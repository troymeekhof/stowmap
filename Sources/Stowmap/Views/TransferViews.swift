import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Copy & Verify: setup, the large running view, the result, and "Check a Copy".

struct CopyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var transfer: TransferModel

    private var subtitle: String {
        if transfer.mode == 1 { return "Compare a folder with its copy to see what's missing or different." }
        switch transfer.stage {
        case .setup: return "Copy files to one or more drives and prove each copy with a checksum."
        case .preparing: return "Listing what to copy…"
        case .running: return transfer.snap.paused ? "Paused." : "Copying and verifying. You can keep working."
        case .done: return transfer.snap.phase == .stopped ? "Stopped before finishing." : "Finished."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(title: "Copy & Verify", subtitle: subtitle) {
                GlassTabs(selection: $transfer.mode, tabs: [
                    ("Copy", "square.and.arrow.down.on.square"), ("Check a Copy", "checklist"),
                ])
                .frame(width: 300)
                .disabled(transfer.isBusy)
            }
            Group {
                if transfer.mode == 1 {
                    CheckCopyView()
                } else {
                    switch transfer.stage {
                    case .setup: CopySetupView()
                    case .preparing, .running: CopyRunningView()
                    case .done: CopyDoneView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
    }
}

// MARK: - Shared pieces

/// Loads the file URLs from a drop.
func droppedURLs(_ providers: [NSItemProvider], then: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { then(urls) }
}

/// A card that accepts dropped files and shows a dashed outline while something hovers over it.
private struct DropCard<Content: View>: View {
    var title: String
    var symbol: String
    var onDrop: ([URL]) -> Void
    @ViewBuilder var content: () -> Content
    @State private var targeted = false

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(text: title, symbol: symbol).padding(.horizontal, 4).padding(.top, 2)
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            droppedURLs(providers, then: onDrop)
            return true
        }
    }
}

private struct EmptyDrop: View {
    var symbol: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Smooth area chart of recent speed, in MB/s.
struct SpeedGraph: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, 1) * 1.15
            let pts = points(in: geo.size, top: top)
            ZStack {
                // Faint guide lines at thirds.
                ForEach(1..<3, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                        .position(x: geo.size.width / 2, y: geo.size.height * CGFloat(i) / 3)
                }
                area(pts, height: geo.size.height)
                    .fill(LinearGradient(colors: [Theme.cyan.opacity(0.40), Theme.violet.opacity(0.10), Color.clear],
                                         startPoint: .top, endPoint: .bottom))
                line(pts).stroke(LinearGradient(colors: [Theme.violet, Theme.cyan], startPoint: .leading, endPoint: .trailing),
                                 style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(Theme.cyan).frame(width: 7, height: 7).position(last)
                        .shadow(color: Theme.cyan.opacity(0.8), radius: 5)
                }
            }
        }
    }

    private func points(in size: CGSize, top: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(v, 0), top) / top) * (size.height - 4) - 2)
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1], cur = pts[i]
            let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
            p.addQuadCurve(to: mid, control: prev)
            if i == pts.count - 1 { p.addLine(to: cur) }
        }
        return p
    }

    private func area(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = line(pts)
        guard let first = pts.first, let last = pts.last else { return p }
        p.addLine(to: CGPoint(x: last.x, y: height))
        p.addLine(to: CGPoint(x: first.x, y: height))
        p.closeSubpath()
        return p
    }
}

private func stateColor(_ s: FileState) -> Color {
    switch s {
    case .verified, .alreadyThere: return Theme.good
    case .copied: return Theme.cyan
    case .mismatch, .failed: return Theme.bad
    case .existsDifferent: return Theme.warn
    default: return Theme.textSecondary
    }
}

private func stateText(_ s: FileState) -> String {
    switch s {
    case .pending: return "Waiting"
    case .copying: return "Copying"
    case .verifying: return "Verifying"
    case .verified: return "Verified"
    case .copied: return "Copied, not verified"
    case .alreadyThere: return "Already there, identical"
    case .existsDifferent: return "Already there and different. Left untouched."
    case .mismatch: return "Checksum mismatch. The copy is not the same as the source."
    case .failed(let why): return why
    }
}

private func stateSymbol(_ s: FileState) -> String {
    switch s {
    case .verified, .alreadyThere: return "checkmark.circle.fill"
    case .copied: return "circle.fill"
    case .mismatch, .failed: return "xmark.octagon.fill"
    case .existsDifferent: return "exclamationmark.triangle.fill"
    default: return "circle.dotted"
    }
}

private struct FileResultRow: View {
    var result: FileResult
    var destNames: [String]

    var body: some View {
        let worst = result.worst
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stateSymbol(worst)).font(.system(size: 12)).foregroundStyle(stateColor(worst))
                .frame(width: 16).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.rel).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if worst.isProblem {
                    ForEach(Array(result.states.enumerated()), id: \.offset) { i, s in
                        if s.isProblem {
                            Text("\(i < destNames.count ? destNames[i] : "Destination \(i + 1)"): \(stateText(s))")
                                .font(.system(size: 11)).foregroundStyle(stateColor(s))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if !result.hash.isEmpty {
                Text(String(result.hash.prefix(8))).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary).help(result.hash)
            }
            Text(Fmt.bytes(result.size)).font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit().frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}

// MARK: - Setup

private struct CopySetupView: View {
    @EnvironmentObject var transfer: TransferModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                DropCard(title: "From", symbol: "tray.and.arrow.up", onDrop: { transfer.handleDrop($0, asDestination: false) }) {
                    if transfer.sources.isEmpty {
                        EmptyDrop(symbol: "plus.rectangle.on.folder", text: "Drop files or folders here,\nor click Add.")
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(transfer.sources) { s in
                                    HStack(spacing: 10) {
                                        Image(systemName: s.isFolder ? "folder.fill" : "doc.fill")
                                            .font(.system(size: 13)).foregroundStyle(Theme.blue).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                            Text((s.path as NSString).deletingLastPathComponent)
                                                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                                .lineLimit(1).truncationMode(.head)
                                        }
                                        Spacer(minLength: 8)
                                        if s.sized {
                                            Text("\(Fmt.count(s.files)) files").font(.system(size: 11)).monospacedDigit()
                                                .foregroundStyle(Theme.textSecondary)
                                            Text(Fmt.bytes(s.bytes)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                                .monospacedDigit().frame(width: 76, alignment: .trailing)
                                        } else {
                                            ProgressView().controlSize(.small).scaleEffect(0.7)
                                        }
                                        IconButton(symbol: "xmark", help: "Remove") { transfer.removeSource(s.path) }
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    Button { transfer.chooseSources() } label: { Label("Add…", systemImage: "plus") }
                        .buttonStyle(QuietButtonStyle())
                }

                DropCard(title: "To", symbol: "tray.and.arrow.down", onDrop: { transfer.handleDrop($0, asDestination: true) }) {
                    if transfer.destinations.isEmpty {
                        EmptyDrop(symbol: "externaldrive.badge.plus", text: "Drop a destination folder here,\nor click Add Destination.\nUp to three.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(transfer.destinations) { d in
                                HStack(spacing: 10) {
                                    Image(systemName: "externaldrive.fill").font(.system(size: 13))
                                        .foregroundStyle(Theme.cyan).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            if !d.volumeName.isEmpty { DriveBadge(name: d.volumeName) }
                                            Text(d.path).font(.system(size: 11.5)).lineLimit(1).truncationMode(.head)
                                        }
                                        if d.total > 0 {
                                            MeterBar(fraction: 1 - Double(d.free) / Double(d.total),
                                                     color: d.free < transfer.totalBytes ? Theme.bad : Theme.cyan)
                                            Text("\(Fmt.bytes(d.free)) free of \(Fmt.bytes(d.total))")
                                                .font(.system(size: 10)).monospacedDigit()
                                                .foregroundStyle(d.free < transfer.totalBytes ? Theme.bad : Theme.textSecondary)
                                        }
                                    }
                                    IconButton(symbol: "xmark", help: "Remove") { transfer.removeDestination(d.path) }
                                }
                                .padding(.horizontal, 6).padding(.vertical, 6)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Button { transfer.chooseDestination() } label: { Label("Add Destination…", systemImage: "plus") }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(transfer.destinations.count >= 3)
                        .opacity(transfer.destinations.count >= 3 ? 0.4 : 1)
                }
            }
            .frame(maxHeight: .infinity)

            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 18) {
                        option("Checksum") {
                            Picker("", selection: $transfer.hash) {
                                ForEach(HashKind.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        option("Verify") {
                            Picker("", selection: $transfer.verify) {
                                ForEach(VerifyMode.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        option("If a file is already there") {
                            Picker("", selection: $transfer.conflict) {
                                ForEach(ConflictPolicy.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                    HStack(spacing: 18) {
                        Toggle("Include hidden files", isOn: $transfer.includeHidden)
                        Toggle("Write a checksum list in each destination (MHL)", isOn: $transfer.writeLists)
                        Spacer(minLength: 0)
                    }
                    .toggleStyle(.checkbox).font(.system(size: 12))
                    if transfer.conflict == .replace {
                        Label("Replace overwrites files that are already in the destination.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.warn)
                    }
                    if transfer.verify == .off {
                        Label("With Verify off, copies are not checked against the source.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.warn)
                    }
                }
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    if let b = transfer.blocker {
                        Text(b).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    } else {
                        let n = transfer.destinations.count
                        Text("\(Fmt.count(transfer.totalFiles)) files  ·  \(Fmt.bytes(transfer.totalBytes)) to \(n) destination\(n == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("Each file is written under a temporary name and only takes its real name once it is complete.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Button { transfer.start() } label: {
                    Label("Start Copy", systemImage: "arrow.right.circle.fill").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(transfer.blocker != nil)
                .opacity(transfer.blocker != nil ? 0.45 : 1)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func option<P: View>(_ title: String, @ViewBuilder _ picker: () -> P) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary).textCase(.uppercase)
            picker().pickerStyle(.segmented).labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Running

private struct CopyRunningView: View {
    @EnvironmentObject var transfer: TransferModel

    var body: some View {
        let s = transfer.snap
        VStack(spacing: 14) {
            Card(padding: 22) {
                HStack(alignment: .center, spacing: 28) {
                    ring(s)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(speedNumber).font(.system(size: 60, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text("MB/s").font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 0)
                            if s.paused { Pill(text: "Paused", color: Theme.amber) }
                        }
                        SpeedGraph(values: transfer.history).frame(height: 96)
                        HStack(spacing: 26) {
                            Stat(label: "Copied", value: "\(Fmt.bytes(s.copiedBytes)) of \(Fmt.bytes(s.totalBytes))")
                            Stat(label: "Files", value: "\(Fmt.count(s.filesDone)) of \(Fmt.count(s.filesTotal))")
                            Stat(label: "Time left", value: transfer.etaText?.replacingOccurrences(of: " left", with: "") ?? "Working it out")
                            Stat(label: "Elapsed", value: elapsed(s))
                        }
                    }
                }
            }

            if let note = transfer.paceNote {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise.fill").foregroundStyle(Theme.amber)
                    Text(note).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.10)))
            }

            Card(padding: 12) {
                VStack(spacing: 10) {
                    ForEach(Array(transfer.destNames.enumerated()), id: \.offset) { i, name in
                        lane(s, i, name)
                    }
                }
            }

            Card(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if !s.currentName.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
                            Text("\(s.activity)  \(s.currentName)").font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            MeterBar(fraction: s.currentSize > 0 ? Double(s.currentDone) / Double(s.currentSize) : 0,
                                     color: s.activity == "Verifying" ? Theme.green : Theme.cyan, height: 5)
                                .frame(width: 160)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(s.recent) { r in FileResultRow(result: r, destNames: transfer.destNames) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                if !s.problems.isEmpty {
                    Pill(text: "\(s.problems.count) need\(s.problems.count == 1 ? "s" : "") attention", color: Theme.bad)
                }
                Spacer()
                if s.paused {
                    Button { transfer.resume() } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(QuietButtonStyle(tint: Theme.cyan))
                } else {
                    Button { transfer.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(QuietButtonStyle())
                }
                Button { transfer.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(QuietButtonStyle(tint: Theme.bad))
            }
        }
    }

    private var speedNumber: String {
        let mb = transfer.speed / 1_000_000
        return mb >= 100 ? String(format: "%.0f", mb) : String(format: "%.1f", mb)
    }

    private func elapsed(_ s: TransferSnapshot) -> String {
        let t = max(0, Int(Date().timeIntervalSince(s.started)))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Two tracks: outer = copied, inner = verified. The centre shows the whole job.
    private func ring(_ s: TransferSnapshot) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 16)
            Circle().trim(from: 0, to: max(0.002, s.copyFraction))
                .stroke(Theme.brand, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.violet.opacity(0.45), radius: 10)
                .animation(.easeOut(duration: 0.4), value: s.copyFraction)
            Circle().stroke(Color.white.opacity(0.07), lineWidth: 10).padding(24)
            Circle().trim(from: 0, to: max(0.002, s.verifyFraction))
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(24)
                .animation(.easeOut(duration: 0.4), value: s.verifyFraction)
            VStack(spacing: 2) {
                Text(Fmt.pct(s.fraction)).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                Text(transfer.stage == .preparing ? "Preparing" : (s.activity.isEmpty ? "Working" : s.activity))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    legend(Theme.cyan, "Copied")
                    legend(Theme.green, "Verified")
                }
                .padding(.top, 6)
            }
        }
        .frame(width: 250, height: 250)
        .padding(8)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func lane(_ s: TransferSnapshot, _ i: Int, _ name: String) -> some View {
        let copied = i < s.destCopied.count ? s.destCopied[i] : 0
        let verified = i < s.destVerified.count ? s.destVerified[i] : 0
        let dead = i < s.destDead.count ? s.destDead[i] : nil
        let total = Double(max(1, s.totalBytes))
        return HStack(spacing: 12) {
            Image(systemName: dead == nil ? "externaldrive.fill" : "externaldrive.badge.xmark")
                .font(.system(size: 13)).foregroundStyle(dead == nil ? Theme.cyan : Theme.bad).frame(width: 18)
            Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                .frame(width: 200, alignment: .leading)
            if let dead {
                Text(dead).font(.system(size: 11.5)).foregroundStyle(Theme.bad).lineLimit(2)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 4) {
                    MeterBar(fraction: Double(copied) / total, color: Theme.cyan, height: 5)
                    MeterBar(fraction: Double(verified) / total, color: Theme.green, height: 5)
                }
                Text("\(i < s.destFilesVerified.count ? Fmt.count(s.destFilesVerified[i]) : "0") verified")
                    .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    .frame(width: 96, alignment: .trailing)
            }
        }
    }
}

// MARK: - Done

private struct CopyDoneView: View {
    @EnvironmentObject var transfer: TransferModel

    var body: some View {
        let s = transfer.snap
        let stopped = s.phase == .stopped
        let clean = s.problems.isEmpty && !stopped
        let tint = clean ? Theme.good : (stopped ? Theme.amber : Theme.bad)
        VStack(spacing: 14) {
            Card(padding: 22) {
                HStack(spacing: 26) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.25), lineWidth: 14)
                        Circle().trim(from: 0, to: stopped ? max(0.01, s.fraction) : 1)
                            .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: tint.opacity(0.5), radius: 10)
                        Image(systemName: clean ? "checkmark" : (stopped ? "stop.fill" : "exclamationmark"))
                            .font(.system(size: 54, weight: .bold)).foregroundStyle(tint)
                    }
                    .frame(width: 170, height: 170)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(headline(s)).font(.system(size: 26, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(s)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 26) {
                            Stat(label: "Copied", value: Fmt.bytes(s.copiedBytes))
                            Stat(label: "Took", value: Fmt.duration((s.finished ?? Date()).timeIntervalSince(s.started)))
                            Stat(label: "Average", value: String(format: "%.0f MB/s", transfer.averageSpeed / 1_000_000))
                            Stat(label: "Checksum", value: transfer.hash.title)
                        }
                        HStack(spacing: 8) {
                            if let first = transfer.destinations.first {
                                Button { Finder.open(first.path) } label: { Label("Show in Finder", systemImage: "folder") }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            if let list = s.listPaths.first {
                                Button { Finder.reveal(list) } label: { Label("Show Checksum List", systemImage: "list.bullet.rectangle") }
                                    .buttonStyle(QuietButtonStyle())
                            }
                            Button { transfer.reset() } label: { Label("New Copy", systemImage: "plus") }
                                .buttonStyle(QuietButtonStyle(tint: Theme.cyan))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Card(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    CardTitle(text: s.problems.isEmpty ? "Files" : "Needs attention", symbol: s.problems.isEmpty ? "doc.on.doc" : "exclamationmark.triangle")
                        .padding(.horizontal, 10).padding(.top, 6)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(s.problems) { r in FileResultRow(result: r, destNames: transfer.destNames) }
                            ForEach(s.recent.filter { !$0.worst.isProblem }) { r in
                                FileResultRow(result: r, destNames: transfer.destNames)
                            }
                            if s.filesDone > s.recent.count {
                                Text("Showing the last \(s.recent.count) files and every problem. The checksum list has them all.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(10)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func headline(_ s: TransferSnapshot) -> String {
        if s.phase == .stopped { return "Stopped at \(Fmt.pct(s.fraction))" }
        if s.problems.isEmpty {
            if transfer.verify == .off { return "All \(Fmt.count(s.good)) files copied" }
            return "All \(Fmt.count(s.good)) files verified"
        }
        return "\(Fmt.count(s.good)) fine, \(Fmt.count(s.problems.count)) need attention"
    }

    private func detail(_ s: TransferSnapshot) -> String {
        if s.phase == .stopped {
            return "Files finished before you stopped are complete and in place. The file in progress was discarded, so nothing half-written was left behind."
        }
        var parts: [String] = []
        if transfer.verify != .off && s.problems.isEmpty {
            parts.append("Every copy was read back from the disk and its checksum matches the source.")
        }
        if s.alreadyThere > 0 {
            parts.append("\(Fmt.count(s.alreadyThere)) were already in the destination and identical.")
        }
        if !s.listPaths.isEmpty { parts.append("A checksum list was saved in each destination.") }
        if !s.problems.isEmpty { parts.append("Nothing was replaced or deleted. The files listed below did not copy cleanly.") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Check a copy

private struct CheckCopyView: View {
    @EnvironmentObject var transfer: TransferModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                pick("Original", "folder.fill", transfer.original, original: true)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                pick("Copy to check", "externaldrive.fill", transfer.copyFolder, original: false)
            }
            .frame(height: 118)

            HStack(spacing: 12) {
                Picker("", selection: $transfer.checkFull) {
                    Text("Quick: names and sizes").tag(false)
                    Text("Full: checksums").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 360)
                .disabled(transfer.checkStage == .running)
                Text(transfer.checkFull ? "Reads both sides in full. Finds damage that keeps the same size."
                                        : "Fast. Finds missing and incomplete files.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if transfer.checkStage == .running {
                    Button("Stop") { transfer.stopCheck() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button { transfer.startCheck() } label: {
                        Label(transfer.checkStage == .done ? "Check Again" : "Check", systemImage: "checklist")
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(transfer.checkBlocker != nil)
                    .opacity(transfer.checkBlocker != nil ? 0.45 : 1)
                }
            }

            if transfer.checkStage == .running {
                MeterBar(fraction: transfer.checkFraction, color: Theme.cyan, height: 6)
                    .animation(.easeOut(duration: 0.2), value: transfer.checkFraction)
                Text([transfer.checkStatus, transfer.checkFull ? Fmt.pct(transfer.checkFraction) : nil, transfer.checkETA]
                    .compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cyan).monospacedDigit()
            }

            Group {
                if let r = transfer.checkResult, transfer.checkStage == .done {
                    results(r)
                } else {
                    Card(padding: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            CardTitle(text: "What it tells you", symbol: "questionmark.circle")
                            Text("Whether every file in the original is in the copy, which ones are missing, which are a different size (usually an interrupted copy), and what is only in the copy.")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Nothing is changed in either folder. If files are missing you can copy just those across afterwards.")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let b = transfer.checkBlocker {
                                Text(b).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func pick(_ title: String, _ symbol: String, _ path: String?, original: Bool) -> some View {
        DropCard(title: title, symbol: symbol, onDrop: { urls in
            if let u = urls.first { transfer.setCheckFolder(u, original: original) }
        }) {
            if let path {
                Text((path as NSString).lastPathComponent).font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1).truncationMode(.middle).padding(.horizontal, 4)
                Text(path).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).truncationMode(.head).padding(.horizontal, 4)
            } else {
                Text("Drop a folder here").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            Spacer(minLength: 0)
            Button(path == nil ? "Choose…" : "Change…") { transfer.chooseFolder(original: original) }
                .buttonStyle(QuietButtonStyle())
                .disabled(transfer.checkStage == .running)
        }
    }

    private func counter(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.count(n)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(n == 0 && color != Theme.good ? Theme.textSecondary : color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func results(_ r: CompareResult) -> some View {
        VStack(spacing: 14) {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: r.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20)).foregroundStyle(r.isComplete ? Theme.good : Theme.warn)
                        Text(r.isComplete
                             ? (r.full ? "The copy is complete and every checksum matches." : "The copy has every file, at the same sizes.")
                             : "The copy is not complete.")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Spacer(minLength: 8)
                        if !r.missing.isEmpty {
                            Button { transfer.copyMissing() } label: {
                                Label("Copy the \(Fmt.count(r.missing.count)) Missing File\(r.missing.count == 1 ? "" : "s")", systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(GlowButtonStyle())
                        }
                    }
                    HStack(spacing: 12) {
                        counter(r.matched, "Match", Theme.good)
                        counter(r.missing.count, "Missing from the copy", Theme.bad)
                        counter(r.different.count, "Different", Theme.warn)
                        counter(r.extra.count, "Only in the copy", Theme.cyan)
                    }
                    if !r.full && r.isComplete {
                        Text("Sizes match, which catches missing and interrupted files. Run Full to compare the contents too.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Card(padding: 8) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section("Missing from the copy", r.missing, Theme.bad) { Fmt.bytes($0.sizeOriginal) }
                        section("Different", r.different, Theme.warn) { "\(Fmt.bytes($0.sizeOriginal)) → \(Fmt.bytes($0.sizeCopy))" }
                        section("Only in the copy", r.extra, Theme.cyan) { Fmt.bytes($0.sizeCopy) }
                        if r.missing.isEmpty && r.different.isEmpty && r.extra.isEmpty {
                            Text("Nothing to list. \(Fmt.count(r.matched)) files, \(Fmt.bytes(r.matchedBytes)).")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).padding(16)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [CompareItem], _ color: Color, size: @escaping (CompareItem) -> String) -> some View {
        if !items.isEmpty {
            Text("\(title)  ·  \(Fmt.count(items.count))").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color).textCase(.uppercase).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
            ForEach(items.prefix(300)) { item in
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.rel).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(item.why).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Text(size(item)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
            if items.count > 300 {
                Text("…and \(Fmt.count(items.count - 300)) more").font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary).padding(.horizontal, 10).padding(.vertical, 4)
            }
        }
    }
}
