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
    var devices: Set<String> = []        // the drives and links it uses; jobs that share none can run together

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

/// One job while it runs: its engine, its timer and everything its live view shows.
@MainActor
final class JobRun: ObservableObject {
    enum Stage { case preparing, running, done }

    let id: UUID
    let kind: QueueJob.Kind
    let full: Bool
    var onProgress: (@MainActor (Double, Int64) -> Void)?
    var onFinish: (@MainActor (QueueJob.State, String, Double, TransferSnapshot?, CompareResult?) -> Void)?

    // Copy
    @Published private(set) var stage: Stage = .preparing
    @Published private(set) var snap = TransferSnapshot()
    @Published private(set) var speed: Double = 0          // bytes per second, smoothed
    @Published private(set) var history: [Double] = []     // one sample each half second (MB/s, or files/s while listing)
    @Published private(set) var graph: [Double] = []       // the whole job so far, thinned as it grows
    @Published private(set) var etaText: String?
    @Published private(set) var paceNote: String?
    @Published private(set) var destNames: [String] = []
    @Published private(set) var destSpeeds: [Double] = []   // bytes per second written, per destination
    @Published private(set) var listedFiles = 0            // found so far while a copy is being listed
    @Published private(set) var runOptions = TransferOptions()

    // Check a copy
    @Published private(set) var checkFraction: Double = 0
    @Published private(set) var checkStatus = "Listing both folders"
    @Published private(set) var checkETA: String?
    @Published private(set) var checkHashing = false
    @Published private(set) var checkListed = 0
    @Published private(set) var checkRate: Double = 0      // files per second while listing
    @Published private(set) var checkBytesDone: Int64 = 0
    @Published private(set) var checkBytesTotal: Int64 = 0
    @Published private(set) var checkFilesDone = 0
    @Published private(set) var checkFilesTotal = 0
    @Published private(set) var checkExpected = 0          // files a saved map says to expect (0 = no map)
    let startedAt = Date()

    private var runSources: [TransferModel.SourceItem] = []
    private var runDests: [TransferModel.DestItem] = []
    private var lastDestCopied: [Int64] = []
    private var listCounter = Shared(0)
    private var prepStop = Shared(false)
    private var engine: TransferEngine?
    private var compare: CompareJob?
    private var timer: Timer?
    private var lastBytes: Int64 = 0
    private var lastTick = Date()
    private var lastListed = 0
    private var graphStride = 1          // half-second samples per graph point
    private var graphSum = 0.0
    private var graphCount = 0
    private var window: [(read: UInt64, write: [UInt64], copied: Int64, files: Int)] = []
    private var expected: [String: DeviceClass] = [:]     // path → what its drive should manage

    init(job: QueueJob, expectedCount: Int) {
        id = job.id
        kind = job.kind
        full = job.full
        checkExpected = expectedCount
    }

    var isPaused: Bool { snap.paused }
    var canPause: Bool { kind == .copy }
    /// Time left for this job, whichever kind it is.
    var eta: String? { kind == .copy ? etaText : checkETA }
    var fraction: Double { kind == .copy ? snap.fraction : checkFraction }
    /// Bytes per second right now (0 while listing).
    var liveSpeed: Double { kind == .check && !checkHashing ? 0 : speed }

    func start(_ job: QueueJob) {
        switch job.kind {
        case .copy: run(copy: job)
        case .check: run(check: job)
        }
    }

    func pause() { engine?.pause(); snap.paused = true }
    func resume() { engine?.resume(); snap.paused = false }
    func stop() { prepStop.value = true; engine?.cancel(); compare?.cancel() }

    private func startTimer() {
        timer?.invalidate()
        lastTick = Date()
        lastBytes = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        if kind == .check { tickCheck() } else { tickCopy() }
    }

    /// Adds a sample to the whole-job graph. When it gets long, neighbours are averaged together
    /// so the full run always fits.
    private func plot(_ value: Double) {
        graphSum += value
        graphCount += 1
        guard graphCount >= graphStride else { return }
        graph.append(graphSum / Double(graphCount))
        graphSum = 0
        graphCount = 0
        if graph.count >= 480 {
            var half: [Double] = []
            half.reserveCapacity(240)
            var i = 0
            while i + 1 < graph.count {
                half.append((graph[i] + graph[i + 1]) / 2)
                i += 2
            }
            graph = half
            graphStride *= 2
        }
    }

    private func resetGraph() {
        graph = []
        graphStride = 1
        graphSum = 0
        graphCount = 0
    }

    // MARK: copy

    private func run(copy job: QueueJob) {
        let o = job.options
        let srcs = job.sources.map(\.path)
        let dests = job.dests.map(\.path)
        runSources = job.sources
        runDests = job.dests
        runOptions = o
        destNames = job.destNames
        stage = .preparing
        let counter = listCounter
        let stopFlag = prepStop
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

    private func begin(_ engine: TransferEngine, _ classes: [String: DeviceClass]) {
        self.engine = engine
        expected = classes
        stage = .running
        lastBytes = 0
        lastTick = Date()
    }

    private func tickCopy() {
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
            if !s.paused { plot(instant / 1_000_000) }
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
            snap = s
            onProgress?(s.fraction, s.totalBytes + s.verifyTotal)
        } else {
            snap = s
        }
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
        onFinish?(state, summary, s.phase == .stopped ? s.fraction : 1, s, nil)
    }

    // MARK: check a copy

    private func run(check job: QueueJob) {
        let cmp = CompareJob()
        compare = cmp
        stage = .running
        startTimer()
        let a = job.original, b = job.copy, full = job.full, o = job.options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = cmp.run(original: a, copy: b, full: full, options: o)
            let cancelled = cmp.isCancelled
            Task { @MainActor in self?.checkFinished(result, cancelled: cancelled) }
        }
    }

    private func tickCheck() {
        guard let cmp = compare else { return }
        let p = cmp.progress
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        guard dt > 0.2 else { return }
        lastTick = now
        if !p.hashing {
            // Listing: files found per second, and time left when a saved map says how many to expect.
            let rate = max(0, Double(p.listed - lastListed) / dt)
            lastListed = p.listed
            checkRate = checkRate == 0 ? rate : checkRate * 0.7 + rate * 0.3
            history.append(rate)
            plot(rate)
            checkListed = p.listed
            var listFraction = 0.0
            if checkExpected > 0 { listFraction = min(0.99, Double(p.listed) / Double(checkExpected)) }
            checkFraction = full ? 0 : listFraction
            checkStatus = "Listing both folders"
            checkETA = checkExpected > 0 ? ETA.text(started: startedAt, fraction: listFraction) : nil
        } else {
            if !checkHashing {
                // The checksum pass starts: a fresh graph, in MB/s.
                checkHashing = true
                history = []
                resetGraph()
                lastBytes = 0
                speed = 0
            }
            let instant = max(0, Double(p.bytesDone - lastBytes) / dt)
            lastBytes = p.bytesDone
            speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
            history.append(instant / 1_000_000)
            plot(instant / 1_000_000)
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
        onProgress?(checkFraction, p.bytesTotal)
    }

    private func checkFinished(_ result: CompareResult, cancelled: Bool) {
        timer?.invalidate()
        timer = nil
        compare = nil
        checkETA = nil
        speed = 0
        stage = .done
        if cancelled {
            onFinish?(.stopped, "Stopped", checkFraction, nil, nil)
            return
        }
        let summary: String
        if result.isComplete {
            summary = full ? "Complete, \(Fmt.count(result.matched)) checksums match" : "Complete, \(Fmt.count(result.matched)) files"
        } else {
            summary = "\(Fmt.count(result.missing.count)) missing, \(Fmt.count(result.different.count)) different"
        }
        onFinish?(result.isComplete ? .done : .attention, summary, 1, nil, result)
    }
}

/// State for the Copy & Verify screen: what to copy, where, how, and the queue of jobs.
@MainActor
final class TransferModel: ObservableObject {
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

    /// Jobs on separate hardware run together, up to this many.
    static let maxTogether = 3

    @Published var mode = 0                               // the new-job form: 0 copy, 1 check a copy
    @Published var showQueue = true                       // the queue column

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

    // Check a copy: setup
    @Published var original: String?
    @Published var copyFolder: String?
    @Published var checkFull = false

    // Queue
    @Published private(set) var queue: [QueueJob] = []
    @Published private(set) var runs: [UUID: JobRun] = [:]   // the jobs running now
    @Published var inspectID: UUID?                        // the job shown in full; nil shows the new-job form
    @Published private(set) var queueETA: String?
    private var lastFinishedID: UUID?
    private var queueStarted: Date?

    /// How many files a folder held when it was last mapped, if a saved map covers it.
    var expectedFiles: (@MainActor (String) -> Int?)?

    private var plans: [String: (plan: TransferPlan, at: Date, hidden: Bool)] = [:]

    var isBusy: Bool { !runs.isEmpty }
    var busyFraction: Double { queueFraction }

    // MARK: queue

    var waitingCount: Int { queue.filter { $0.state == .waiting }.count }
    var runningCount: Int { runs.count }
    var countedJobs: [QueueJob] { queue.filter { $0.counted } }
    /// Bytes per second across every running job.
    var totalSpeed: Double { runs.values.reduce(0) { $0 + $1.liveSpeed } }
    var lastFinishedJob: QueueJob? {
        guard let id = lastFinishedID else { return nil }
        return queue.first { $0.id == id }
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

    /// The job shown in full beside the queue, if one is picked.
    var shownJob: QueueJob? {
        guard let id = inspectID else { return nil }
        return queue.first { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout QueueJob) -> Void) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        change(&queue[i])
    }

    private func devices(for job: QueueJob) -> Set<String> {
        var paths = job.sources.map(\.path) + job.dests.map(\.path)
        if job.kind == .check { paths += [job.original, job.copy] }
        return Set(paths.map { Hardware.deviceKey(forPath: $0) })
    }

    private func enqueue(_ job: QueueJob) {
        var job = job
        job.devices = devices(for: job)
        let wasIdle = !isBusy
        if wasIdle {
            // A new run: jobs finished earlier no longer count toward its progress.
            for i in queue.indices { queue[i].counted = false }
            inspectID = nil
        }
        queue.append(job)
        showQueue = true
        if wasIdle { inspectID = job.id }
        advance()
    }

    /// Starts every waiting job whose drives are free. A job never jumps ahead of an earlier one
    /// that is waiting for the same drive.
    private func advance() {
        var inUse = Set<String>()
        for j in queue where j.state == .running { inUse.formUnion(j.devices) }
        var held = Set<String>()
        var active = runs.count
        for i in queue.indices where queue[i].state == .waiting {
            let d = queue[i].devices
            if active < Self.maxTogether && d.isDisjoint(with: inUse) && d.isDisjoint(with: held) {
                inUse.formUnion(d)
                active += 1
                start(i)
            } else {
                held.formUnion(d)
            }
        }
        if runs.isEmpty, queueStarted != nil {
            queueStarted = nil
            queueETA = nil
            DockProgress.set(nil)
            NSSound(named: "Glass")?.play()
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    private func start(_ i: Int) {
        if queueStarted == nil { queueStarted = Date() }
        queue[i].state = .running
        queue[i].counted = true
        let job = queue[i]
        let id = job.id
        var want = 0
        if job.kind == .check, let a = expectedFiles?(job.original), let b = expectedFiles?(job.copy) { want = a + b }
        let run = JobRun(job: job, expectedCount: want)
        run.onProgress = { [weak self] fraction, bytes in
            guard let self else { return }
            self.update(id) { j in
                j.fraction = fraction
                if bytes > 0 { j.bytes = bytes }
            }
            self.refreshQueue()
        }
        run.onFinish = { [weak self] state, summary, fraction, snap, result in
            guard let self else { return }
            self.update(id) { j in
                j.state = state
                j.summary = summary
                j.fraction = fraction
                j.plan = nil
                j.result = snap
                j.checkResult = result
            }
            self.runs[id] = nil
            self.lastFinishedID = id
            self.refreshQueue()
            self.advance()
        }
        runs[id] = run
        DockProgress.set(queueFraction)
        run.start(job)
    }

    private func refreshQueue() {
        guard queueStarted != nil else { return }
        let f = queueFraction
        DockProgress.set(f)
        queueETA = ETA.text(started: queueStarted, fraction: f)
    }

    /// Takes a job that hasn't started out of the queue, or clears a finished one from the list.
    func remove(_ id: UUID) {
        guard runs[id] == nil else { return }
        queue.removeAll { $0.id == id }
        if inspectID == id { inspectID = nil }
        advance()
    }

    func clearFinished() {
        queue.removeAll { $0.isFinished }
        inspectID = nil
    }

    func pause(_ id: UUID) { runs[id]?.pause() }
    func resume(_ id: UUID) { runs[id]?.resume() }
    /// Stops one running job. Jobs waiting for its drives start next.
    func stop(_ id: UUID) { runs[id]?.stop() }

    /// Stops every running job and everything waiting.
    func stopQueue() {
        for i in queue.indices where queue[i].state == .waiting {
            queue[i].state = .stopped
            queue[i].summary = "Not started"
        }
        for run in runs.values { run.stop() }
    }

    /// Back to an empty setup screen.
    func reset() {
        sources = []
        destinations = []
        plans = [:]
        conflict = .skip
        mode = 0
        inspectID = nil
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
        enqueue(next)
        inspectID = next.id
    }
}
