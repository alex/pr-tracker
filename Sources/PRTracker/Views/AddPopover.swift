import SwiftUI

struct AddPopoverView: View {
    @Environment(Store.self) private var store
    let flow: AddFlow

    var body: some View {
        switch flow.kind {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Fetching pull request…").font(.system(size: 13))
            }
            .padding(20)
            .frame(width: 300, alignment: .leading)

        case .invalid:
            VStack(alignment: .leading, spacing: 6) {
                Label("Not a pull-request link", systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Copy a GitHub PR URL like github.com/owner/repo/pull/123 and paste again.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300, alignment: .leading)

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't fetch that pull request", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)

        case .alreadyTracked(let id):
            VStack(alignment: .leading, spacing: 8) {
                Label("Already tracking", systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                if let pr = store.pr(id: id) {
                    Text(verbatim: "\(pr.title)  #\(pr.number)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack {
                    Spacer()
                    Button("Show in List") { store.reveal(id) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)

        case .preview(let pr):
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.merged)
                        Text("Found on github.com")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 10)
                    HStack(alignment: .top, spacing: 10) {
                        CIBadgeView(state: pr.ci).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(pr.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: "#\(pr.number)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(verbatim: "\(pr.repo) · \(pr.branch)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let reviewer = pr.reviewers.first {
                                    ChipView(text: "review: \(reviewer)", color: Palette.review)
                                }
                                checksChip(pr)
                            }
                            .padding(.top, 5)
                        }
                    }
                }
                .padding(16)
                Divider()
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { store.addFlow = nil }
                    Button("Add Pull Request") { store.confirmAdd(pr) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(width: 340)
        }
    }

    @ViewBuilder
    private func checksChip(_ pr: TrackedPR) -> some View {
        switch pr.ci {
        case .pass: ChipView(text: "checks passed")
        case .fail: ChipView(text: "checks failed", color: Palette.fail)
        case .running: ChipView(text: "checks running")
        case .none: EmptyView()
        }
    }
}
