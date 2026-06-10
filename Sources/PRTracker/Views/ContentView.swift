import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 300)
        } detail: {
            MainPane()
        }
        .frame(minWidth: 760, minHeight: 440)
        .task { snapshotIfRequested(store) }
        .task { await store.startPolling() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await store.refreshIfStale() }
        }
    }
}

// Debug aid: PRTRACKER_SNAPSHOT=/path.png renders the window to a PNG a few
// seconds after launch (self-window capture needs no screen-recording grant).
@MainActor
private func snapshotIfRequested(_ store: Store) {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["PRTRACKER_SNAPSHOT"] else { return }
    if env["PRTRACKER_LIGHT"] != nil {
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    Task { @MainActor in
        if let url = env["PRTRACKER_PASTE"] {
            try? await Task.sleep(for: .seconds(1))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            store.handlePaste()
        }
        try? await Task.sleep(for: .seconds(4))
        // Deprecated but still the simplest own-window capture (no
        // screen-recording grant needed for windows we own).
        for (i, window) in NSApp.windows.filter(\.isVisible).enumerated() {
            guard let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .bestResolution]
            ) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            let out = i == 0 ? path : path.replacingOccurrences(of: ".png", with: "-\(i).png")
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
}

struct SidebarView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let selection = Binding<SidebarFilter?>(
            get: { store.filter },
            set: { store.filter = $0 ?? .all }
        )
        List(selection: selection) {
            Section("Smart Groups") {
                sidebarRow(label: "All open", color: Palette.ci, count: store.openCount)
                    .tag(SidebarFilter.all)
                ForEach(WaitingState.allCases) { state in
                    sidebarRow(
                        label: state.label,
                        color: Palette.color(for: state),
                        count: store.count(for: state)
                    )
                    .tag(SidebarFilter.state(state))
                }
            }
            if !store.repos.isEmpty {
                Section("Repositories") {
                    ForEach(store.repos, id: \.name) { repo in
                        sidebarRow(
                            label: repo.name,
                            color: Color.primary.opacity(0.25),
                            count: repo.count
                        )
                        .tag(SidebarFilter.repo(repo.name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(label: String, color: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 13)).lineLimit(1)
            Spacer()
            Text(verbatim: "\(count)")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct MainPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow()
            if store.prs.isEmpty {
                EmptyStateView()
            } else {
                PRListView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct HeaderRow: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Pull Requests")
                .font(.system(size: 15, weight: .bold))
            if store.openCount > 0 {
                Text(verbatim: "\(store.openCount) open")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                    .help(error)
            }
            Spacer()
            RefreshButton()
            PasteField()
                .popover(item: $store.addFlow, arrowEdge: .bottom) { flow in
                    AddPopoverView(flow: flow)
                }
        }
        .padding(.top, 10)
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.bottom, 6)
    }
}

struct RefreshButton: View {
    @Environment(Store.self) private var store
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await store.refreshAll() }
        } label: {
            Group {
                if store.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing || store.prs.isEmpty)
        .onHover { hovering = $0 }
        .help("Refresh now (⌘R)")
    }
}

struct PasteField: View {
    @Environment(Store.self) private var store
    @State private var hovering = false

    var body: some View {
        Button { store.handlePaste() } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Paste PR URL to add")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text("⌘V")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary, lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .frame(width: 230, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy a GitHub pull-request link, then click here or press ⌘V")
    }
}

struct PRListView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.sections) { section in
                        // Merged is collapsible (and starts collapsed) except
                        // when it's the sidebar filter itself.
                        let collapsible = section.state == .merged
                            && store.filter != .state(.merged)
                        GroupHeaderView(
                            state: section.state,
                            count: section.items.filter { $0.depth == 0 }.count,
                            collapsed: collapsible ? store.mergedCollapsed : nil
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.mergedCollapsed.toggle()
                            }
                        }
                        if !(collapsible && store.mergedCollapsed) {
                            ForEach(section.items) { item in
                                NestedRowView(item: item)
                                    .id(item.id)
                                    .opacity(store.draggingID == item.id ? 0.45 : 1)
                                    .onDrag {
                                        store.draggingID = item.id
                                        return NSItemProvider(object: item.id as NSString)
                                    }
                                    .onDrop(
                                        of: [.text],
                                        delegate: RowDropDelegate(itemID: item.id, store: store)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .onChange(of: store.scrollTarget) { _, target in
                if let target {
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    store.scrollTarget = nil
                }
            }
        }
    }
}

// Reorders live as the drag passes over sibling rows, so the row follows the
// cursor; the drop itself just ends the gesture.
private struct RowDropDelegate: DropDelegate {
    let itemID: String
    let store: Store

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragged = store.draggingID else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                store.reorder(dragged, over: itemID)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { store.draggingID = nil }
        return true
    }
}

struct EmptyStateView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 18)
                .fill(Palette.review.opacity(0.08))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Palette.review)
                )
                .padding(.bottom, 16)
            Text("No pull requests yet")
                .font(.system(size: 16, weight: .bold))
                .padding(.bottom, 6)
            Text("Copy a PR link from GitHub and paste it here — title, reviewers and CI status come along automatically.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.bottom, 18)
            Button { store.handlePaste() } label: {
                HStack(spacing: 8) {
                    Text("Paste PR URL")
                        .font(.system(size: 13, weight: .semibold))
                    Text("⌘V")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Palette.review.opacity(0.3), lineWidth: 1)
                        )
                }
                .foregroundStyle(Palette.review)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Palette.review.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                )
            }
            .buttonStyle(.plain)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
