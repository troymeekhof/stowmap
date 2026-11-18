import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Window

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
          TopTabs()
          Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
          HStack(spacing: 0) {
            if model.pane == .drive || model.pane == .search {
                Sidebar()
                    .frame(width: 250)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            }
            Group {
                switch model.pane {
                case .search:
                    SearchView().transition(.opacity)
                case .duplicates:
                    DuplicatesView().transition(.opacity)
                case .copy:
                    CopyView().transition(.opacity)
                case .drive:
                    if let session = model.selected {
                        DetailView(session: session)
                            .id(session.id)
                            .transition(.opacity)
                    } else {
                        EmptyState()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .foregroundStyle(.white)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.violet.opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $model.deletePrompt, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { model.confirmPermanentDelete() }
            Button("Cancel", role: .cancel) { model.cancelPermanentDelete() }
        } message: {
            Text(deleteMessage)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            let appModel = model
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in appModel.addFolder(url) }
            }
            return true
        }
    }
}

/// The three parts of the app, as tabs across the top of the window. Each shows its own progress.
struct TopTabs: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var transfer: TransferModel

    var body: some View {
        HStack(spacing: 4) {
            tab("Drives", "externaldrive.fill", selected: model.pane == .drive || model.pane == .search,
                busy: model.scanningCount > 0, fraction: nil, status: drivesStatus) { model.pane = .drive }
            tab("Duplicates", "doc.on.doc.fill", selected: model.pane == .duplicates,
                busy: dupBusy, fraction: dupFraction, status: dupStatus) { model.pane = .duplicates }
            tab("Copy & Verify", "square.and.arrow.down.on.square.fill", selected: model.pane == .copy,
                busy: transfer.isBusy, fraction: transfer.busyFraction, status: copyStatus) { model.pane = .copy }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.05)))
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 8)
    }

    private func tab(_ title: String, _ symbol: String, selected: Bool, busy: Bool, fraction: Double?,
                     status: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.75))
                        Text(status).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                            .monospacedDigit().lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if busy {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    }
                }
                MeterBar(fraction: fraction ?? 0, color: Theme.cyan, height: 3)
                    .opacity(busy && fraction != nil ? 1 : 0)
            }
            .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 5)
            .frame(width: 236, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.11 : 0.0001)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var drivesStatus: String {
        let n = model.scanningCount
        return n > 0 ? "Scanning \(n) drive\(n == 1 ? "" : "s")" : "Maps of every drive"
    }

    private var copyStatus: String {
        if transfer.isBusy {
            let waiting = transfer.waitingCount
            let tail = waiting > 0 ? "\(waiting) waiting" : nil
            if transfer.runningCount == 1, let run = transfer.runs.values.first {
                let what: String
                if run.kind == .check {
                    what = run.checkHashing ? "Checking  \(Fmt.pct(run.checkFraction))" : "Listing  \(Fmt.count(run.checkListed)) files"
                } else if run.stage == .preparing {
                    what = "Listing  \(Fmt.count(run.listedFiles)) files"
                } else {
                    what = "\(Fmt.pct(run.fraction))  ·  \(String(format: "%.0f MB/s", run.speed / 1_000_000))"
                }
                return [what, waiting > 0 ? transfer.queueETA : run.eta, tail].compactMap { $0 }.joined(separator: "  ·  ")
            }
            let mb = String(format: "%.0f MB/s", transfer.totalSpeed / 1_000_000)
            return ["\(transfer.runningCount) jobs  ·  \(Fmt.pct(transfer.queueFraction))  ·  \(mb)", transfer.queueETA, tail]
                .compactMap { $0 }.joined(separator: "  ·  ")
        }
        if let last = transfer.lastFinishedJob { return last.summary }
        return "Copy with checksums"
    }

    private var dupBusy: Bool { model.dupPhase == .running || model.isVerifying }

    private var dupFraction: Double {
        model.dupPhase == .running ? model.dupProgress.fraction : model.verifyOverall
    }

    private var dupStatus: String {
        if model.dupPhase == .running {
            let stage = model.dupProgress.total > 0 ? "Comparing files" : "Reading maps"
            return ["\(stage)  \(Fmt.pct(model.dupProgress.fraction))", model.dupETA].compactMap { $0 }.joined(separator: "  ·  ")
        }
        if model.isVerifying {
            return ["Verifying  \(Fmt.pct(model.verifyOverall))", model.dupETA].compactMap { $0 }.joined(separator: "  ·  ")
        }
        if model.dupPhase == .done {
            if model.dupMatches.isEmpty { return "None found in \(model.dupScopeName)" }
            let wasted = model.dupGroups.reduce(Int64(0)) { $0 + $1.wasted }
            return "\(Fmt.bytes(wasted)) to free in \(Fmt.count(model.dupMatches.count)) folder\(model.dupMatches.count == 1 ? "" : "s")"
        }
        return "Find identical files"
    }
}

private extension ContentView {
    var deleteTitle: String {
        let n = model.pendingDeleteNodes.count
        return "Delete \(n) item\(n == 1 ? "" : "s") permanently?"
    }

    var deleteMessage: String {
        let nodes = model.pendingDeleteNodes
        let names = nodes.prefix(6).map { "• " + $0.name }.joined(separator: "\n")
        let more = nodes.count > 6 ? "\n…and \(nodes.count - 6) more" : ""
        return "\(model.pendingDeleteVolumes) has no Trash, so these can't be moved there. Deleting erases them now (\(Fmt.bytes(model.pendingDeleteBytes))) and they can't be recovered.\n\n\(names)\(more)"
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive").font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("Looking for drives…").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var transfer: TransferModel
    @FocusState private var searchFocused: Bool
    @State private var showFeedback = false

    private let groups: [(title: String, kinds: [Volume.Kind])] = [
        ("Internal", [.boot, .internalDrive]),
        ("External", [.external]),
        ("Network", [.network]),
        ("Folders", [.folder]),
    ]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 26, height: 26)
                Text("Stowmap").font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .padding(.top, 14).padding(.horizontal, 18).padding(.bottom, 12)

            tools

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.title) { group in
                        let vols = model.volumes.filter { group.kinds.contains($0.kind) }
                        if !vols.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 8)
                                ForEach(vols) { v in
                                    if let session = model.sessions[v.id] {
                                        VolumeRow(session: session, selected: model.pane == .drive && model.selectedID == v.id)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(.easeOut(duration: 0.18)) {
                                                    model.selectedID = v.id
                                                    model.pane = .drive
                                                }
                                            }
                                            .contextMenu {
                                                Button("Open in Finder") { Finder.open(v.path) }
                                                Button(session.result == nil ? "Scan" : "Rescan") { session.start() }
                                                if v.kind == .folder {
                                                    Divider()
                                                    Button("Remove from Sidebar") { model.removeFolder(v) }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.volumes.map(\.id))
            }

            Divider().overlay(Color.white.opacity(0.06))
            scanAllControl
                .padding(.horizontal, 12).padding(.top, 12)
            HStack(spacing: 8) {
                Button { model.chooseFolder() } label: {
                    Label("Scan a Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())
                Spacer(minLength: 0)
                IconButton(symbol: "bubble.left.and.text.bubble.right", help: "Leave feedback") { showFeedback = true }
                Menu {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                    Button("Leave Feedback…") { showFeedback = true }
                    Button("Full Disk Access Settings…") { Finder.openFullDiskAccessSettings() }
                    Divider()
                    Text("Stowmap \(version)")
                    Button("Quit Stowmap") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Settings and updates")
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.18))
        .sheet(isPresented: $showFeedback) { FeedbackSheet() }
    }

    /// One button for every drive: scan them all, or stop while they run.
    @ViewBuilder
    private var scanAllControl: some View {
        let running = model.scanningCount
        let waiting = model.scanAllPending.count
        if running > 0 || waiting > 0 {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                Text("Scanning \(running) drive\(running == 1 ? "" : "s")" + (waiting > 0 ? ", \(waiting) waiting" : ""))
                    .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
                Button("Stop") { model.stopAllScans() }
                    .buttonStyle(QuietButtonStyle())
                    .help("Stop every scan that is running or waiting")
            }
        } else {
            Button { model.scanAll() } label: {
                Label(model.anyScanned ? "Rescan All Drives" : "Scan All Drives",
                      systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(QuietButtonStyle())
            .help("Scan every drive in the sidebar. Network shares run one at a time. (⇧⌘R)")
        }
    }

    /// Search across every scanned drive.
    private var tools: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Search all drives", text: $model.searchText)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit {
                        model.pane = .search
                        model.runSearch()
                    }
                if !model.searchText.isEmpty {
                    Button { model.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain).help("Clear search")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(model.pane == .search ? 0.10 : 0.06)))
            if model.searchBusy {
                MeterBar(fraction: model.searchProgress, color: Theme.cyan)
                    .animation(.easeOut(duration: 0.15), value: model.searchProgress)
                    .padding(.horizontal, 4)
            }

        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

/// Where feedback goes. An email address in Info.plist (StowmapFeedbackEmail) opens a ready-to-send
/// message in the user's mail app; without one, it opens a new issue on the project's GitHub page.
enum Feedback {
    static var email: String? {
        let v = Bundle.main.infoDictionary?["StowmapFeedbackEmail"] as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    static var details: String {
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Stowmap \(app) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    static func send(_ text: String, kind: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n—\n" + details
        var c = URLComponents()
        if let email {
            c.scheme = "mailto"
            c.path = email
            c.queryItems = [URLQueryItem(name: "subject", value: "Stowmap feedback: \(kind)"),
                            URLQueryItem(name: "body", value: body)]
        } else {
            c.scheme = "https"
            c.host = "github.com"
            c.path = "/troymeekhof/stowmap/issues/new"
            c.queryItems = [URLQueryItem(name: "title", value: "\(kind): "),
                            URLQueryItem(name: "body", value: body)]
        }
        // Mail apps want spaces as %20, not "+".
        if let url = c.url.flatMap({ URL(string: $0.absoluteString.replacingOccurrences(of: "+", with: "%20")) }) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind = "Idea"
    private let kinds = ["Idea", "Problem", "Praise", "Question"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 20))
                    .foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leave feedback").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Stowmap is made by one independent creator. Every message gets read.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Picker("", selection: $kind) {
                ForEach(kinds, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .frame(minHeight: 150)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What happened, or what would make this better for you?")
                            .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                    }
                }
            Text(Feedback.email == nil
                 ? "Send opens a new issue on the project's GitHub page with your note filled in. It's public, and needs a free GitHub account. Sent with it: \(Feedback.details)."
                 : "Send opens a message in your mail app with your note filled in, so you can check it before it goes. Sent with it: \(Feedback.details).")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button {
                    Feedback.send(text, kind: kind)
                    dismiss()
                } label: { Label("Send", systemImage: "paperplane.fill") }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.windowBackground)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

struct VolumeRow: View {
    @ObservedObject var session: ScanSession
    var selected: Bool

    var body: some View {
        let v = session.volume
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.white.opacity(0.08)))
                Image(systemName: v.symbol).font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(v.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if session.isScanning {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    } else if session.result != nil {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                            .foregroundStyle(Theme.good.opacity(0.8))
                    }
                }
                if session.isScanning {
                    // While scanning, the capacity bar gives way to scan progress.
                    ScanBar(fraction: session.scanFraction)
                    Text(scanStatus)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.cyan)
                        .monospacedDigit().lineLimit(1)
                } else if v.total > 0 {
                    MeterBar(fraction: v.usedFraction, color: Theme.usage(v.usedFraction))
                    Text("\(Fmt.bytes(v.free)) free of \(Fmt.bytes(v.total))")
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).monospacedDigit().lineLimit(1)
                } else {
                    Text(v.path).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.09 : 0.0001))
        )
    }

    private var scanStatus: String {
        let p = session.progress
        if let f = session.scanFraction {
            return ["Scanning \(Fmt.pct(f))", session.scanETA ?? "\(Fmt.count(p.files)) files"].joined(separator: "  ·  ")
        }
        return "Scanning  ·  \(Fmt.bytes(p.bytes)) mapped"
    }
}

/// Scan progress for a drive row: a filling bar when the amount to scan is known, a sliding
/// one when it isn't (network shares and folders).
struct ScanBar: View {
    var fraction: Double?
    var height: CGFloat = 6
    @State private var slide = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                if let f = fraction {
                    Capsule().fill(Theme.brand)
                        .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, f)))))
                        .animation(.easeOut(duration: 0.25), value: f)
                } else {
                    Capsule().fill(Theme.brand)
                        .frame(width: g.size.width * 0.35)
                        .offset(x: slide ? g.size.width * 0.65 : 0)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: slide)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .onAppear { slide = true }
    }
}

// MARK: - Detail

struct DetailView: View {
    @ObservedObject var session: ScanSession
    @EnvironmentObject private var model: AppModel
    @AppStorage("showHidden") private var showHidden = true
    @State private var tab = 0
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if session.isScanning {
                ScanningView(session: session)
            } else if let result = session.result, let focus = session.focus {
                browser(result, focus)
            } else {
                IdleView(session: session)
            }
            if !session.collected.isEmpty {
                CollectorBar(session: session, confirm: $confirmTrash)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 18)
        .confirmationDialog("Move \(session.collected.count) item\(session.collected.count == 1 ? "" : "s") to the Trash?",
                            isPresented: $confirmTrash) {
            Button("Move to Trash (\(Fmt.bytes(session.collectedBytes)))", role: .destructive) {
                withAnimation { session.trashCollected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
        .alert("Some items couldn't be moved", isPresented: Binding(
            get: { session.trashError != nil }, set: { if !$0 { session.trashError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.trashError ?? "")
        }
        .background {
            // Keyboard shortcuts
            Group {
                Button("") { session.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("") { session.start() }.keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0)
        }
    }

    // MARK: header

    private var header: some View {
        let v = session.volume
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).font(.system(size: 26, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(subtitle(v)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .monospacedDigit().lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let r = session.result, !session.isScanning {
                    Pill(text: r.fromCache ? "Saved \(Fmt.ago(r.date))" : "Scanned \(Fmt.ago(r.date))",
                         color: r.fromCache ? Theme.amber : Theme.good)
                    Pill(text: "\(Fmt.count(r.root.fileCount)) files", color: Theme.cyan)
                    Button { showHidden.toggle() } label: {
                        Label("Hidden", systemImage: showHidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(QuietButtonStyle(tint: showHidden ? Theme.cyan : Color.white))
                    .help(showHidden ? "Hidden files and folders are shown. Click to fold them away." : "Hidden files and folders are folded away. Click to show them.")
                    Button { model.openDuplicates(for: v.id) } label: {
                        Label("Duplicates", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .help("Find identical files within this drive")
                    Menu {
                        Button("Export This Folder as CSV…") { exportCSV() }
                        Button("Open in Finder") { Finder.open(session.focus?.path ?? v.path) }
                        Button("Copy Path") { Finder.copyPath(session.focus?.path ?? v.path) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    Button { session.start() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .buttonStyle(QuietButtonStyle())
                        .help("Scan again (⌘R)")
                }
            }
            if v.total > 0 {
                MeterBar(fraction: v.usedFraction, color: Theme.usage(v.usedFraction), height: 6)
            }
        }
    }

    private func subtitle(_ v: Volume) -> String {
        var parts = [v.kindLabel]
        if !v.format.isEmpty { parts.append(v.format) }
        if v.kind == .network && v.total > 0 {
            // These numbers describe the whole server, not this share.
            parts.append("Server: \(Fmt.bytes(v.used)) used of \(Fmt.bytes(v.total))")
            parts.append("\(Fmt.bytes(v.free)) free")
        } else if v.total > 0 {
            parts.append("\(Fmt.bytes(v.used)) used of \(Fmt.bytes(v.total))")
            parts.append("\(Fmt.bytes(v.free)) free")
        } else {
            parts.append(v.path)
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: browser

    @ViewBuilder
    private func browser(_ result: ScanResult, _ focus: FileNode) -> some View {
        HStack(spacing: 12) {
            GlassTabs(selection: $tab, tabs: [
                ("Map", "chart.pie.fill"), ("Tree", "list.bullet.indent"),
                ("File Types", "square.stack.3d.up.fill"), ("Largest Files", "arrow.up.right.circle.fill"),
            ])
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }

        if result.denied > 0 {
            AccessBanner(count: result.denied)
        } else if result.fromCache {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.amber)
                Text("Showing the saved map from \(Fmt.ago(result.date)). Rescan for current sizes and full detail.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
        }

        Group {
            switch tab {
            case 0: MapTab(session: session, focus: focus, showHidden: showHidden)
            case 1: TreeTab(session: session, root: result.root, showHidden: showHidden) { tab = 0 }
            case 2: TypesTab(result: result)
            default: LargestTab(session: session, files: result.largest) { tab = 0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(session.revision)
    }

    private func exportCSV() {
        guard let focus = session.focus else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(focus.name) - Stowmap.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["name,path,kind,size_bytes,files"]
        for c in focus.children {
            let kind: String
            switch c.kind {
            case .folder: kind = "folder"
            case .file: kind = "file"
            case .smallFiles: kind = "small files"
            case .hiddenSpace: kind = "hidden space"
            }
            lines.append([q(c.name), q(c.path), kind, String(c.size), String(c.fileCount)].joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

struct AccessBanner: View {
    var count: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Theme.warn)
            Text("\(Fmt.count(count)) folder\(count == 1 ? "" : "s") couldn't be read. Give Stowmap Full Disk Access, then rescan, for the complete picture.")
                .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open Settings") { Finder.openFullDiskAccessSettings() }
                .buttonStyle(QuietButtonStyle(tint: Theme.warn))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warn.opacity(0.10)))
    }
}

// MARK: - Idle (never scanned)

struct IdleView: View {
    @ObservedObject var session: ScanSession

    private let gets: [(symbol: String, title: String, detail: String)] = [
        ("chart.pie.fill", "Map", "The biggest folders as slices. Click one to go inside."),
        ("list.bullet.indent", "Tree", "Every folder as an outline, with search."),
        ("square.stack.3d.up.fill", "File Types", "Space by kind and by extension."),
        ("arrow.up.right.circle.fill", "Largest Files", "The 250 biggest files on the drive."),
    ]

    var body: some View {
        let v = session.volume
        SplitPanel {
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 13)
                    if v.total > 0 {
                        Circle().trim(from: 0, to: max(0.003, v.usedFraction))
                            .stroke(Theme.brand, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Theme.violet.opacity(0.45), radius: 10)
                    }
                    VStack(spacing: 2) {
                        if v.total > 0 {
                            Text(Fmt.pct(v.usedFraction))
                                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("used").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        } else {
                            Image(systemName: "folder.fill").font(.system(size: 40)).foregroundStyle(Theme.brand)
                        }
                    }
                }
                .frame(width: 180, height: 180)

                VStack(spacing: 8) {
                    Text("See what's filling \(v.name)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Stowmap reads every folder, hidden ones included, and draws the result as a map you can click through.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                Button { session.start() } label: { Label("Scan \(v.name)", systemImage: "magnifyingglass") }
                    .buttonStyle(GlowButtonStyle())
                    .keyboardShortcut(.defaultAction)
                if v.kind == .network {
                    Text("Network shares scan more slowly than local drives.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
        } right: {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(text: v.kind == .folder ? "This folder" : "This drive", symbol: v.symbol)
                    .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                if v.total > 0 {
                    FactRow(label: "Capacity", value: Fmt.bytes(v.total))
                    FactRow(label: "Used", value: Fmt.bytes(v.used))
                    FactRow(label: "Free", value: Fmt.bytes(v.free))
                }
                if !v.format.isEmpty { FactRow(label: "Format", value: v.format) }
                FactRow(label: "Location", value: v.path)
                FactRow(label: "Last scanned", value: "Never")

                CardTitle(text: "What you get", symbol: "square.grid.2x2")
                    .padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 6)
                ForEach(gets, id: \.title) { g in
                    HStack(spacing: 12) {
                        Image(systemName: g.symbol).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.07)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(g.title).font(.system(size: 12.5, weight: .semibold))
                            Text(g.detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Scanning

struct ScanningView: View {
    @ObservedObject var session: ScanSession
    @State private var spin = false

    private var fraction: Double? { session.scanFraction }

    private func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        let p = session.progress
        SplitPanel {
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 13)
                    if let f = fraction {
                        Circle().trim(from: 0, to: max(0.01, f))
                            .stroke(Theme.brand, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.3), value: f)
                    }
                    Circle().trim(from: 0, to: 0.18)
                        .stroke(Theme.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(-13)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                    VStack(spacing: 2) {
                        Text(Fmt.bytes(p.bytes))
                            .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text("mapped").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 22)
                }
                .frame(width: 180, height: 180)
                .padding(13)
                .onAppear { spin = true }

                VStack(spacing: 8) {
                    Text("Mapping \(session.volume.name)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("You can keep working. Other drives can scan at the same time.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
                Button("Cancel") { session.cancel() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        } right: {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(text: "This scan", symbol: "waveform.path.ecg")
                    .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                FactRow(label: "Mapped so far", value: Fmt.bytes(p.bytes))
                FactRow(label: "Files", value: NumberFormatter.localizedString(from: NSNumber(value: p.files), number: .decimal))
                if let f = fraction { FactRow(label: "Progress", value: Fmt.pct(f)) }
                if let eta = session.scanETA {
                    FactRow(label: "Time left", value: eta.replacingOccurrences(of: " left", with: ""))
                }
                if let started = session.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { ctx in
                        FactRow(label: "Elapsed", value: clock(ctx.date.timeIntervalSince(started)))
                    }
                }
                FactRow(label: "Folders without access", value: Fmt.count(p.denied))

                if let note = session.paceNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "tortoise.fill").foregroundStyle(Theme.amber)
                        Text(note).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.amber.opacity(0.10)))
                    .padding(.horizontal, 6).padding(.top, 10)
                }

                CardTitle(text: "Reading now", symbol: "doc.text.magnifyingglass")
                    .padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 6)
                ForEach(Array(session.recentPaths.enumerated()), id: \.offset) { i, path in
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6 - Double(i) * 0.08))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
        }
    }
}

// MARK: - Collector

struct CollectorBar: View {
    @ObservedObject var session: ScanSession
    @Binding var confirm: Bool

    var body: some View {
        Card(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").font(.system(size: 15)).foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Collector").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                    Text("\(session.collected.count) item\(session.collected.count == 1 ? "" : "s")  ·  \(Fmt.bytes(session.collectedBytes))")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.collected) { node in
                            HStack(spacing: 5) {
                                Text(node.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(Fmt.bytes(node.size)).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                                Button { withAnimation { session.toggleCollect(node) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .help(node.path)
                        }
                    }
                }
                Button("Clear") { withAnimation { session.clearCollected() } }
                    .buttonStyle(QuietButtonStyle())
                Button { confirm = true } label: { Label("Move to Trash", systemImage: "trash.fill") }
                    .buttonStyle(QuietButtonStyle(tint: Theme.bad))
            }
        }
    }
}
