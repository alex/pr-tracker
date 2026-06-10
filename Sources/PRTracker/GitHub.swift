import Foundation

struct PRRef: Hashable, Sendable {
    let owner: String
    let name: String
    let number: Int
    var id: String { "\(owner)/\(name)#\(number)" }
}

func parsePRURL(_ raw: String) -> PRRef? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let host = url.host?.lowercased(),
          host == "github.com" || host == "www.github.com"
    else { return nil }
    let parts = url.path.split(separator: "/").map(String.init)
    guard parts.count >= 4, parts[2] == "pull", let n = Int(parts[3]) else { return nil }
    return PRRef(owner: parts[0], name: parts[1], number: n)
}

enum GitHubError: LocalizedError {
    case ghMissing
    case tokenFailed
    case http(Int)
    case graphQL(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .ghMissing:
            "Couldn't find the gh CLI. Install it (brew install gh) and run `gh auth login`."
        case .tokenFailed:
            "Couldn't get a GitHub token from gh. Run `gh auth login` in a terminal."
        case .http(let code):
            code == 401 ? "GitHub rejected the token (401). Run `gh auth login`." : "GitHub returned HTTP \(code)."
        case .graphQL(let msg):
            msg
        case .notFound:
            "No pull request found at that URL."
        }
    }
}

actor GitHubClient {
    static let shared = GitHubClient()
    private var cachedToken: String?

    // CFNetwork heuristically caches the GraphQL POST responses (GitHub sends
    // no Cache-Control header), serving stale check states even on manual
    // refresh. Use a session with caching disabled entirely.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private func ghToken(forceRefresh: Bool = false) throws -> String {
        if !forceRefresh, let t = cachedToken { return t }
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh",
            "/run/current-system/sw/bin/gh",
        ]
        let process = Process()
        if let gh = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            process.executableURL = URL(fileURLWithPath: gh)
            process.arguments = ["auth", "token"]
        } else {
            // Fall back to PATH lookup (covers unusual install locations when
            // launched from a terminal).
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "auth", "token"]
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw GitHubError.ghMissing
        }
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { throw GitHubError.tokenFailed }
        cachedToken = token
        return token
    }

    func fetch(_ ref: PRRef) async throws -> TrackedPR {
        do {
            return try await doFetch(ref, token: ghToken())
        } catch GitHubError.http(401) {
            return try await doFetch(ref, token: ghToken(forceRefresh: true))
        }
    }

    private static let query = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          number title url headRefName isDraft merged closed mergedAt createdAt
          author { login }
          reviewDecision
          reviewRequests(first: 10) {
            nodes { requestedReviewer { ... on User { login } ... on Team { slug } } }
          }
          latestOpinionatedReviews(first: 10) { nodes { state author { login } } }
          reviewThreads(first: 100) { totalCount nodes { isResolved } }
          comments { totalCount }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  state
                  contexts(first: 100) {
                    totalCount
                    nodes {
                      ... on CheckRun { status conclusion }
                      ... on StatusContext { state }
                    }
                  }
                }
              }
            }
          }
          repository { nameWithOwner }
        }
      }
    }
    """

    private func doFetch(_ ref: PRRef, token: String) async throws -> TrackedPR {
        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "query": Self.query,
            "variables": ["owner": ref.owner, "name": ref.name, "number": ref.number],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw GitHubError.http(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let g = try decoder.decode(GQLResponse.self, from: data)
        guard let pr = g.data?.repository?.pullRequest else {
            if let msg = g.errors?.first?.message { throw GitHubError.graphQL(msg) }
            throw GitHubError.notFound
        }

        let reviewers = (pr.reviewRequests?.nodes ?? [])
            .compactMap { $0?.requestedReviewer }
            .compactMap { $0.login ?? $0.slug }

        var changesRequestedBy: String?
        if pr.reviewDecision == "CHANGES_REQUESTED" {
            changesRequestedBy = (pr.latestOpinionatedReviews?.nodes ?? [])
                .compactMap { $0 }
                .first { $0.state == "CHANGES_REQUESTED" }?.author?.login ?? "reviewer"
        }

        let threads = (pr.reviewThreads?.nodes ?? []).compactMap { $0 }
        let unresolved = threads.filter { !$0.isResolved }.count
        let commentCount = (pr.comments?.totalCount ?? 0) + (pr.reviewThreads?.totalCount ?? 0)

        var ci = CIState.none
        var checksTotal = 0
        var checksRunning = 0
        if let rollup = (pr.commits?.nodes ?? []).compactMap({ $0 }).first?.commit.statusCheckRollup {
            switch rollup.state {
            case "SUCCESS": ci = .pass
            case "FAILURE", "ERROR": ci = .fail
            case "PENDING", "EXPECTED": ci = .running
            default: ci = .none
            }
            let ctxs = (rollup.contexts?.nodes ?? []).compactMap { $0 }
            checksTotal = rollup.contexts?.totalCount ?? ctxs.count
            checksRunning = ctxs.filter { c in
                if let status = c.status { return status != "COMPLETED" }
                if let state = c.state { return state == "PENDING" || state == "EXPECTED" }
                return false
            }.count
        }

        return TrackedPR(
            repo: pr.repository.nameWithOwner,
            number: pr.number,
            url: pr.url,
            title: pr.title,
            branch: pr.headRefName,
            author: pr.author?.login,
            isDraft: pr.isDraft,
            reviewers: reviewers,
            changesRequestedBy: changesRequestedBy,
            unresolvedThreads: unresolved,
            commentCount: commentCount,
            ci: ci,
            checksTotal: checksTotal,
            checksRunning: checksRunning,
            merged: pr.merged,
            closed: pr.closed,
            mergedAt: pr.mergedAt,
            createdAt: pr.createdAt,
            addedAt: .now,
            completedSeenAt: nil,
            manuallyMerged: false,
            dependsOn: nil
        )
    }
}

// MARK: - GraphQL response shapes

private struct GQLResponse: Decodable {
    struct ErrorMsg: Decodable { let message: String }
    struct DataObj: Decodable { let repository: Repo? }
    struct Repo: Decodable { let pullRequest: PR? }
    struct Actor: Decodable { let login: String }
    struct Nodes<T: Decodable>: Decodable {
        let totalCount: Int?
        let nodes: [T?]?
    }
    struct ReviewRequest: Decodable { let requestedReviewer: Reviewer? }
    struct Reviewer: Decodable {
        let login: String?
        let slug: String?
    }
    struct Review: Decodable {
        let state: String
        let author: Actor?
    }
    struct Thread: Decodable { let isResolved: Bool }
    struct CommitNode: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable {
        let state: String
        let contexts: Nodes<Ctx>?
    }
    struct Ctx: Decodable {
        let status: String?
        let conclusion: String?
        let state: String?
    }
    struct Counted: Decodable { let totalCount: Int? }
    struct RepoName: Decodable { let nameWithOwner: String }

    struct PR: Decodable {
        let number: Int
        let title: String
        let url: String
        let headRefName: String
        let isDraft: Bool
        let merged: Bool
        let closed: Bool
        let mergedAt: Date?
        let createdAt: Date
        let author: Actor?
        let reviewDecision: String?
        let reviewRequests: Nodes<ReviewRequest>?
        let latestOpinionatedReviews: Nodes<Review>?
        let reviewThreads: Nodes<Thread>?
        let comments: Counted?
        let commits: Nodes<CommitNode>?
        let repository: RepoName
    }

    let data: DataObj?
    let errors: [ErrorMsg]?
}
