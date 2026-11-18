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
    var only: String? = nil        // a volume id, when the result covers one drive
    var body: some View {
        let roots = model.scannedRoots().filter { only == nil || $0.id == only }
        let waiting = only == nil ? model.unscannedNames : []
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

/// Which drives the duplicate check looks in: one tick box per scanned drive.
struct DupDriveChecklist: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let roots = model.scannedRoots()
        VStack(alignment: .leading, spacing: 5) {
            if roots.isEmpty {
                Text("No drive has been scanned yet. Scan one in Drives first.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Look in").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        ForEach(roots, id: \.id) { r in chip(r) }
                    }
                }
            }
            if !model.unscannedNames.isEmpty {
                Text("Not scanned, so not included: " + model.unscannedNames.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ r: TreeRoot) -> some View {
        let on = !model.dupExcluded.contains(r.id)
        return Button { model.toggleDupDrive(r.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? Theme.cyan : Theme.textSecondary)
                Text(r.name).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Theme.textSecondary)
                Text("\(r.fromCache ? "saved " : "")\(Fmt.ago(r.date))").font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(on ? 0.08 : 0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.dupPhase == .running)
        .help(on ? "Untick to leave \(r.name) out of the duplicate check" : "Tick to include \(r.name)")
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
        let locked = SystemPaths.isProtected(node.path)
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
                           : (locked ? "Part of macOS. Stowmap won't collect it."
                              : (canCollect ? "Add to Collector" : "This is the last copy. Stowmap keeps one.")),
                       tint: on ? Theme.amber : Theme.textSecondary) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    model.toggleCollect(node, in: volumeID)
                }
            }
            .disabled(!on && (!canCollect || locked))
            .opacity(!on && (!canCollect || locked) ? 0.3 : 1)
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

/// Progress for a pass over the maps, drawn like the capacity bar under a drive's name.
struct ToolProgressBar: View {
    var fraction: Double
    var active: Bool
    var body: some View {
        MeterBar(fraction: fraction, color: Theme.cyan, height: 6)
            .animation(.easeOut(duration: 0.2), value: fraction)
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: active)
    }
}

struct ToolHeader<Trailing: View>: View {
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
            ToolProgressBar(fraction: model.searchProgress, active: model.searchBusy)
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
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 18)
        .onChange(of: model.searchKind) { _ in model.runSearch() }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("dupMinMB") private var minMB = 10
    @State private var expanded = Set<String>()

    private let sizes: [(label: String, mb: Int)] = [
        ("1 MB and up", 1), ("10 MB and up", 10), ("100 MB and up", 100), ("1 GB and up", 1000), ("10 GB and up", 10000),
    ]

    /// Size, plus a count of whatever else is being left out.
    private var filterLabel: String {
        let size = sizes.first(where: { $0.mb == minMB })?.label ?? "10 MB and up"
        let extra = (model.dupSkipSystem ? 1 : 0) + model.dupIgnored.count
        return extra == 0 ? size : "\(size), \(extra) filter\(extra == 1 ? "" : "s")"
    }

    private var subtitle: String {
        switch model.dupPhase {
        case .idle:
            return "Find identical files \(model.dupWhere)."
        case .running: return model.dupProgress.stage.isEmpty ? "Starting…" : model.dupProgress.stage + "…"
        case .done:
            if model.isVerifying { return "Verifying copies, reading each one in full.  \(Fmt.pct(model.verifyOverall))" }
            let wasted = model.dupGroups.reduce(Int64(0)) { $0 + $1.wasted }
            if model.dupGroups.isEmpty {
                return "No duplicates of that size \(model.dupWhere)."
            }
            return "\(Fmt.count(model.dupMatches.count)) folder match\(model.dupMatches.count == 1 ? "" : "es"), \(Fmt.count(model.dupGroups.count)) duplicated files. Keeping one copy of each would free \(Fmt.bytes(wasted))."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "Duplicates", subtitle: subtitle) {
                Menu {
                    Picker("Smallest file to compare", selection: $minMB) {
                        ForEach(sizes, id: \.mb) { s in
                            Text(s.label).tag(s.mb)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Skip system and app files", isOn: Binding(
                        get: { model.dupSkipSystem }, set: { model.setSkipSystem($0) }))
                    Divider()
                    Section("Ignored folders") {
                        ForEach(model.dupIgnored, id: \.self) { path in
                            Button("Stop ignoring \((path as NSString).lastPathComponent)") { model.stopIgnoring(path) }
                                .help(path)
                        }
                        Button("Ignore a Folder…") { model.chooseFolderToIgnore() }
                    }
                } label: {
                    Label(filterLabel, systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(model.dupPhase == .running)
                .help("What the duplicate check includes")
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
            ToolProgressBar(fraction: model.dupPhase == .running ? model.dupProgress.fraction : model.verifyOverall,
                            active: model.dupPhase == .running || model.isVerifying)
            DupDriveChecklist()

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
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 18)
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
                Text("System and app files are left out unless you turn that off under the filter menu. Use the eye button on any folder to ignore it from then on.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            VStack(spacing: 10) {
                Text(Fmt.pct(p.fraction))
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                MeterBar(fraction: p.fraction, color: Theme.cyan, height: 8)
                    .frame(maxWidth: 420)
                    .animation(.easeOut(duration: 0.2), value: p.fraction)
                Text(p.stage.isEmpty ? "Starting…" : p.stage)
                    .font(.system(size: 14, weight: .semibold))
                Text(p.total > 0
                     ? ["\(Fmt.count(p.checked)) of \(Fmt.count(p.total)) files compared", model.dupETA].compactMap { $0 }.joined(separator: "  ·  ")
                     : (model.dupScope == nil ? "Reading the maps of every scanned drive"
                                              : "Reading the map of \(model.dupScopeName)"))
                    .font(.system(size: 11.5, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var results: some View {
        Card(padding: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.dupMatches) { match in
                        FolderMatchView(match: match, expanded: expanded.contains(match.id)) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                if expanded.contains(match.id) { expanded.remove(match.id) } else { expanded.insert(match.id) }
                            }
                        }
                    }
                    if model.dupMatches.isEmpty {
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

/// One row per set of folders that hold copies of the same files. Opens to show the files.
private struct FolderMatchView: View {
    @EnvironmentObject var model: AppModel
    var match: FolderMatch
    var expanded: Bool
    var toggle: () -> Void
    @State private var hover = false

    private var title: String {
        if match.locations.count == 1 { return "Copies inside \(match.locations[0].name)" }
        let names = Set(match.locations.map(\.name))
        if names.count == 1, let n = names.first { return n }
        return match.locations.map(\.name).joined(separator: "  ↔  ")
    }

    private var verified: (done: Int, total: Int) {
        var done = 0
        for gid in match.groupIDs where model.dupGroup(gid)?.state == .identical { done += 1 }
        return (done, match.groupIDs.count)
    }

    private var differing: Int {
        var n = 0
        for gid in match.groupIDs where model.dupGroup(gid)?.state == .different { n += 1 }
        return n
    }

    var body: some View {
        let v = verified
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12).padding(.top, 4)
                Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(Theme.blue)
                    .frame(width: 18).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    ForEach(Array(match.locations.enumerated()), id: \.offset) { i, loc in
                        SideRow(match: match, side: i, loc: loc)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Fmt.bytes(match.wasted)) to free")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("\(Fmt.count(match.fileCount)) file\(match.fileCount == 1 ? "" : "s")  ·  \(Fmt.bytes(match.bytes)) per copy")
                        .font(.system(size: 11, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    if let f = model.verifyFractions[match.id] {
                        VStack(alignment: .trailing, spacing: 4) {
                            MeterBar(fraction: f, color: Theme.cyan, height: 6)
                                .frame(width: 170)
                                .animation(.easeOut(duration: 0.2), value: f)
                            HStack(spacing: 8) {
                                Text(f <= 0 ? "Waiting to verify"
                                     : ["Verifying  \(Fmt.pct(f))", model.verifyETAs[match.id]].compactMap { $0 }.joined(separator: "  ·  "))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(Theme.cyan)
                                Button("Stop") { model.cancelVerify(match.id) }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            if let note = model.verifyNotes[match.id] {
                                Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.amber)
                                    .multilineTextAlignment(.trailing).frame(width: 260, alignment: .trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else if v.done == v.total {
                        Pill(text: "Verified identical", color: Theme.good)
                    } else {
                        if differing > 0 {
                            Pill(text: "\(differing) not identical", color: Theme.bad)
                        }
                        Button(v.done == 0 ? "Verify" : "Verify the rest (\(v.done) of \(v.total) done)") {
                            model.verifyMatch(match)
                        }
                        .buttonStyle(QuietButtonStyle())
                        .help("Read every copy in these folders from start to end and compare them")
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(match.groupIDs.prefix(150), id: \.self) { gid in
                        if let g = model.dupGroup(gid) { DupGroupView(group: g) }
                    }
                    if match.groupIDs.count > 150 {
                        Text("…and \(Fmt.count(match.groupIDs.count - 150)) more files in these folders")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 10)
                    }
                }
                .padding(.leading, 30).padding(.trailing, 6).padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(hover || expanded ? 0.06 : 0.03)))
        .onHover { hover = $0 }
    }
}

/// One folder in a match: where it is, and a button to collect every copy under it.
private struct SideRow: View {
    @EnvironmentObject var model: AppModel
    var match: FolderMatch
    var side: Int
    var loc: FolderLoc

    var body: some View {
        let c = model.sideCollected(match, side: side)
        HStack(spacing: 6) {
            DriveBadge(name: loc.volumeName)
            Text(loc.path).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).truncationMode(.head)
            if c.collected > 0 {
                Text("\(c.collected) of \(c.total) collected").font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
            IconButton(symbol: "tray.and.arrow.down",
                       help: "Add the copies in this folder to the Collector. The copies in the other folder stay.") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.collectSide(match, side: side) }
            }
            IconButton(symbol: "chart.pie", help: "Show this folder on the map") {
                model.showOnMap(volumeID: loc.volumeID, folderPath: loc.path)
            }
            IconButton(symbol: "folder", help: "Open in Finder") { Finder.open(loc.path) }
            IconButton(symbol: "eye.slash", help: "Ignore this folder in duplicate checks") {
                withAnimation(.easeOut(duration: 0.2)) { model.ignoreDuplicateFolder(loc.path) }
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
