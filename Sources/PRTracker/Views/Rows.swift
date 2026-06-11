import SwiftUI

struct NestedRowView: View {
    let item: RowItem

    var body: some View {
        PRRowView(item: item)
            .padding(.leading, CGFloat(item.depth) * 34)
            .overlay(alignment: .topLeading) {
                if item.depth > 0 {
                    ConnectorShape()
                        .stroke(
                            Palette.blocked.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 11, height: 30)
                        .offset(x: CGFloat(item.depth - 1) * 34 + 21, y: -8)
                }
            }
    }
}

struct PRRowView: View {
    @Environment(Store.self) private var store
    let item: RowItem
    @State private var hovering = false

    // Everything displayed is derived from the store, not the captured item:
    // the Lazy stack can reuse a row's view when a PR moves between sections,
    // leaving a snapshot taken at insert time on screen. Reading through the
    // store makes Observation re-render the row whenever a refresh updates
    // `prs`, so row content can never go stale.
    private var pr: TrackedPR { store.pr(id: item.id) ?? item.pr }
    private var state: WaitingState { store.derivedState(pr) }
    private var selected: Bool { store.selection == pr.id }

    private var avatarName: String? {
        switch state {
        case .you: pr.author
        case .review, .merged: pr.changesRequestedBy ?? pr.reviewers.first
        case .ci, .blocked: nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            CIBadgeView(state: pr.ci)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(verbatim: "#\(pr.number)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .layoutPriority(1)
                }
                HStack(spacing: 6) {
                    Text(pr.repo).foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(store.reason(pr, state: state)).foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let depID = pr.dependsOn, let blocker = store.pr(id: depID),
               store.derivedState(blocker) != .merged {
                ChipView(text: "after #\(blocker.number)", color: Palette.blocked)
            }
            if pr.commentCount > 0 {
                HStack(spacing: 3) {
                    Text(verbatim: "\(pr.commentCount)").monospacedDigit()
                    Image(systemName: "bubble.left").font(.system(size: 10))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            }
            AvatarView(name: avatarName)
            Text(relAge(pr.createdAt))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected
                    ? Palette.review.opacity(0.12)
                    : hovering ? Color.primary.opacity(0.045) : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .opacity(state == .merged ? 0.55 : 1)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { store.openOnGitHub(pr) }
        .onTapGesture { store.selection = pr.id }
        .contextMenu { RowContextMenu(pr: pr) }
    }
}

struct RowContextMenu: View {
    @Environment(Store.self) private var store
    let pr: TrackedPR

    var body: some View {
        Button("Open on GitHub") { store.openOnGitHub(pr) }
        Button("Copy URL") { store.copyURL(pr) }
        Divider()
        Menu("Blocked by") {
            let candidates = store.blockerCandidates(for: pr)
            ForEach(candidates) { cand in
                Toggle(isOn: Binding(
                    get: { pr.dependsOn == cand.id },
                    set: { on in store.setDependency(of: pr.id, on: on ? cand.id : nil) }
                )) {
                    Text(verbatim: "#\(cand.number) · \(cand.title)")
                }
                .disabled(store.wouldCycle(child: pr.id, blocker: cand.id))
            }
            if !candidates.isEmpty { Divider() }
            Button("None (clear)") { store.setDependency(of: pr.id, on: nil) }
                .disabled(pr.dependsOn == nil)
        }
        Button("Mark as Merged") { store.markMerged(pr.id) }
            .disabled(store.derivedState(pr) == .merged)
        Divider()
        Button("Remove from Tracker", role: .destructive) { store.remove(pr.id) }
    }
}
