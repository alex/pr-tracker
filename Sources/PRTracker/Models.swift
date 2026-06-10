import Foundation

enum CIState: String, Codable {
    case pass, fail, running, none
}

enum WaitingState: String, Codable, CaseIterable, Identifiable, Hashable {
    case you, review, ci, blocked, merged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .you: "Waiting on you"
        case .review: "Waiting on review"
        case .ci: "Waiting on CI"
        case .blocked: "Blocked"
        case .merged: "Merged"
        }
    }
}

struct TrackedPR: Codable, Identifiable, Hashable, Sendable {
    var repo: String // "owner/name"
    var number: Int
    var url: String
    var title: String
    var branch: String
    var author: String?
    var isDraft: Bool
    var reviewers: [String]
    var changesRequestedBy: String?
    var unresolvedThreads: Int
    var commentCount: Int
    var ci: CIState
    var checksTotal: Int
    var checksRunning: Int
    var merged: Bool
    var closed: Bool
    var mergedAt: Date?
    var createdAt: Date
    var addedAt: Date
    // When we first observed the PR merged/closed; drives pruning.
    var completedSeenAt: Date?
    var manuallyMerged: Bool
    // id of the tracked PR this one is blocked by.
    var dependsOn: String?

    var id: String { "\(repo)#\(number)" }
}

enum SidebarFilter: Hashable {
    case all
    case state(WaitingState)
    case repo(String)
}

struct RowItem: Identifiable {
    let pr: TrackedPR
    let depth: Int
    let state: WaitingState
    let reason: String
    var id: String { pr.id }
}

struct GroupSection: Identifiable {
    let state: WaitingState
    let items: [RowItem]
    var id: String { state.rawValue }
}

struct AddFlow: Identifiable {
    enum Kind {
        case loading
        case invalid
        case alreadyTracked(String)
        case error(String)
        case preview(TrackedPR)
    }
    let id = UUID()
    var kind: Kind
}

func relAge(_ date: Date, now: Date = .now) -> String {
    let s = max(0, now.timeIntervalSince(date))
    if s < 3600 { return "\(max(1, Int(s / 60)))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    if s < 86400 * 21 { return "\(Int(s / 86400))d" }
    return "\(Int(s / (86400 * 7)))w"
}
