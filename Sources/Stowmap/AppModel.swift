import SwiftUI
import AppKit

// MARK: - Saved index (last scan of each drive, reopened instantly)

private struct CachedNode: Codable {
    var n: String
    var k: UInt8
    var h: Bool
    var s: Int64
    var c: Int
    var ch: [CachedNode]?
    var l: Int64? = nil      // file length, for duplicate matching (absent in older saves)
}

private struct CachedScan: Codable {
    var version = 1
    var root: CachedNode
    var types: [TypeStat]
    var largest: [LargeFile]
    var date: Date
    var duration: TimeInterval
    var denied: Int
}

enum ScanStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Stowmap/Index", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func url(_ v: Volume) -> URL { dir.appendingPathComponent(v.cacheKey + ".stowmap") }

    /// Keeps everything that matters for browsing; rolls up entries too small to see on the map.
    private static func pack(_ n: FileNode, floor: Int64) -> CachedNode {
        var kids: [CachedNode] = []
        var restBytes: Int64 = 0
        var restCount = 0
        for c in n.children {
            if c.size >= floor || c.kind == .hiddenSpace {
                kids.append(pack(c, floor: floor))
            } else {
                restBytes += c.size
                restCount += c.fileCount
            }
        }
        if restBytes > 0 {
            kids.append(CachedNode(n: "Smaller items", k: FileNode.Kind.smallFiles.rawValue, h: false,
                                   s: restBytes, c: restCount, ch: nil))
        }
        return CachedNode(n: n.name, k: n.kind.rawValue, h: n.isHidden, s: n.size, c: n.fileCount,
                          ch: kids.isEmpty ? nil : kids, l: n.logical > 0 ? n.logical : nil)
    }

    private static func unpack(_ c: CachedNode) -> FileNode {
        let node = FileNode(name: c.n, kind: FileNode.Kind(rawValue: c.k) ?? .file, isHidden: c.h,
                            size: c.s, fileCount: c.c)
        node.logical = c.l ?? 0
        if let ch = c.ch {
            node.children = ch.map { sub in
                let k = unpack(sub)
                k.parent = node
                return k
            }
            // The "Smaller items" roll-up is appended last by pack(); keep largest-first order.
            node.children.sort { $0.size > $1.size }
        }
        return node
    }

    static func save(_ r: ScanResult, for v: Volume) {
        let floor = max(1_000_000, r.root.size / 400_000)
        let cached = CachedScan(root: pack(r.root, floor: floor), types: Array(r.types.prefix(400)),
                                largest: r.largest, date: r.date, duration: r.duration, denied: r.denied)
        guard let json = try? JSONEncoder().encode(cached),
              let packed = try? (json as NSData).compressed(using: .lzfse) else { return }
        try? (packed as Data).write(to: url(v), options: .atomic)
    }

    static func load(for v: Volume) -> ScanResult? {
        guard let packed = try? Data(contentsOf: url(v)),
              let json = try? (packed as NSData).decompressed(using: .lzfse),
              let cached = try? JSONDecoder().decode(CachedScan.self, from: json as Data),
              cached.version == 1 else { return nil }
        let root = unpack(cached.root)
        root.rootPath = v.path
        return ScanResult(root: root, types: cached.types, largest: cached.largest, date: cached.date,
                          duration: cached.duration, denied: cached.denied, fromCache: true)
    }

    static func remove(for v: Volume) { try? FileManager.default.removeItem(at: url(v)) }
}

// MARK: - One drive's scan + navigation state

@MainActor
final class ScanSession: ObservableObject, Identifiable {
    enum Phase { case idle, scanning, done }

    @Published var volume: Volume
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: ScanResult?
    @Published var focus: FileNode?
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var recentPaths: [String] = []   // newest first, for the scanning view
    private(set) var startedAt: Date?
    @Published private(set) var collected: [FileNode] = []
    @Published var trashError: String?
    @Published private(set) var revision = 0      // bumps when the tree changes in place

    nonisolated let id: String
    private var ctx: ScanContext?
    private var timer: Timer?
    /// Called when this session gains or replaces a result, so the app can account for sibling shares.
    var onResultChanged: (() -> Void)?

    init(volume: Volume) {
        self.volume = volume
        self.id = volume.id
        let v = volume
        Task.detached(priority: .utility) { [weak self] in
            guard let cached = ScanStore.load(for: v) else { return }
            await self?.adoptCached(cached)
        }
    }

    private func adoptCached(_ r: ScanResult) {
        guard result == nil, phase == .idle else { return }
        result = r
        focus = r.root
        phase = .done
        onResultChanged?()
    }

    var isScanning: Bool { phase == .scanning }

    func start() {
        guard phase != .scanning else { return }
        let context = DiskScanner.makeContext(for: volume)
        ctx = context
        progress = ScanProgress()
        recentPaths = []
        startedAt = Date()
        phase = .scanning
        collected = []

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] t in
            // The session can be dropped (drive unplugged) mid-scan; don't tick forever.
            guard self != nil else { t.invalidate(); return }
            let snap = context.snapshot()
            Task { @MainActor in self?.tick(snap) }
        }

        let v = volume
        // A plain GCD thread: the walk blocks until done, which would tie up a Swift concurrency thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = DiskScanner.run(volume: v, ctx: context)
            let cancelled = context.isCancelled
            Task { @MainActor in self?.finish(r, cancelled: cancelled) }
        }
    }

    private func tick(_ snap: ScanProgress) {
        progress = snap
        if !snap.path.isEmpty, snap.path != recentPaths.first {
            recentPaths.insert(snap.path, at: 0)
            if recentPaths.count > 6 { recentPaths.removeLast() }
        }
    }

    func cancel() { ctx?.cancel() }

    private func finish(_ scanned: ScanResult, cancelled: Bool) {
        timer?.invalidate()
        timer = nil
        ctx = nil
        if cancelled {
            phase = result == nil ? .idle : .done
            return
        }
        let r = scanned
        if volume.poolKey == nil { addHiddenSpace(to: r.root) }
        result = r
        focus = r.root
        phase = .done
        revision += 1
        onResultChanged?()      // network shares: the app fills in what else is on the server
        let v = volume
        Task.detached(priority: .utility) { ScanStore.save(r, for: v) }
    }

    /// Used space the file system reports but no walk can reach: snapshots, purgeable data,
    /// protected system files. Shown as its own entry so totals match Finder.
    private func addHiddenSpace(to root: FileNode) {
        guard volume.kind != .folder, volume.total > 0 else { return }
        let reallyUsed = volume.total - volume.realFree
        let gap = reallyUsed - root.size
        guard gap > max(500_000_000, volume.total / 200) else { return }
        let node = FileNode(name: volume.kind == .network ? "Elsewhere on this server" : "Hidden space",
                            kind: .hiddenSpace, size: gap)
        node.parent = root
        root.children.append(node)
        root.children.sort { $0.size > $1.size }
        root.size += gap
    }

    /// What this share's own files add up to, without any stand-in entries.
    var ownScannedBytes: Int64? {
        guard let root = result?.root else { return nil }
        return root.children.reduce(Int64(0)) { $0 + ($1.kind == .hiddenSpace ? 0 : $1.size) }
    }

    /// A server reports the used space of its whole storage pool, so a share's total is bigger than
    /// its own files. Explain the difference: one entry per sibling share that has been scanned
    /// (named, with its real size), and one "Elsewhere on this server" entry for the remainder.
    func applyServerGap(siblings: [(id: String, name: String, bytes: Int64)]) {
        guard let root = result?.root, volume.total > 0 else { return }
        let focusWasStandIn = focus?.kind == .hiddenSpace
        root.children.removeAll { $0.kind == .hiddenSpace }
        var own: Int64 = 0
        for c in root.children { own += c.size }
        var gap = (volume.total - volume.realFree) - own
        let floor = max(500_000_000, volume.total / 200)

        for sib in siblings.sorted(by: { $0.bytes > $1.bytes }) where sib.bytes > 0 && gap > 0 {
            let size = min(sib.bytes, gap)
            let node = FileNode(name: sib.name, kind: .hiddenSpace, size: size)
            node.linkedVolumeID = sib.id
            node.parent = root
            root.children.append(node)
            gap -= size
        }
        if gap > floor {
            let node = FileNode(name: "Elsewhere on this server", kind: .hiddenSpace, size: gap)
            node.parent = root
            root.children.append(node)
        }
        var total: Int64 = 0
        for c in root.children { total += c.size }
        root.size = total
        root.children.sort { $0.size > $1.size }
        if focusWasStandIn { focus = root }
        revision += 1
    }

    // MARK: navigation

    func drill(_ node: FileNode) {
        guard node.canDrill else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { focus = node }
    }

    func goUp() {
        guard let p = focus?.parent else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { focus = p }
    }

    /// Jump to the folder containing a path (used by Largest Files).
    func show(path: String) {
        guard let root = result?.root, let rootPath = root.rootPath, path.hasPrefix(rootPath) else { return }
        var node = root
        let rel = path.dropFirst(rootPath.count)
        for part in rel.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == part && $0.isFolder }) else { break }
            node = next
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { focus = node }
    }

    // MARK: collector

    func isCollected(_ node: FileNode) -> Bool { collected.contains { $0 === node } }

    var collectedBytes: Int64 { collected.reduce(0) { $0 + $1.size } }

    func toggleCollect(_ node: FileNode) {
        guard node.isReal, node.parent != nil else { return }
        if let i = collected.firstIndex(where: { $0 === node }) {
            collected.remove(at: i)
            return
        }
        // Already covered by a collected parent folder?
        var up = node.parent
        while let u = up {
            if isCollected(u) { return }
            up = u.parent
        }
        // Collecting a folder replaces anything inside it that was collected on its own.
        collected.removeAll { item in
            var p = item.parent
            while let q = p { if q === node { return true }; p = q.parent }
            return false
        }
        collected.append(node)
    }

    func clearCollected() { collected = [] }

    /// Moves everything in the collector to the Trash (recoverable) and updates the map in place.
    func trashCollected() {
        var failures: [String] = []
        var trashed: [String] = []
        for node in collected {
            let path = node.path
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(path)
                detach(node)
            } catch {
                failures.append("\(node.name): \(error.localizedDescription)")
            }
        }
        collected = []
        if !trashed.isEmpty {
            // Largest Files is a flat list of paths: drop anything that just went to the Trash.
            result?.largest.removeAll { f in
                trashed.contains { f.path == $0 || f.path.hasPrefix($0 + "/") }
            }
        }
        revision += 1
        if !failures.isEmpty {
            trashError = failures.prefix(5).joined(separator: "\n")
                + (failures.count > 5 ? "\n…and \(failures.count - 5) more" : "")
        }
        if let r = result {
            let v = volume
            Task.detached(priority: .utility) { ScanStore.save(r, for: v) }
        }
    }

    private func detach(_ node: FileNode) {
        guard let parent = node.parent else { return }
        if let f = focus, f.ancestry.contains(where: { $0 === node }) { focus = parent }
        parent.children.removeAll { $0 === node }
        var up: FileNode? = parent
        while let u = up {
            u.size -= node.size
            u.fileCount -= node.fileCount
            u.children.sort { $0.size > $1.size }
            up = u.parent
        }
    }
}

// MARK: - App state

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var volumes: [Volume] = []
    @Published var selectedID: String?
    @Published private(set) var sessions: [String: ScanSession] = [:]

    /// What the main area shows: one drive's map, search results, or duplicates.
    enum Pane { case drive, search, duplicates }
    @Published var pane: Pane = .drive

    // Search across every scanned drive
    @Published var searchText = ""
    @Published var searchKind = 0                    // 0 all, 1 folders, 2 files
    @Published private(set) var searchResults: [SearchHit] = []
    @Published private(set) var searchTotal = 0
    @Published private(set) var searchBusy = false
    @Published private(set) var searchedFor = ""
    private var searchToken = 0
    @Published private(set) var searchProgress: Double = 0
    private var searchTimer: Timer?

    // Duplicates across every scanned drive
    enum DupPhase { case idle, running, done }
    @Published private(set) var dupPhase: DupPhase = .idle
    @Published private(set) var dupGroups: [DupGroup] = [] {
        didSet {
            var roots: [String: String] = [:]
            for (id, session) in sessions { roots[id] = session.volume.path }
            dupMatches = DuplicateFinder.folderMatches(dupGroups, rootPaths: roots)
        }
    }
    /// The same results, rolled up into the folders that hold the copies.
    @Published private(set) var dupMatches: [FolderMatch] = []
    @Published private(set) var dupProgress = DupProgress()
    @Published private(set) var dupVerifying = Set<Int>()
    /// Verify jobs that are queued or running: key → how far along (0…1).
    @Published private(set) var verifyFractions: [String: Double] = [:]
    @Published private(set) var verifyOverall: Double = 0
    private var verifyJobs: [VerifyJob] = []
    private var verifyTimer: Timer?
    private let verifyQueue = DispatchQueue(label: "com.midjulymedia.stowmap.verify", qos: .utility)
    @Published var toolError: String?
    /// nil = every scanned drive; otherwise the one drive to look within.
    @Published private(set) var dupScope: String?
    private var dupScan: DuplicateScan?
    private var dupTimer: Timer?

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private let foldersKey = "scanFolders"
    private var generation = 0     // bumps when the folder list changes; stale refreshes are dropped

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    var selected: ScanSession? { selectedID.flatMap { sessions[$0] } }

    private var folderPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: foldersKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: foldersKey) }
    }

    func refresh() {
        let folders = folderPaths
        let gen = generation
        Task.detached(priority: .userInitiated) { [weak self] in
            let list = AppModel.readVolumes() + folders.compactMap { AppModel.folderVolume($0) }
            await self?.apply(list, generation: gen)
        }
    }

    private func apply(_ list: [Volume], generation gen: Int) {
        // A refresh that started before a folder was added or removed would undo that change.
        guard gen == generation else { return }
        if list != volumes { volumes = list }
        for v in list {
            if let s = sessions[v.id] {
                if s.volume != v { s.volume = v }
            } else {
                sessions[v.id] = makeSession(v)
            }
        }
        // Forget drives that were unplugged (unless a scan is still unwinding).
        for (id, s) in sessions where !list.contains(where: { $0.id == id }) {
            s.cancel()
            sessions[id] = nil
        }
        if selectedID == nil || sessions[selectedID ?? ""] == nil {
            selectedID = list.first?.id
        }
    }

    private func makeSession(_ v: Volume) -> ScanSession {
        let s = ScanSession(volume: v)
        s.onResultChanged = { [weak self, weak s] in
            guard let self, let s else { return }
            self.rebalancePool(of: s.volume)
        }
        return s
    }

    /// Recomputes the "what else is on this server" entries for every scanned share on one pool.
    private func rebalancePool(of volume: Volume) {
        guard let key = volume.poolKey else { return }
        let group = sessions.values.filter { $0.volume.poolKey == key }
        for s in group where s.result != nil && !s.isScanning {
            let siblings = group.compactMap { other -> (id: String, name: String, bytes: Int64)? in
                guard other !== s, let bytes = other.ownScannedBytes else { return nil }
                return (other.volume.id, other.volume.name, bytes)
            }
            s.applyServerGap(siblings: siblings)
        }
    }

    /// Names of shares on the same server and pool that have not been scanned yet.
    func unscannedSiblings(of volume: Volume) -> [String] {
        guard let key = volume.poolKey else { return [] }
        return sessions.values
            .filter { $0.volume.poolKey == key && $0.volume.id != volume.id && $0.result == nil }
            .map { $0.volume.name }.sorted()
    }

    // MARK: search

    /// Every drive that has a map, newest scans included as they are.
    func scannedRoots() -> [TreeRoot] {
        sessions.values.compactMap { s -> TreeRoot? in
            guard let r = s.result else { return nil }
            return TreeRoot(id: s.volume.id, name: s.volume.name, root: r.root, date: r.date, fromCache: r.fromCache)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var unscannedNames: [String] {
        sessions.values.filter { $0.result == nil }.map { $0.volume.name }.sorted()
    }

    func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        searchToken += 1
        guard !q.isEmpty else {
            searchResults = []; searchTotal = 0; searchedFor = ""; searchBusy = false
            return
        }
        let token = searchToken
        let roots = scannedRoots()
        let kind = searchKind
        let progress = WorkProgress()
        searchBusy = true
        searchProgress = 0
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            let f = progress.fraction
            Task { @MainActor in
                guard let self, self.searchToken == token, self.searchBusy else { return }
                self.searchProgress = f
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let out = TreeSearch.run(query: q, roots: roots, kind: kind, progress: progress)
            Task { @MainActor in self?.finishSearch(out, query: q, token: token) }
        }
    }

    private func finishSearch(_ out: SearchOutcome, query: String, token: Int) {
        guard token == searchToken else { return }      // a newer search replaced this one
        searchResults = out.hits
        searchTotal = out.total
        searchedFor = query
        searchBusy = false
        searchProgress = 1
        searchTimer?.invalidate()
        searchTimer = nil
    }

    func clearSearch() {
        searchText = ""
        runSearch()
        if pane == .search { pane = .drive }
    }

    /// Jump to a folder on its drive's map.
    func showOnMap(volumeID: String, folderPath: String) {
        guard let s = sessions[volumeID] else { return }
        selectedID = volumeID
        pane = .drive
        s.show(path: folderPath)
    }

    // MARK: duplicates

    /// Roots the duplicate check will use for the current scope.
    func duplicateRoots() -> [TreeRoot] {
        let all = scannedRoots()
        guard let scope = dupScope else { return all }
        return all.filter { $0.id == scope }
    }

    var dupScopeName: String {
        guard let scope = dupScope else { return "All drives" }
        return sessions[scope]?.volume.name ?? "This drive"
    }

    /// Changing where to look throws away results from the previous scope.
    func setDupScope(_ id: String?) {
        guard dupPhase != .running, id != dupScope else { return }
        dupScope = id
        dupGroups = []
        dupPhase = .idle
    }

    /// From a drive's header: look for duplicates within that one drive.
    func openDuplicates(for volumeID: String) {
        pane = .duplicates
        guard dupPhase != .running else { return }
        setDupScope(volumeID)
        let mb = UserDefaults.standard.object(forKey: "dupMinMB") as? Int ?? 10
        findDuplicates(minSize: Int64(mb) * 1_000_000)
    }

    func findDuplicates(minSize: Int64) {
        guard dupPhase != .running else { return }
        let roots = duplicateRoots()
        let scan = DuplicateScan()
        dupScan = scan
        dupGroups = []
        dupProgress = DupProgress()
        dupPhase = .running
        dupTimer?.invalidate()
        dupTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            let p = scan.snapshot()
            Task { @MainActor in self?.dupProgress = p }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let groups = DuplicateFinder.run(roots: roots, minSize: minSize, scan: scan)
            let cancelled = scan.isCancelled
            Task { @MainActor in self?.finishDuplicates(groups, cancelled: cancelled) }
        }
    }

    func cancelDuplicates() { dupScan?.cancel() }

    private func finishDuplicates(_ groups: [DupGroup], cancelled: Bool) {
        dupTimer?.invalidate()
        dupTimer = nil
        dupScan = nil
        dupGroups = cancelled ? [] : groups
        dupPhase = cancelled ? .idle : .done
    }

    // MARK: verification (full read, one job at a time so a network share isn't flooded)

    private func startVerify(key: String, groupIDs: [Int]) {
        guard verifyFractions[key] == nil else { return }
        var items: [VerifyJob.Item] = []
        var bytes: Int64 = 0
        for gid in groupIDs {
            guard let g = dupGroup(gid), g.state == .sampled || g.state == .unreadable,
                  !dupVerifying.contains(gid) else { continue }
            items.append(VerifyJob.Item(groupID: gid, paths: g.items.map(\.path)))
            bytes += g.size * Int64(g.items.count)
            dupVerifying.insert(gid)
        }
        guard !items.isEmpty else { return }
        let job = VerifyJob(key: key, items: items, totalBytes: bytes)
        verifyJobs.append(job)
        verifyFractions[key] = 0
        if verifyTimer == nil {
            verifyTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollVerify() }
            }
        }
        verifyQueue.async { [weak self] in
            for item in job.items {
                if job.isCancelled { break }
                let same = DuplicateFinder.identical(item.paths, job: job)
                let stopped = job.isCancelled
                Task { @MainActor in self?.finishVerify(item.groupID, same, stopped: stopped) }
            }
            Task { @MainActor in self?.finishJob(job) }
        }
    }

    private func pollVerify() {
        var done: Int64 = 0, total: Int64 = 0
        for job in verifyJobs {
            verifyFractions[job.key] = job.progress.fraction
            let c = job.progress.counts
            done += c.done
            total += c.total
        }
        verifyOverall = total > 0 ? Double(done) / Double(total) : 0
    }

    private func finishVerify(_ id: Int, _ same: Bool?, stopped: Bool) {
        dupVerifying.remove(id)
        guard !stopped, let i = dupGroups.firstIndex(where: { $0.id == id }) else { return }
        switch same {
        case .some(true): dupGroups[i].state = .identical
        case .some(false): dupGroups[i].state = .different
        case .none: dupGroups[i].state = .unreadable
        }
    }

    private func finishJob(_ job: VerifyJob) {
        for item in job.items { dupVerifying.remove(item.groupID) }
        verifyJobs.removeAll { $0 === job }
        verifyFractions[job.key] = nil
        if verifyJobs.isEmpty {
            verifyTimer?.invalidate()
            verifyTimer = nil
            verifyOverall = 0
        }
    }

    /// Reads every copy in one set from start to end and compares them.
    func verifyGroup(_ id: Int) { startVerify(key: "group-\(id)", groupIDs: [id]) }

    /// Reads every copy in a folder match from start to end.
    func verifyMatch(_ match: FolderMatch) { startVerify(key: match.id, groupIDs: match.groupIDs) }

    func cancelVerify(_ key: String) {
        verifyJobs.first { $0.key == key }?.cancel()
    }

    var isVerifying: Bool { !verifyJobs.isEmpty }

    func dupGroup(_ id: Int) -> DupGroup? {
        // Group ids are their positions until a trash pass removes some; fall back to a search.
        if id < dupGroups.count, dupGroups[id].id == id { return dupGroups[id] }
        return dupGroups.first { $0.id == id }
    }

    /// Adds every copy that sits under one side of a folder match to the Collector, always
    /// leaving at least one copy of each file somewhere.
    func collectSide(_ match: FolderMatch, side: Int) {
        for gid in match.groupIDs {
            guard let g = dupGroup(gid), g.state != .different else { continue }
            var remaining = g.items.filter { !isCollected($0.node, in: $0.volumeID) }.count
            for item in g.items where match.side[item.id] == side && remaining > 1 {
                guard let session = sessions[item.volumeID], !session.isCollected(item.node) else { continue }
                session.toggleCollect(item.node)
                if session.isCollected(item.node) { remaining -= 1 }
            }
        }
        objectWillChange.send()
    }

    /// How many copies under one side of a match are in the Collector.
    func sideCollected(_ match: FolderMatch, side: Int) -> (collected: Int, total: Int) {
        var collected = 0, total = 0
        for gid in match.groupIDs {
            guard let g = dupGroup(gid) else { continue }
            for item in g.items where match.side[item.id] == side {
                total += 1
                if isCollected(item.node, in: item.volumeID) { collected += 1 }
            }
        }
        return (collected, total)
    }

    // MARK: collector, across drives

    func isCollected(_ node: FileNode, in volumeID: String) -> Bool {
        sessions[volumeID]?.isCollected(node) ?? false
    }

    func toggleCollect(_ node: FileNode, in volumeID: String) {
        sessions[volumeID]?.toggleCollect(node)
        objectWillChange.send()
    }

    var collectedCount: Int { sessions.values.reduce(0) { $0 + $1.collected.count } }
    var collectedBytes: Int64 { sessions.values.reduce(Int64(0)) { $0 + $1.collectedBytes } }

    func clearAllCollected() {
        for s in sessions.values { s.clearCollected() }
        objectWillChange.send()
    }

    /// Moves every collected item on every drive to the Trash, then drops what's gone from the lists.
    func trashAllCollected() {
        var errors: [String] = []
        for s in sessions.values where !s.collected.isEmpty {
            s.trashCollected()
            if let e = s.trashError { errors.append(e); s.trashError = nil }
        }
        let fm = FileManager.default
        dupGroups = dupGroups.compactMap { g in
            var g = g
            g.items.removeAll { !fm.fileExists(atPath: $0.path) }
            return g.items.count > 1 ? g : nil
        }
        searchResults.removeAll { !fm.fileExists(atPath: $0.node.path) }
        if !errors.isEmpty { toolError = errors.joined(separator: "\n") }
    }

    func addFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        if let existing = volumes.first(where: { $0.path == path }) {
            selectedID = existing.id
            return
        }
        var paths = folderPaths
        if !paths.contains(path) { paths.append(path) }
        folderPaths = paths
        generation += 1
        if let v = AppModel.folderVolume(path) {
            volumes.append(v)
            let s = makeSession(v)
            sessions[v.id] = s
            selectedID = v.id
            s.start()
        }
    }

    func removeFolder(_ v: Volume) {
        guard v.kind == .folder else { return }
        folderPaths = folderPaths.filter { $0 != v.path }
        generation += 1
        ScanStore.remove(for: v)
        refresh()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Scan"
        panel.message = "Choose a folder to map"
        if panel.runModal() == .OK, let url = panel.url { addFolder(url) }
    }

    // MARK: volume discovery (off the main thread: a sleeping NAS can stall statfs)

    nonisolated private static func folderVolume(_ path: String) -> Volume? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let name = FileManager.default.displayName(atPath: path)
        return Volume(name: name, path: path, kind: .folder)
    }

    /// "//user@nas.local/Media" or "nas.local:/volume1/Media" → "nas.local"
    nonisolated private static func serverHost(for path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let from: String = withUnsafePointer(to: &fs.f_mntfromname) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tuple.pointee)) {
                String(cString: $0)
            }
        }
        var host: Substring
        if from.hasPrefix("//") {
            host = from.dropFirst(2).prefix { $0 != "/" }
            if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        } else if let colon = from.range(of: ":/") {
            host = from[..<colon.lowerBound]
        } else {
            return nil
        }
        return host.isEmpty ? nil : host.lowercased()
    }

    nonisolated private static func readVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeUUIDStringKey, .volumeLocalizedFormatDescriptionKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                          options: [.skipHiddenVolumes]) ?? []
        var out: [Volume] = []
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.volumeIsBrowsable == false { continue }
            let total = Int64(rv.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            let realFree = Int64(rv.volumeAvailableCapacity ?? 0)
            let important = rv.volumeAvailableCapacityForImportantUsage ?? 0
            let path = url.path
            let kind: Volume.Kind
            if path == "/" { kind = .boot }
            else if rv.volumeIsLocal == false { kind = .network }
            else if rv.volumeIsInternal == true { kind = .internalDrive }
            else { kind = .external }
            let server = kind == .network ? serverHost(for: path) : nil
            out.append(Volume(name: rv.volumeName ?? url.lastPathComponent, path: path, kind: kind,
                              total: total, free: max(realFree, important), realFree: realFree,
                              format: rv.volumeLocalizedFormatDescription ?? "", uuid: rv.volumeUUIDString, server: server))
        }
        return out.sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
    }
}

// MARK: - Finder shortcuts

enum Finder {
    static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Folders open in a Finder window; files are revealed in their folder.
    static func show(_ node: FileNode) {
        if node.kind == .file { reveal(node.path) } else { open(node.path) }
    }

    static func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    static func quickLook(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func openTerminal(_ path: String) {
        let term = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: term,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
