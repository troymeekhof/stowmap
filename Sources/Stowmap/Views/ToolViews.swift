import SwiftUI

// Search results and duplicates: the two screens that look across every scanned drive at once.

// MARK: - Shared pieces

/// Small label naming the drive a result lives on.
struct DriveBadge: View {
    var name: String
    var body: some View {
        Text(name)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Theme.cyan)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.cyan.opacity(0.14)))
    }
}

/// Which scans a cross-drive result is based on, and how old they are.
struct ScanBasis: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let roots = model.scannedRoots()
        let waiting = model.unscannedNames
        VStack(alignment: .leading, spacing: 3) {
            if roots.isEmpty {
                Text("No drive has been scanned yet. Scan one from the sidebar first.")
            } else {
                Text("Based on: " + roots.map { "\($0.name) (\($0.fromCache ? "saved " : "")\(Fmt.ago($0.date)))" }
                    .joined(separator: ", "))
            }
            if !waiting.isEmpty {
                Text("Not scanned, so not included: " + waiting.joined(separator: ", "))
            }
        }
        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A file or folder shown with the drive and folder it lives in.
struct LocatedRow: View {
    @EnvironmentObject var model: AppModel
    var node: FileNode
    var volumeID: String
    var volumeName: String
    var folder: String
    var fraction: Double
    var canCollect: Bool = true        // false when this is the last copy left in its group
    @State private var hover = false

    var body: some View {
        let on = model.isCollected(node, in: volumeID)
        HStack(spacing: 8) {
            NodeIcon(node: node)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    DriveBadge(name: volumeName)
                    Text(folder).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            MeterBar(fraction: fraction, color: node.isFolder ? Theme.cyan : Theme.lilac, height: 4)
                .frame(width: 80)
            Text(Fmt.bytes(node.size)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).frame(width: 78, alignment: .trailing)
            IconButton(symbol: on ? "tray.full.fill" : "tray.and.arrow.down",
                       help: on ? "Remove from Collector"
                           : (canCollect ? "Add to Collector" : "This is the last copy. Stowmap keeps one."),
                       tint: on ? Theme.amber : Theme.textSecondary) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    model.toggleCollect(node, in: volumeID)
                }
            }
            .disabled(!on && !canCollect)
            .opacity(!on && !canCollect ? 0.3 : 1)
            IconButton(symbol: "chart.pie", help: "Show its folder on the map") {
                model.showOnMap(volumeID: volumeID, folderPath: node.isFolder ? node.path : folder)
            }
            IconButton(symbol: node.isFolder ? "folder" : "magnifyingglass",
                       help: node.isFolder ? "Open in Finder" : "Reveal in Finder") {
                Finder.show(node)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hover ? 0.07 : 0.0001)))
        .onHover { hover = $0 }
        .contextMenu {
            Button(node.isFolder ? "Open in Finder" : "Reveal in Finder") { Finder.show(node) }
            Button("Quick Look") { Finder.quickLook(node.path) }
            Button("Copy Path") { Finder.copyPath(node.path) }
        }
    }
}

/// Collector summary for screens that span drives.
struct SharedCollectorBar: View {
    @EnvironmentObject var model: AppModel
    @State private var confirm = false

    var body: some View {
        let count = model.collectedCount
        Card(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").font(.system(size: 15)).foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Collector, all drives").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary).textCase(.uppercase)
                    Text("\(count) item\(count == 1 ? "" : "s")  ·  \(Fmt.bytes(model.collectedBytes))")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer(minLength: 8)
                Button("Clear") { withAnimation { model.clearAllCollected() } }
                    .buttonStyle(QuietButtonStyle())
                Button { confirm = true } label: { Label("Move to Trash", systemImage: "trash.fill") }
                    .buttonStyle(QuietButtonStyle(tint: Theme.bad))
            }
        }
        .confirmationDialog("Move \(count) item\(count == 1 ? "" : "s") to the Trash?", isPresented: $confirm) {
            Button("Move to Trash (\(Fmt.bytes(model.collectedBytes)))", role: .destructive) {
                withAnimation { model.trashAllCollected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each item goes to the Trash on its own drive. Network shares without a Trash will refuse, and nothing is deleted there.")
        }
    }
}

private struct ToolHeader<Trailing: View>: View {
    @EnvironmentObject var model: AppModel
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
            IconButton(symbol: "xmark", help: "Back to the drive") {
                withAnimation(.easeOut(duration: 0.18)) { model.pane = .drive }
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var model: AppModel

    private var subtitle: String {
        if model.searchBusy { return "Searching…" }
        if model.searchedFor.isEmpty { return "Find files and folders by name on every drive you've scanned." }
        let shown = model.searchResults.count
        if model.searchTotal > shown {
            return "\(Fmt.count(model.searchTotal)) matches for “\(model.searchedFor)”. Showing the \(shown) largest."
        }
        return "\(Fmt.count(model.searchTotal)) match\(model.searchTotal == 1 ? "" : "es") for “\(model.searchedFor)”."
    }

    var body: some View {
        let top = Double(max(1, model.searchResults.first?.node.size ?? 1))
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "Search", subtitle: subtitle) {
                GlassTabs(selection: $model.searchKind, tabs: [
                    ("All", "square.grid.2x2"), ("Folders", "folder"), ("Files", "doc"),
                ])
                .frame(width: 300)
            }
            ScanBasis()

            Card(padding: 8) {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.searchResults) { hit in
                            LocatedRow(node: hit.node, volumeID: hit.volumeID, volumeName: hit.volumeName,
                                       folder: hit.node.parent?.path ?? "",
                                       fraction: Double(hit.node.size) / top)
                        }
                        if model.searchResults.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").font(.system(size: 26, weight: .light))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(model.searchedFor.isEmpty
                                     ? "Type in the search box in the sidebar and press Return."
                                     : "Nothing on the scanned drives has “\(model.searchedFor)” in its name.")
                                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                                Text("Files under 128 KB are grouped per folder and can't be found one by one. Maps reopened from a saved scan only hold larger items; rescan for full detail.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.collectedCount > 0 { SharedCollectorBar() }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
        .onChange(of: model.searchKind) { _ in model.runSearch() }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("dupMinMB") private var minMB = 10

    private let sizes: [(label: String, mb: Int)] = [
        ("1 MB and up", 1), ("10 MB and up", 10), ("100 MB and up", 100), ("1 GB and up", 1000),
    ]

    private var subtitle: String {
        switch model.dupPhase {
        case .idle: return "Find identical files across every drive you've scanned."
        case .running: return model.dupProgress.stage.isEmpty ? "Starting…" : model.dupProgress.stage + "…"
        case .done:
            let wasted = model.dupGroups.reduce(Int64(0)) { $0 + $1.wasted }
            if model.dupGroups.isEmpty { return "No duplicates of that size on the scanned drives." }
            return "\(Fmt.count(model.dupGroups.count)) sets of copies. Keeping one of each would free \(Fmt.bytes(wasted))."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "Duplicates", subtitle: subtitle) {
                Menu {
                    ForEach(sizes, id: \.mb) { s in
                        Button(s.label) { minMB = s.mb }
                    }
                } label: {
                    Label(sizes.first(where: { $0.mb == minMB })?.label ?? "10 MB and up",
                          systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(model.dupPhase == .running)
                if model.dupPhase == .running {
                    Button("Cancel") { model.cancelDuplicates() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button { model.findDuplicates(minSize: Int64(minMB) * 1_000_000) } label: {
                        Label(model.dupPhase == .done ? "Check Again" : "Find Duplicates",
                              systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(GlowButtonStyle())
                }
            }
            ScanBasis()

            Group {
                switch model.dupPhase {
                case .idle: explainer
                case .running: running
                case .done: results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.collectedCount > 0 { SharedCollectorBar() }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
        .alert("Some items couldn't be moved", isPresented: Binding(
            get: { model.toolError != nil }, set: { if !$0 { model.toolError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.toolError ?? "")
        }
    }

    private var explainer: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                CardTitle(text: "How it matches", symbol: "checklist")
                step("1", "Same size", "Uses the sizes already in each drive's map. Nothing is read from disk.")
                step("2", "Same samples", "Reads a small piece from the start, middle and end of each candidate. Fast, even for large clips on a network share.")
                step("3", "Verify, when you ask", "Reads the copies from start to end and compares them. Do this before trashing anything you can't replace.")
                Text("Stowmap always leaves one copy of every set. Renamed copies are found; re-exports and transcodes of the same footage are different files and are not.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var running: some View {
        let p = model.dupProgress
        return Card(padding: 24) {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(p.stage.isEmpty ? "Starting…" : p.stage)
                    .font(.system(size: 14, weight: .semibold))
                if p.total > 0 {
                    MeterBar(fraction: Double(p.checked) / Double(max(1, p.total)), color: Theme.cyan, height: 6)
                        .frame(maxWidth: 360)
                    Text("\(Fmt.count(p.checked)) of \(Fmt.count(p.total)) files")
                        .font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var results: some View {
        Card(padding: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.dupGroups) { group in
                        DupGroupView(group: group)
                    }
                    if model.dupGroups.isEmpty {
                        Text("Nothing to show. Try a smaller minimum size, or scan more drives.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct DupGroupView: View {
    @EnvironmentObject var model: AppModel
    var group: DupGroup

    var body: some View {
        let remaining = group.items.filter { !model.isCollected($0.node, in: $0.volumeID) }.count
        let verifying = model.dupVerifying.contains(group.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(group.items.count) copies")
                    .font(.system(size: 12.5, weight: .bold))
                Text("\(Fmt.bytes(group.size)) each  ·  \(group.driveCount == 1 ? "one drive" : "\(group.driveCount) drives")  ·  \(Fmt.bytes(group.wasted)) to free")
                    .font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                statePill
                if verifying {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                } else if group.state == .sampled || group.state == .unreadable {
                    Button("Verify") { model.verifyGroup(group.id) }
                        .buttonStyle(QuietButtonStyle())
                        .help("Read every copy from start to end and compare them")
                }
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)

            ForEach(group.items) { item in
                LocatedRow(node: item.node, volumeID: item.volumeID, volumeName: item.volumeName,
                           folder: item.folder, fraction: 1,
                           canCollect: group.state != .different && remaining > 1)
            }
        }
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    @ViewBuilder
    private var statePill: some View {
        switch group.state {
        case .sampled: Pill(text: "Samples match", color: Theme.amber)
        case .identical: Pill(text: "Verified identical", color: Theme.good)
        case .different: Pill(text: "Not identical", color: Theme.bad)
        case .unreadable: Pill(text: "Couldn't read a copy", color: Theme.warn)
        }
    }
}
