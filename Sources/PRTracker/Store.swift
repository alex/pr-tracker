import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class Store {
    var prs: [TrackedPR] = []
    var filter: SidebarFilter = .all
    var selection: String?
    var addFlow: AddFlow?
    var lastError: String?
    var scrollTarget: String?
    var mergedCollapsed = true

    private var lastRefresh: Date?
    var isRefreshing = false

    /// Merged/closed PRs are kept for reference and pruned after this long.
    private static let prunedAfter: TimeInterval = 3 * 86400
    private static let pollInterval: TimeInterval = 5 * 60

    private var saveURL: URL {
        // Debug aid: PRTRACKER_DATA_DIR points the store at an alternate
        // directory (Foundation ignores $HOME, so tests can't redirect it).
        let dir = if let override = ProcessInfo.processInfo.environment["PRTRACKER_DATA_DIR"] {
            URL(fileURLWithPath: override, isDirectory: true)
        } else {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PRTracker", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("prs.json")
    }

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([TrackedPR].self, from: data) {
            prs = loaded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(prs) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    // MARK: - Lookup & derivation

    func pr(id: String) -> TrackedPR? {
        prs.first { $0.id == id }
    }

    func derivedState(_ pr: TrackedPR) -> WaitingState {
        if pr.merged || pr.closed || pr.manuallyMerged { return .merged }
        if let dep = pr.dependsOn, let blocker = self.pr(id: dep),
           !(blocker.merged || blocker.closed || blocker.manuallyMerged) {
            return .blocked
        }
        if pr.isDraft { return .you }
        if pr.changesRequestedBy != nil || pr.unresolvedThreads > 0 || pr.ci == .fail { return .you }
        if pr.ci == .running { return .ci }
        return .review
    }

    func reason(_ pr: TrackedPR, state: WaitingState) -> String {
        switch state {
        case .merged:
            if pr.closed && !pr.merged && !pr.manuallyMerged { return "Closed" }
            if let d = pr.mergedAt ?? pr.completedSeenAt { return "Merged \(relAge(d)) ago" }
            return "Merged"
        case .blocked:
            if let dep = pr.dependsOn, let blocker = self.pr(id: dep) {
                return "Blocked until #\(blocker.number) merges"
            }
            return "Blocked"
        case .you:
            if let who = pr.changesRequestedBy { return "Changes requested by \(who)" }
            if pr.unresolvedThreads > 0 {
                return "\(pr.unresolvedThreads) unresolved comment\(pr.unresolvedThreads == 1 ? "" : "s")"
            }
            if pr.ci == .fail { return "Checks failed" }
            return "Draft — not ready for review"
        case .ci:
            if pr.checksTotal > 0 { return "\(pr.checksRunning) of \(pr.checksTotal) checks running" }
            return "Checks running"
        case .review:
            if let r = pr.reviewers.first { return "Awaiting review from \(r)" }
            return "Awaiting review"
        }
    }

    // MARK: - Grouped list

    var sections: [GroupSection] {
        let inScope: [TrackedPR] = switch filter {
        case .repo(let r): prs.filter { $0.repo == r }
        default: prs
        }
        let derived = Dictionary(uniqueKeysWithValues: inScope.map { ($0.id, derivedState($0)) })
        let inScopeIDs = Set(inScope.map(\.id))

        // Position in `prs` is the display order; drag-reorder moves items
        // there and save() persists it.
        let order = Dictionary(uniqueKeysWithValues: prs.enumerated().map { ($0.element.id, $0.offset) })
        func byOrder(_ a: TrackedPR, _ b: TrackedPR) -> Bool {
            order[a.id, default: .max] < order[b.id, default: .max]
        }

        func item(_ pr: TrackedPR, depth: Int) -> RowItem {
            let s = derived[pr.id]!
            return RowItem(pr: pr, depth: depth, state: s, reason: reason(pr, state: s))
        }

        if case .state(let s) = filter {
            let items = inScope.filter { derived[$0.id] == s }.sorted(by: byOrder)
                .map { item($0, depth: 0) }
            return items.isEmpty ? [] : [GroupSection(state: s, items: items)]
        }

        // All transitive dependents of a root, flattened to one indent level
        // (a chain A ← B ← C lists B then C under A, both at depth 1; each
        // row's "after #N" chip still names its direct blocker).
        func chain(under rootID: String) -> [RowItem] {
            var out: [RowItem] = []
            var seen: Set<String> = [rootID]
            func visit(_ id: String) {
                let dependents = inScope
                    .filter { $0.dependsOn == id && derived[$0.id] == .blocked }
                    .sorted(by: byOrder)
                for child in dependents where !seen.contains(child.id) {
                    seen.insert(child.id)
                    out.append(item(child, depth: 1))
                    visit(child.id)
                }
            }
            visit(rootID)
            return out
        }

        var out: [GroupSection] = []
        for group in [WaitingState.you, .review, .ci, .blocked, .merged] {
            let roots = inScope.filter { p in
                guard let d = derived[p.id] else { return false }
                if d == .blocked {
                    // A blocked PR nests under its blocker when the blocker is
                    // visible; otherwise it surfaces in the Blocked section.
                    let blockerVisible = p.dependsOn.map { inScopeIDs.contains($0) } ?? false
                    return group == .blocked && !blockerVisible
                }
                return d == group
            }.sorted(by: byOrder)
            let items = roots.flatMap { [item($0, depth: 0)] + chain(under: $0.id) }
            if !items.isEmpty { out.append(GroupSection(state: group, items: items)) }
        }
        return out
    }

    // MARK: - Sidebar data

    var openCount: Int {
        prs.filter { derivedState($0) != .merged }.count
    }

    func count(for state: WaitingState) -> Int {
        prs.filter { derivedState($0) == state }.count
    }

    var repos: [(name: String, count: Int)] {
        Dictionary(grouping: prs.filter { derivedState($0) != .merged }, by: \.repo)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Add flow

    func handlePaste() {
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        guard let ref = parsePRURL(pasted) else {
            addFlow = AddFlow(kind: .invalid)
            return
        }
        if prs.contains(where: { $0.id == ref.id }) {
            addFlow = AddFlow(kind: .alreadyTracked(ref.id))
            return
        }
        let flow = AddFlow(kind: .loading)
        addFlow = flow
        Task {
            do {
                let pr = try await GitHubClient.shared.fetch(ref)
                if addFlow?.id == flow.id { addFlow?.kind = .preview(pr) }
            } catch {
                if addFlow?.id == flow.id { addFlow?.kind = .error(error.localizedDescription) }
            }
        }
    }

    func confirmAdd(_ pr: TrackedPR) {
        addFlow = nil
        guard self.pr(id: pr.id) == nil else {
            reveal(pr.id)
            return
        }
        var added = pr
        if (added.merged || added.closed) && added.completedSeenAt == nil {
            added.completedSeenAt = .now
        }
        prs.append(added)
        save()
        reveal(added.id)
    }

    func reveal(_ id: String) {
        addFlow = nil
        if case .repo(let r) = filter, pr(id: id)?.repo != r { filter = .all }
        if case .state = filter { filter = .all }
        if let p = pr(id: id), derivedState(p) == .merged { mergedCollapsed = false }
        selection = id
        scrollTarget = id
    }

    // MARK: - Manual reordering

    /// id of the row being dragged, while a reorder drag is in flight.
    var draggingID: String?

    /// Rows may swap only when they are siblings in the displayed list: same
    /// section, same depth and (for nested rows) the same direct blocker.
    private func areSiblings(_ a: RowItem, _ b: RowItem) -> Bool {
        a.depth == b.depth && (a.depth == 0 || a.pr.dependsOn == b.pr.dependsOn)
    }

    func reorder(_ draggedID: String, over targetID: String) {
        guard draggedID != targetID,
              let section = sections.first(where: { $0.items.contains { $0.id == draggedID } }),
              let dragged = section.items.first(where: { $0.id == draggedID }),
              let target = section.items.first(where: { $0.id == targetID }),
              areSiblings(dragged, target),
              let from = prs.firstIndex(where: { $0.id == draggedID }),
              let to = prs.firstIndex(where: { $0.id == targetID })
        else { return }
        prs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    // MARK: - Row actions

    func openOnGitHub(_ pr: TrackedPR) {
        if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
    }

    func copyURL(_ pr: TrackedPR) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url, forType: .string)
    }

    func copySelectedURL() {
        if let id = selection, let pr = pr(id: id) { copyURL(pr) }
    }

    func remove(_ id: String) {
        prs.removeAll { $0.id == id }
        for i in prs.indices where prs[i].dependsOn == id {
            prs[i].dependsOn = nil
        }
        if selection == id { selection = nil }
        save()
    }

    func markMerged(_ id: String) {
        guard let i = prs.firstIndex(where: { $0.id == id }) else { return }
        prs[i].manuallyMerged = true
        if prs[i].completedSeenAt == nil { prs[i].completedSeenAt = .now }
        save()
    }

    func blockerCandidates(for pr: TrackedPR) -> [TrackedPR] {
        prs.filter { $0.id != pr.id && derivedState($0) != .merged }
            .sorted { ($0.repo, $0.number) < ($1.repo, $1.number) }
    }

    func wouldCycle(child: String, blocker: String) -> Bool {
        var current: String? = blocker
        var hops = 0
        while let c = current, hops < 100 {
            if c == child { return true }
            current = pr(id: c)?.dependsOn
            hops += 1
        }
        return false
    }

    func setDependency(of childID: String, on blockerID: String?) {
        guard let i = prs.firstIndex(where: { $0.id == childID }) else { return }
        if let blockerID {
            guard pr(id: blockerID) != nil, !wouldCycle(child: childID, blocker: blockerID) else { return }
        }
        prs[i].dependsOn = blockerID
        save()
    }

    // MARK: - Refresh

    func startPolling() async {
        await refreshAll()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.pollInterval))
            await refreshAll()
        }
    }

    func refreshIfStale() async {
        if let last = lastRefresh, Date.now.timeIntervalSince(last) < 60 { return }
        await refreshAll()
    }

    func refreshAll() async {
        guard !prs.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefresh = .now

        // Done PRs never change again; skipping them keeps refresh cost
        // bounded by the number of open PRs.
        let refs = prs.filter { !($0.merged || $0.closed || $0.manuallyMerged) }
            .compactMap { pr -> PRRef? in
                let parts = pr.repo.split(separator: "/").map(String.init)
                guard parts.count == 2 else { return nil }
                return PRRef(owner: parts[0], name: parts[1], number: pr.number)
            }

        var firstError: String?
        await withTaskGroup(of: (String, Result<TrackedPR, Error>).self) { group in
            for ref in refs {
                group.addTask {
                    do {
                        return (ref.id, .success(try await GitHubClient.shared.fetch(ref)))
                    } catch {
                        return (ref.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let fresh):
                    if let i = prs.firstIndex(where: { $0.id == id }) {
                        prs[i] = merge(old: prs[i], fresh: fresh)
                    }
                case .failure(let error):
                    if firstError == nil { firstError = error.localizedDescription }
                }
            }
        }
        lastError = firstError

        // Drop dependencies that point at PRs no longer tracked.
        for i in prs.indices {
            if let dep = prs[i].dependsOn, pr(id: dep) == nil { prs[i].dependsOn = nil }
        }
        // Prune long-done PRs.
        let cutoff = Date.now.addingTimeInterval(-Self.prunedAfter)
        prs.removeAll { pr in
            guard let done = pr.completedSeenAt else { return false }
            return (pr.merged || pr.closed || pr.manuallyMerged) && done < cutoff
        }
        save()
    }

    private func merge(old: TrackedPR, fresh: TrackedPR) -> TrackedPR {
        var pr = fresh
        pr.addedAt = old.addedAt
        pr.dependsOn = old.dependsOn
        pr.manuallyMerged = old.manuallyMerged
        pr.completedSeenAt = old.completedSeenAt
        if (pr.merged || pr.closed || pr.manuallyMerged) && pr.completedSeenAt == nil {
            pr.completedSeenAt = .now
        }
        return pr
    }
}
