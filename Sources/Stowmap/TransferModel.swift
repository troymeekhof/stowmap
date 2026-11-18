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

/// One copy or check lined up in the queue.
struct QueueJob: Identifiable {
    enum Kind { case copy, check }
    enum State { case waiting, running, done, attention, stopped }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var state: State = .waiting
    var fraction: Double = 0
    var summary = ""
    var bytes: Int64 = 0                 // size of the work when known (0 = not known yet)
    var counted = true                   // part of the queue run in progress
    var options = TransferOptions()

    // Copy
    var sources: [TransferModel.SourceItem] = []
    var dests: [TransferModel.DestItem] = []
    var destNames: [String] = []
    var plan: TransferPlan?              // already listed (reused if recent)
    var planAt: Date?
    var result: TransferSnapshot?

    // Check a copy
    var original = ""
    var copy = ""
    var full = false
    var checkResult: CompareResult?

    var isFinished: Bool { state == .done || state == .attention || state == .stopped }
}

/// The Dock icon with a progress bar along the bottom while the queue runs.
@MainActor
enum DockProgress {
    private final class Tile: NSView {
        var fraction: Double = 0
        override func draw(_ dirtyRect: NSRect) {
            NSApp.applicationIconImage.draw(in: bounds)
            let w = bounds.width, h = bounds.height
            let track = NSRect(x: w * 0.10, y: h * 0.07, width: w * 0.80, height: h * 0.105)
            let radius = track.height / 2
            NSColor.black.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            outline.lineWidth = 1
            outline.stroke()
            let inner = track.insetBy(dx: h * 0.018, dy: h * 0.018)
            let f = CGFloat(min(1, max(0, fraction)))
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * f), height: inner.height)
            NSColor(calibratedRed: 0.30, green: 0.85, blue: 1.0, alpha: 1).setFill()
            NSBezierPath(roundedRect: fill, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
        }
    }

    private static var tile: Tile?
    private static var shown: Int = -1

    /// nil removes the bar.
    static func set(_ fraction: Double?) {
        let dock = NSApp.dockTile
        guard let fraction else {
            if tile != nil {
                tile = nil
                shown = -1
                dock.contentView = nil
                dock.display()
            }
            return
        }
        let step = Int((min(1, max(0, fraction)) * 200).rounded())
        if tile == nil {
            let t = Tile(frame: NSRect(origin: .zero, size: dock.size))
            tile = t
            dock.contentView = t
        } else if step == shown {
            return
        }
        shown = step
        tile?.fraction = fraction
        dock.display()
    }
}

/// State for the Copy & Verify screen: what to copy, where, how, the queue and the running job.
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

    @Published var mode = 0                               // 0 copy, 1 check a copy, 2 queue

    // Copy: setup (the next job being put together; editable while others run)
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

    // Queue
    @Published private(set) var queue: [QueueJob] = []
    @Published var inspectID: UUID?                        // a finished job picked from the queue list
    @Published private(set) var queueETA: String?
    private var currentID: UUID?
    private var lastFinishedID: UUID?
    private var queueStarted: Date?

    // The running copy
    @Published private(set) var stage: Stage = .setup
    @Published private(set) var snap = TransferSnapshot()
    @Published private(set) var speed: Double = 0          // bytes per second, smoothed
    @Published private(set) var history: [Double] = []     // one sample each half second (MB/s, or files/s while listing)
    @Published private(set) var peak: Double = 0
    @Published private(set) var etaText: String?
    @Published private(set) var paceNote: String?
    @Published private(set) var destNames: [String] = []
    @Published private(set) var destSpeeds: [Double] = []   // bytes per second written, per destination
    @Published private(set) var jobLine = ""               // "6 items to … · xxHash64 · verifying each destination"
    @Published private(set) var listedFiles = 0            // found so far while a copy is being listed
    @Published private(set) var runOptions = TransferOptions()
    private var runSources: [SourceItem] = []
    private var runDests: [DestItem] = []
    private var lastDestCopied: [Int64] = []
    private var listCounter = Shared(0)
    private var prepStop = Shared(false)

    // Check a copy: setup
    @Published var original: String?
    @Published var copyFolder: String?
    @Published var checkFull = false

    // The running check
    @Published private(set) var checkStage: CheckStage = .setup
    @Published private(set) var checkFraction: Double = 0
    @Published private(set) var checkStatus = ""
    @Published private(set) var checkETA: String?
    @Published private(set) var checkHashing = false
    @Published private(set) var checkListed = 0
    @Published private(set) var checkRate: Double = 0      // files per second while listing
    @Published private(set) var checkBytesDone: Int64 = 0
    @Published private(set) var checkBytesTotal: Int64 = 0
    @Published private(set) var checkFilesDone = 0
    @Published private(set) var checkFilesTotal = 0
    @Published private(set) var checkStartedAt = Date()

    /// How many files a folder held when it was last mapped, if a saved map covers it.
    var expectedFiles: (@MainActor (String) -> Int?)?

    private var engine: TransferEngine?
    private var timer: Timer?
    private var lastBytes: Int64 = 0
    private var lastTick = Date()
    private var window: [(read: UInt64, write: [UInt64], copied: Int64, files: Int)] = []
    private var expected: [String: DeviceClass] = [:]     // path → what its drive should manage
    private var compare: CompareJob?
    private var checkStarted: Date?
    private var plans: [String: (plan: TransferPlan, at: Date, hidden: Bool)] = [:]

    var isBusy: Bool { stage == .preparing || stage == .running || checkStage == .running }
    var busyFraction: Double { queueFraction }

    // MARK: queue

    var waitingCount: Int { queue.filter { $0.state == .waiting }.count }
    var countedJobs: [QueueJob] { queue.filter { $0.counted } }
    /// "2 of 5": the running job's place in this run of the queue.
    var queuePosition: (index: Int, of: Int) {
        let jobs = countedJobs
        let finished = jobs.filter { $0.isFinished }.count
        return (min(jobs.count, finished + 1), jobs.count)
    }

    /// Progress through every job in this run, weighted by size where the sizes are known.
    var queueFraction: Double {
        let jobs = countedJobs
        guard !jobs.isEmpty else { return 0 }
        let known = jobs.filter { $0.bytes > 0 }.map { Double($0.bytes) }
        let typical = known.isEmpty ? 1 : known.reduce(0, +) / Double(known.count)
        var total = 0.0, done = 0.0
        for j in jobs {
            let w = j.bytes > 0 ? Double(j.bytes) : typical
            total += w
            switch j.state {
            case .waiting: break
            case .running: done += w * min(1, max(0, j.fraction))
            case .done, .attention, .stopped: done += w
            }
        }
        return total > 0 ? min(1, done / total) : 0
    }

    /// The job the Queue tab shows in full: one picked from the list, else the running one, else the last finished.
    var shownJob: QueueJob? {
        if let id = inspectID, let j = queue.first(where: { $0.id == id }) { return j }
        if let id = currentID, let j = queue.first(where: { $0.id == id }) { return j }
        if let id = lastFinishedID, let j = queue.first(where: { $0.id == id }) { return j }
        return nil
    }

    var runningJob: QueueJob? {
        guard let id = currentID else { return nil }
        return queue.first { $0.id == id }
    }

    private func update(_ id: UUID?, _ change: (inout QueueJob) -> Void) {
        guard let id, let i = queue.firstIndex(where: { $0.id == id }) else { return }
        change(&queue[i])
    }

    private func enqueue(_ job: QueueJob) {
        let wasIdle = !isBusy
        if wasIdle {
            // A new run: jobs finished earlier no longer count toward its progress.
            for i in queue.indices { queue[i].counted = false }
            inspectID = nil
        }
        queue.append(job)
        if wasIdle { mode = 2 }
        advance()
    }

    private func advance() {
        guard !isBusy else { return }
        guard let i = queue.firstIndex(where: { $0.state == .waiting }) else {
            if queueStarted != nil {
                queueStarted = nil
                queueETA = nil
                DockProgress.set(nil)
                NSSound(named: "Glass")?.play()
                NSApp.requestUserAttention(.informationalRequest)
            }
            return
        }
        if queueStarted == nil { queueStarted = Date() }
        queue[i].state = .running
        queue[i].counted = true
        currentID = queue[i].id
        let job = queue[i]
        DockProgress.set(queueFraction)
        switch job.kind {
        case .copy: run(copy: job)
        case .check: run(check: job)
        }
    }

    private func finish(_ id: UUID?, state: QueueJob.State, summary: String, fraction: Double,
                        _ extra: (inout QueueJob) -> Void = { _ in }) {
        update(id) { j in
            j.state = state
            j.summary = summary
            j.fraction = fraction
            j.plan = nil
            extra(&j)
        }
        lastFinishedID = id
        currentID = nil
        refreshQueue()
        advance()
    }

    private func refreshQueue() {
        guard queueStarted != nil else { return }
        let f = queueFraction
        DockProgress.set(f)
        queueETA = ETA.text(started: queueStarted, fraction: f)
    }

    /// Takes a job that hasn't started out of the queue, or clears a finished one from the list.
    func remove(_ id: UUID) {
        guard id != currentID else { return }
        queue.removeAll { $0.id == id }
        if inspectID == id { inspectID = nil }
    }

    func clearFinished() {
        queue.removeAll { $0.isFinished }
        inspectID = nil
    }

    /// Stops the running job and everything waiting behind it.
    func stopQueue() {
        for i in queue.indices where queue[i].state == .waiting {
            queue[i].state = .stopped
            queue[i].summary = "Not started"
        }
        stop()
    }

    // MARK: copy setup

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
                    self.plans[path] = (plan, Date(), o.includeHidden)
                }
            }
        }
    }

    func removeSource(_ path: String) {
        sources.removeAll { $0.path == path }
        plans[path] = nil
    }

    func addDestination(_ url: URL) {
        guard destinations.count < 3 else { return }
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

    private func verifyText(_ v: VerifyMode) -> String {
        switch v {
        case .destination: return "verifying each destination"
        case .both: return "verifying source and destinations"
        case .off: return "not verifying"
        }
    }

    /// Starts the copy now, or lines it up behind whatever is running.
    func enqueueCopy() {
        guard blocker == nil else { return }
        let o = options
        let n = sources.count
        let destText = destinations.map { $0.volumeName.isEmpty ? $0.name : $0.volumeName }.joined(separator: " and ")
        let title = n == 1 ? "Copy \(sources[0].name)" : "Copy \(n) items"
        var job = QueueJob(kind: .copy, title: title,
                           detail: "\(Fmt.bytes(totalBytes)) to \(destText)  ·  \(o.hash.title)  ·  \(verifyText(o.verify))")
        job.options = o
        job.sources = sources
        job.dests = destinations
        job.destNames = destinations.map { $0.volumeName.isEmpty ? $0.name : "\($0.volumeName) · \($0.name)" }
        job.bytes = totalBytes * (o.verify == .off ? 1 : 2)
        // The folders were listed when they were added; reuse that so the copy starts at once.
        var merged = TransferPlan()
        var oldest = Date()
        var reusable = true
        for s in sources {
            guard let p = plans[s.path], p.hidden == o.includeHidden else { reusable = false; break }
            merged.entries += p.plan.entries
            merged.fileCount += p.plan.fileCount
            merged.totalBytes += p.plan.totalBytes
            merged.unreadable += p.plan.unreadable
            oldest = min(oldest, p.at)
        }
        if reusable {
            merged.entries.sort { $0.rel < $1.rel }
            job.plan = merged
            job.planAt = oldest
        }
        sources = []
        destinations = []
        plans = [:]
        conflict = .skip
        enqueue(job)
    }

    // MARK: run a copy

    private func run(copy job: QueueJob) {
        let o = job.options
        let srcs = job.sources.map(\.path)
        let dests = job.dests.map(\.path)
        runSources = job.sources
        runDests = job.dests
        runOptions = o
        destNames = job.destNames
        jobLine = "\(job.title)  ·  \(job.detail)"
        lastDestCopied = []
        destSpeeds = []
        snap = TransferSnapshot()
        history = []
        peak = 0
        speed = 0
        etaText = nil
        paceNote = nil
        window = []
        listedFiles = 0
        engine = nil
        stage = .preparing
        let counter = Shared(0)
        listCounter = counter
        let stopFlag = Shared(false)
        prepStop = stopFlag
        startTimer()
        // A listing less than ten minutes old is still good; older than that, look again.
        var ready: TransferPlan?
        if let plan = job.plan, let at = job.planAt, Date().timeIntervalSince(at) < 600 { ready = plan }
        let prepared = ready
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let plan = prepared ?? TransferPlanner.build(sources: srcs, options: o, keepGoing: { !stopFlag.value },
                                                         found: { n in counter.value = n })
            var classes: [String: DeviceClass] = [:]
            for p in srcs + dests { if let c = Hardware.expected(forPath: p) { classes[p] = c } }
            let engine = TransferEngine(plan: plan, destinations: dests, options: o)
            if stopFlag.value { engine.cancel() }
            Task { @MainActor in self?.begin(engine, classes) }
            engine.run()
            Task { @MainActor in self?.finished(engine) }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        lastTick = Date()
        lastBytes = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func begin(_ engine: TransferEngine, _ classes: [String: DeviceClass]) {
        self.engine = engine
        expected = classes
        stage = .running
        lastBytes = 0
        lastTick = Date()
    }

    private func tick() {
        if checkStage == .running { tickCheck(); return }
        guard let engine else {
            listedFiles = listCounter.value
            return
        }
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
            update(currentID) { j in
                j.fraction = s.fraction
                if s.totalBytes + s.verifyTotal > 0 { j.bytes = s.totalBytes + s.verifyTotal }
            }
            refreshQueue()
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
            (runSources.first?.name ?? "The source", "reading", readSecs, runSources.first.flatMap { expected[$0.path] })
        for (i, d) in runDests.enumerated() where i < s.writeNanos.count && i < first.write.count {
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
        let s = engine.snapshot()
        snap = s
        speed = 0
        etaText = nil
        paceNote = nil
        self.engine = nil
        stage = .done
        let state: QueueJob.State
        let summary: String
        if s.phase == .stopped {
            state = .stopped
            summary = "Stopped at \(Fmt.pct(s.fraction))"
        } else if s.problems.isEmpty {
            state = .done
            summary = runOptions.verify == .off ? "\(Fmt.count(s.good)) files copied" : "\(Fmt.count(s.good)) files verified"
        } else {
            state = .attention
            summary = "\(Fmt.count(s.problems.count)) need attention"
        }
        finish(currentID, state: state, summary: summary, fraction: s.phase == .stopped ? s.fraction : 1) { j in
            j.result = s
        }
    }

    func pause() { engine?.pause(); snap.paused = true }
    func resume() { engine?.resume(); snap.paused = false }
    /// Stops the running job. The queue moves on to the next one.
    func stop() { prepStop.value = true; engine?.cancel(); compare?.cancel() }

    /// Back to an empty setup screen.
    func reset() {
        sources = []
        destinations = []
        plans = [:]
        conflict = .skip
        mode = 0
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
    }

    func setCheckFolder(_ url: URL, original isOriginal: Bool) {
        var isDir: ObjCBool = false
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        if isOriginal { original = path } else { copyFolder = path }
    }

    var checkBlocker: String? {
        guard let a = original, let b = copyFolder else { return "Choose the original folder and the copy." }
        if a == b { return "Those are the same folder." }
        return nil
    }

    /// Starts the check now, or lines it up behind whatever is running.
    func enqueueCheck() {
        guard checkBlocker == nil, let a = original, let b = copyFolder else { return }
        var job = QueueJob(kind: .check, title: "Check \((b as NSString).lastPathComponent)",
                           detail: "\(checkFull ? "Checksums" : "Names and sizes")  ·  against \((a as NSString).lastPathComponent)")
        job.options = options
        job.original = a
        job.copy = b
        job.full = checkFull
        original = nil
        copyFolder = nil
        enqueue(job)
    }

    private func run(check job: QueueJob) {
        let cmp = CompareJob()
        compare = cmp
        checkStage = .running
        checkFraction = 0
        checkStatus = "Listing both folders"
        checkETA = nil
        checkHashing = false
        checkListed = 0
        checkRate = 0
        checkBytesDone = 0
        checkBytesTotal = 0
        checkFilesDone = 0
        checkFilesTotal = 0
        checkStarted = Date()
        checkStartedAt = Date()
        history = []
        speed = 0
        var want = 0
        if let ea = expectedFiles?(job.original), let eb = expectedFiles?(job.copy) { want = ea + eb }
        checkExpected = want
        startTimer()
        let a = job.original, b = job.copy, full = job.full, o = job.options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = cmp.run(original: a, copy: b, full: full, options: o)
            let cancelled = cmp.isCancelled
            Task { @MainActor in self?.checkFinished(result, cancelled: cancelled, full: full) }
        }
    }

    @Published private(set) var checkExpected = 0          // files a saved map says to expect (0 = no map)
    private var lastListed = 0

    private func tickCheck() {
        guard let cmp = compare else { return }
        let p = cmp.progress
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        guard dt > 0.2 else { return }
        lastTick = now
        let full = runningJob?.full ?? false
        if !p.hashing {
            // Listing: files found per second, and time left when a saved map says how many to expect.
            let rate = max(0, Double(p.listed - lastListed) / dt)
            lastListed = p.listed
            checkRate = checkRate == 0 ? rate : checkRate * 0.7 + rate * 0.3
            history.append(rate)
            checkListed = p.listed
            var listFraction = 0.0
            if checkExpected > 0 { listFraction = min(0.99, Double(p.listed) / Double(checkExpected)) }
            checkFraction = full ? 0 : listFraction
            checkStatus = "Listing both folders"
            checkETA = checkExpected > 0 ? ETA.text(started: checkStarted, fraction: listFraction) : nil
        } else {
            if !checkHashing {
                // The checksum pass starts: a fresh graph, in MB/s.
                checkHashing = true
                history = []
                lastBytes = 0
                speed = 0
            }
            let instant = max(0, Double(p.bytesDone - lastBytes) / dt)
            lastBytes = p.bytesDone
            speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
            history.append(instant / 1_000_000)
            checkFraction = p.fraction
            checkStatus = "Comparing checksums"
            checkListed = p.listed
            checkBytesDone = p.bytesDone
            checkBytesTotal = p.bytesTotal
            checkFilesDone = p.filesDone
            checkFilesTotal = p.filesTotal
            let recent = history.suffix(20)
            let avg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count) * 1_000_000
            checkETA = (avg > 0 && history.count >= 6) ? ETA.text(Double(p.bytesTotal - p.bytesDone) / avg) : nil
        }
        if history.count > 240 { history.removeFirst(history.count - 240) }
        let f = checkFraction
        update(currentID) { j in
            j.fraction = f
            if p.bytesTotal > 0 { j.bytes = p.bytesTotal }
        }
        refreshQueue()
    }

    private func checkFinished(_ result: CompareResult, cancelled: Bool, full: Bool) {
        timer?.invalidate()
        timer = nil
        compare = nil
        lastListed = 0
        checkStage = .setup
        checkETA = nil
        speed = 0
        if cancelled {
            finish(currentID, state: .stopped, summary: "Stopped", fraction: checkFraction)
            return
        }
        let state: QueueJob.State = result.isComplete ? .done : .attention
        let summary: String
        if result.isComplete {
            summary = full ? "Complete, \(Fmt.count(result.matched)) checksums match" : "Complete, \(Fmt.count(result.matched)) files"
        } else {
            summary = "\(Fmt.count(result.missing.count)) missing, \(Fmt.count(result.different.count)) different"
        }
        finish(currentID, state: state, summary: summary, fraction: 1) { j in j.checkResult = result }
    }

    /// Copies what a check found missing into the copy folder, keeping the folder structure.
    /// Files that exist but differ are left for you to decide.
    func copyMissing(from job: QueueJob) {
        guard let result = job.checkResult, !result.missing.isEmpty else { return }
        var plan = TransferPlan()
        for m in result.missing {
            let src = TransferEngine.join(job.original, m.rel)
            var st = stat()
            guard lstat(src, &st) == 0 else { continue }
            plan.entries.append(PlanEntry(source: src, rel: m.rel, kind: .file, size: Int64(st.st_size),
                                          modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))))
            plan.fileCount += 1
            plan.totalBytes += Int64(st.st_size)
        }
        guard plan.fileCount > 0 else { return }
        let name = (job.copy as NSString).lastPathComponent
        var next = QueueJob(kind: .copy, title: "Copy \(Fmt.count(plan.fileCount)) missing file\(plan.fileCount == 1 ? "" : "s")",
                            detail: "\(Fmt.bytes(plan.totalBytes)) to \(name)  ·  \(hash.title)  ·  verifying")
        next.options = TransferOptions(hash: hash, verify: verify == .off ? .destination : verify, conflict: .skip,
                                       includeHidden: includeHidden, skipClutter: true, writeLists: writeLists)
        next.sources = [SourceItem(path: job.original, files: plan.fileCount, bytes: plan.totalBytes, sized: true, isFolder: true)]
        next.dests = [DestItem(path: job.copy)]
        next.destNames = [name]
        next.bytes = plan.totalBytes * 2
        next.plan = plan
        next.planAt = Date.distantFuture      // an exact list of files; never listed again
        inspectID = nil
        enqueue(next)
        mode = 2
    }
}
