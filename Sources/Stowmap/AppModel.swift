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
                          ch: kids.isEmpty ? nil : kids)
    }

    private static func unpack(_ c: CachedNode) -> FileNode {
        let node = FileNode(name: c.n, kind: FileNode.Kind(rawValue: c.k) ?? .file, isHidden: c.h,
                            size: c.s, fileCount: c.c)
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
        addHiddenSpace(to: r.root)
        result = r
        focus = r.root
        phase = .done
        revision += 1
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
        // On a network share the server reports the whole storage pool, so the gap is mostly
        // other shares, plus the server's snapshots and recycle bins.
        let label = volume.kind == .network ? "Elsewhere on this server" : "Hidden space"
        let node = FileNode(name: label, kind: .hiddenSpace, size: gap)
        node.parent = root
        root.children.append(node)
        root.children.sort { $0.size > $1.size }
        root.size += gap
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
                sessions[v.id] = ScanSession(volume: v)
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
            let s = ScanSession(volume: v)
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
            out.append(Volume(name: rv.volumeName ?? url.lastPathComponent, path: path, kind: kind,
                              total: total, free: max(realFree, important), realFree: realFree,
                              format: rv.volumeLocalizedFormatDescription ?? "", uuid: rv.volumeUUIDString))
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
