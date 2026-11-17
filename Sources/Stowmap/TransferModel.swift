import SwiftUI
import AppKit

/// Rough time left for a job that knows how far along it is.
enum ETA {
    /// nil until there is enough to go on (a few seconds and a couple of percent).
    static func seconds(started: Date?, fraction: Double) -> TimeInterval? {
        guard let started, fraction > 0.015, fraction < 1 else { return nil }
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 4 else { return nil }
        return elapsed * (1 - fraction) / fraction
    }

    static func text(_ seconds: TimeInterval?) -> String? {
        guard let s = seconds, s.isFinite, s >= 0 else { return nil }
        if s < 50 { return "under a minute left" }
        if s < 3600 { return "about \(Int((s / 60).rounded())) min left" }
        let h = Int(s / 3600), m = Int((s.truncatingRemainder(dividingBy: 3600)) / 60)
        return m == 0 ? "about \(h) hr left" : "about \(h) hr \(m) min left"
    }

    static func text(started: Date?, fraction: Double) -> String? {
        text(seconds(started: started, fraction: fraction))
    }
}

/// State for the Copy & Verify screen: what to copy, where, how, and the running job.
@MainActor
final class TransferModel: ObservableObject {
    enum Stage { case setup, preparing, running, done }
    enum CheckStage { case setup, running, done }

    struct SourceItem: Identifiable, Equatable {
        let path: String
        var files = 0
        var bytes: Int64 = 0
        var sized = false
        var isFolder = false
        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
    }

    struct DestItem: Identifiable, Equatable {
        let path: String
        var volumeName = ""
        var free: Int64 = 0
        var total: Int64 = 0
        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
    }

    @Published var mode = 0                               // 0 copy, 1 check a copy

    // Copy: setup
    @Published private(set) var sources: [SourceItem] = []
    @Published private(set) var destinations: [DestItem] = []
    @Published var hash: HashKind = HashKind(rawValue: UserDefaults.standard.string(forKey: "copyHash") ?? "") ?? .xxh64 {
        didSet { UserDefaults.standard.set(hash.rawValue, forKey: "copyHash") }
    }
    @Published var verify: VerifyMode = VerifyMode(rawValue: UserDefaults.standard.string(forKey: "copyVerify") ?? "") ?? .destination {
        didSet { UserDefaults.standard.set(verify.rawValue, forKey: "copyVerify") }
    }
    @Published var conflict: ConflictPolicy = .skip        // always starts on the safe choice
    @Published var includeHidden = true
    @Published var writeLists = true

    // Copy: running
    @Published private(set) var stage: Stage = .setup
    @Published private(set) var snap = TransferSnapshot()
    @Published private(set) var speed: Double = 0          // bytes per second, smoothed
    @Published private(set) var history: [Double] = []     // MB/s, one sample each half second
    @Published private(set) var peak: Double = 0
    @Published private(set) var etaText: String?
    @Published private(set) var paceNote: String?
    @Published private(set) var destNames: [String] = []
    @Published private(set) var destSpeeds: [Double] = []   // bytes per second written, per destination
    @Published private(set) var jobLine = ""               // "6 items from … to … · xxHash64 · verifying each destination"
    private var lastDestCopied: [Int64] = []

    // Check a copy
    @Published var original: String?
    @Published var copyFolder: String?
    @Published var checkFull = false
    @Published private(set) var checkStage: CheckStage = .setup
    @Published private(set) var checkResult: CompareResult?
    @Published private(set) var checkFraction: Double = 0
    @Published private(set) var checkStatus = ""
    @Published private(set) var checkETA: String?

    private var engine: TransferEngine?
    private var timer: Timer?
    private var lastBytes: Int64 = 0
    private var lastTick = Date()
    private var window: [(read: UInt64, write: [UInt64], copied: Int64, files: Int)] = []
    private var expected: [String: DeviceClass] = [:]     // path → what its drive should manage
    private var compare: CompareJob?
    private var checkStarted: Date?

    var isBusy: Bool { stage == .preparing || stage == .running || checkStage == .running }
    var busyFraction: Double { checkStage == .running ? checkFraction : snap.fraction }

    // MARK: setup

    var totalBytes: Int64 { sources.reduce(0) { $0 + $1.bytes } }
    var totalFiles: Int { sources.reduce(0) { $0 + $1.files } }
    var allSized: Bool { sources.allSatisfy { $0.sized } }

    private var options: TransferOptions {
        TransferOptions(hash: hash, verify: verify, conflict: conflict, includeHidden: includeHidden,
                        skipClutter: true, writeLists: writeLists)
    }

    /// Why Start is unavailable, or nil when everything is ready.
    var blocker: String? {
        if sources.isEmpty { return "Add the files or folders to copy." }
        if destinations.isEmpty { return "Add at least one destination folder." }
        if !allSized { return "Measuring what you picked…" }
        for d in destinations {
            for s in sources where d.path == s.path || d.path.hasPrefix(s.path + "/") {
                return "\(d.name) is inside \(s.name). Pick a destination outside what you're copying."
            }
            if d.total > 0 && d.free < totalBytes {
                return "\(d.volumeName.isEmpty ? d.name : d.volumeName) has \(Fmt.bytes(d.free)) free; this copy needs \(Fmt.bytes(totalBytes))."
            }
        }
        return nil
    }

    func addSources(_ urls: [URL]) {
        guard stage == .setup else { return }
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !sources.contains(where: { $0.path == path }) else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            sources.append(SourceItem(path: path, isFolder: isDir.boolValue))
            let o = options
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let plan = TransferPlanner.build(sources: [path], options: o)
                Task { @MainActor in
                    guard let self, let i = self.sources.firstIndex(where: { $0.path == path }) else { return }
                    self.sources[i].files = plan.fileCount
                    self.sources[i].bytes = plan.totalBytes
                    self.sources[i].sized = true
                }
            }
        }
    }

    func removeSource(_ path: String) {
        guard stage == .setup else { return }
        sources.removeAll { $0.path == path }
    }

    func addDestination(_ url: URL) {
        guard stage == .setup, destinations.count < 3 else { return }
        let path = url.standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              !destinations.contains(where: { $0.path == path }) else { return }
        var item = DestItem(path: path)
        if let rv = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                      .volumeAvailableCapacityForImportantUsageKey,
                                                      .volumeAvailableCapacityKey]) {
            item.volumeName = rv.volumeName ?? ""
            item.total = Int64(rv.volumeTotalCapacity ?? 0)
            item.free = max(Int64(rv.volumeAvailableCapacity ?? 0), rv.volumeAvailableCapacityForImportantUsage ?? 0)
        }
        destinations.append(item)
    }

    func removeDestination(_ path: String) {
        guard stage == .setup else { return }
        destinations.removeAll { $0.path == path }
    }

    func chooseSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.prompt = "Add"
        panel.message = "Choose the files and folders to copy"
        if panel.runModal() == .OK { addSources(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Copy Here"
        panel.message = "Choose a folder to copy into"
        if panel.runModal() == .OK, let url = panel.url { addDestination(url) }
    }

    /// Dropped items: folders can be either side, so the drop target decides.
    func handleDrop(_ urls: [URL], asDestination: Bool) {
        if asDestination { for u in urls { addDestination(u) } } else { addSources(urls) }
    }

    // MARK: run

    func start() {
        guard stage == .setup, blocker == nil else { return }
        let o = options
        let srcs = sources.map(\.path)
        let dests = destinations.map(\.path)
        destNames = destinations.map { $0.volumeName.isEmpty ? $0.name : "\($0.volumeName) · \($0.name)" }
        stage = .preparing
        let n = sources.count
        let verifyText: String
        switch verify {
        case .destination: verifyText = "verifying each destination"
        case .both: verifyText = "verifying source and destinations"
        case .off: verifyText = "not verifying"
        }
        jobLine = "\(n) item\(n == 1 ? "" : "s") to \(destinations.map { $0.volumeName.isEmpty ? $0.name : $0.volumeName }.joined(separator: " and "))  ·  \(hash.title)  ·  \(verifyText)"
        lastDestCopied = []
        destSpeeds = []
        snap = TransferSnapshot()
        history = []
        peak = 0
        speed = 0
        etaText = nil
        paceNote = nil
        window = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let plan = TransferPlanner.build(sources: srcs, options: o)
            var classes: [String: DeviceClass] = [:]
            for p in srcs + dests { if let c = Hardware.expected(forPath: p) { classes[p] = c } }
            let engine = TransferEngine(plan: plan, destinations: dests, options: o)
            Task { @MainActor in self?.begin(engine, classes) }
            engine.run()
            Task { @MainActor in self?.finished(engine) }
        }
    }

    /// Runs a prepared plan (used by "Copy the missing files").
    private func start(plan: TransferPlan, into dest: String) {
        guard stage == .setup || stage == .done else { return }
        let o = TransferOptions(hash: hash, verify: verify == .off ? .destination : verify, conflict: .skip,
                                includeHidden: includeHidden, skipClutter: true, writeLists: writeLists)
        destNames = [(dest as NSString).lastPathComponent]
        mode = 0
        jobLine = "\(plan.fileCount) missing file\(plan.fileCount == 1 ? "" : "s") to \((dest as NSString).lastPathComponent)  ·  \(hash.title)  ·  verifying"
        lastDestCopied = []
        destSpeeds = []
        stage = .preparing
        snap = TransferSnapshot()
        history = []
        peak = 0
        window = []
        paceNote = nil
        let engine = TransferEngine(plan: plan, destinations: [dest], options: o)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Task { @MainActor in self?.begin(engine, [:]) }
            engine.run()
            Task { @MainActor in self?.finished(engine) }
        }
    }

    private func begin(_ engine: TransferEngine, _ classes: [String: DeviceClass]) {
        self.engine = engine
        expected = classes
        stage = .running
        lastBytes = 0
        lastTick = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let engine else { return }
        let s = engine.snapshot()
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        let moved = s.copiedBytes + s.verifiedBytes
        if dt > 0.2 {
            let instant = s.paused ? 0 : Double(moved - lastBytes) / dt
            speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
            history.append(instant / 1_000_000)
            if history.count > 240 { history.removeFirst(history.count - 240) }
            peak = max(peak, instant)
            if lastDestCopied.count != s.destCopied.count { lastDestCopied = Array(repeating: 0, count: s.destCopied.count) }
            destSpeeds = s.destCopied.enumerated().map { i, c in
                s.paused ? 0 : max(0, Double(c - lastDestCopied[i]) / dt)
            }
            lastDestCopied = s.destCopied
            lastBytes = moved
            lastTick = now
            let left = Double((s.totalBytes + s.verifyTotal) - moved)
            let recent = history.suffix(20)
            let avg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count) * 1_000_000
            etaText = (avg > 0 && !s.paused && history.count >= 6) ? ETA.text(left / avg) : nil
            updatePace(s)
        }
        snap = s
    }

    /// Looks at the last ~20 seconds: which stage took the time, and is it under what that drive should do?
    private func updatePace(_ s: TransferSnapshot) {
        window.append((s.readNanos, s.writeNanos, s.copiedBytes, s.filesDone))
        if window.count > 40 { window.removeFirst(window.count - 40) }
        guard window.count >= 30, let first = window.first, !s.paused else { paceNote = nil; return }
        let bytes = Double(s.copiedBytes - first.copied)
        let files = max(1, s.filesDone - first.files)
        guard bytes > 50_000_000 else { paceNote = nil; return }
        let avgFile = Int64(bytes) / Int64(files)

        let readSecs = Double(s.readNanos - first.read) / 1e9
        var slowest: (name: String, verb: String, secs: Double, cls: DeviceClass?) =
            (sources.first?.name ?? "The source", "reading", readSecs, sources.first.flatMap { expected[$0.path] })
        for (i, d) in destinations.enumerated() where i < s.writeNanos.count && i < first.write.count {
            let secs = Double(s.writeNanos[i] - first.write[i]) / 1e9
            if secs > slowest.secs {
                slowest = (d.volumeName.isEmpty ? d.name : d.volumeName, "writing", secs, expected[d.path])
            }
        }
        guard slowest.secs > 1 else { paceNote = nil; return }
        paceNote = Pace.transferNote(name: slowest.name, verb: slowest.verb, mbps: bytes / slowest.secs / 1_000_000,
                                     expected: slowest.cls, averageFileBytes: avgFile)
    }

    private func finished(_ engine: TransferEngine) {
        timer?.invalidate()
        timer = nil
        snap = engine.snapshot()
        speed = 0
        etaText = nil
        paceNote = nil
        stage = .done
        if snap.phase == .finished { NSSound(named: "Glass")?.play() }
    }

    func pause() { engine?.pause(); snap.paused = true }
    func resume() { engine?.resume(); snap.paused = false }
    func stop() { engine?.cancel() }

    /// Back to an empty setup screen.
    func reset() {
        guard stage == .done || stage == .setup else { return }
        engine = nil
        sources = []
        destinations = []
        conflict = .skip
        snap = TransferSnapshot()
        history = []
        stage = .setup
    }

    var averageSpeed: Double {
        guard let end = snap.finished else { return 0 }
        let secs = end.timeIntervalSince(snap.started)
        return secs > 0 ? Double(snap.copiedBytes) / secs : 0
    }

    // MARK: check a copy

    func chooseFolder(original isOriginal: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        panel.message = isOriginal ? "Choose the original folder" : "Choose the copy to check"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isOriginal { original = url.standardizedFileURL.path } else { copyFolder = url.standardizedFileURL.path }
        if checkStage == .done { checkStage = .setup; checkResult = nil }
    }

    func setCheckFolder(_ url: URL, original isOriginal: Bool) {
        var isDir: ObjCBool = false
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        if isOriginal { original = path } else { copyFolder = path }
        if checkStage == .done { checkStage = .setup; checkResult = nil }
    }

    var checkBlocker: String? {
        guard let a = original, let b = copyFolder else { return "Choose the original folder and the copy." }
        if a == b { return "Those are the same folder." }
        return nil
    }

    func startCheck() {
        guard checkStage != .running, checkBlocker == nil, let a = original, let b = copyFolder else { return }
        let job = CompareJob()
        compare = job
        checkStage = .running
        checkFraction = 0
        checkStatus = "Listing both folders"
        checkETA = nil
        checkStarted = Date()
        let full = checkFull
        let o = options
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            let p = job.progress
            Task { @MainActor in
                guard let self, self.checkStage == .running else { return }
                self.checkFraction = p.fraction
                self.checkStatus = p.stage
                self.checkETA = full ? ETA.text(started: self.checkStarted, fraction: p.fraction) : nil
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = job.run(original: a, copy: b, full: full, options: o)
            let cancelled = job.isCancelled
            Task { @MainActor in
                guard let self else { return }
                self.timer?.invalidate()
                self.timer = nil
                self.compare = nil
                self.checkResult = cancelled ? nil : result
                self.checkStage = cancelled ? .setup : .done
            }
        }
    }

    func stopCheck() { compare?.cancel() }

    /// Copies what the check found missing into the copy folder, keeping the folder structure.
    /// Files that exist but differ are left for you to decide.
    func copyMissing() {
        guard let result = checkResult, let a = original, let b = copyFolder, !result.missing.isEmpty, !isBusy else { return }
        var plan = TransferPlan()
        for m in result.missing {
            let src = TransferEngine.join(a, m.rel)
            var st = stat()
            guard lstat(src, &st) == 0 else { continue }
            plan.entries.append(PlanEntry(source: src, rel: m.rel, kind: .file, size: Int64(st.st_size),
                                          modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))))
            plan.fileCount += 1
            plan.totalBytes += Int64(st.st_size)
        }
        guard plan.fileCount > 0 else { return }
        checkStage = .setup
        checkResult = nil
        start(plan: plan, into: b)
    }
}
