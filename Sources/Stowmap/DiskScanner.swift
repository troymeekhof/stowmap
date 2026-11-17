import Foundation

// Fast parallel directory walker: readdir + fstatat (no Foundation enumerator), allocated sizes,
// hard links counted once, never leaves the volume being scanned.

struct FileID: Hashable {
    let dev: Int32
    let ino: UInt64
}

struct ScanProgress {
    var files = 0
    var bytes: Int64 = 0
    var denied = 0
    var path = ""
}

struct TypeAcc {
    var count = 0
    var bytes: Int64 = 0
}

/// Per-worker accumulator, merged into the context when the worker finishes (no lock per file).
struct LocalStats {
    var types: [String: TypeAcc] = [:]
    var largest: [LargeFile] = []
    var floor: Int64 = 1_000_000

    mutating func add(name: String, size: Int64) {
        let e = FileTypes.ext(of: name)
        var acc = types[e] ?? TypeAcc()
        acc.count += 1
        acc.bytes += size
        types[e] = acc
    }

    mutating func offer(path: String, size: Int64) {
        largest.append(LargeFile(path: path, size: size))
        if largest.count > 600 { trim() }
    }

    mutating func trim() {
        largest.sort { $0.size > $1.size }
        if largest.count > DiskScanner.largestKept {
            largest.removeLast(largest.count - DiskScanner.largestKept)
            floor = max(floor, largest.last?.size ?? floor)
        }
    }
}

final class ScanContext: @unchecked Sendable {
    // Configuration (immutable after init)
    let allowedDevs: Set<Int32>
    let isBoot: Bool
    let logicalSizes: Bool        // network shares often report 0 allocated blocks
    let smallThreshold: Int64     // files below this are rolled up per folder
    let parallelDepth: Int        // folders above this depth get their own worker

    private let lock = NSLock()
    private let queue = OperationQueue()
    private let group = DispatchGroup()

    private var visited = Set<FileID>()     // directories (firmlinks show the same folder twice)
    private var links = Set<FileID>()       // hard-linked files already counted
    private var progress = ScanProgress()
    private var cancelled = false
    private var types: [String: TypeAcc] = [:]
    private var largest: [LargeFile] = []
    private var deferred: [(FileNode, String)] = []

    init(allowedDevs: Set<Int32>, isBoot: Bool, isNetwork: Bool) {
        self.allowedDevs = allowedDevs
        self.isBoot = isBoot
        self.logicalSizes = isNetwork
        self.smallThreshold = 128 * 1024
        self.parallelDepth = 4
        queue.maxConcurrentOperationCount = isNetwork ? 4 : max(4, min(12, ProcessInfo.processInfo.activeProcessorCount))
        queue.qualityOfService = .userInitiated
    }

    // MARK: thread-safe state

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func snapshot() -> ScanProgress { lock.lock(); defer { lock.unlock() }; return progress }

    /// True the first time a directory is seen.
    func visit(_ id: FileID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return visited.insert(id).inserted
    }

    private func firstLink(_ id: FileID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return links.insert(id).inserted
    }

    private func report(files: Int, bytes: Int64, path: String) {
        lock.lock()
        progress.files += files
        progress.bytes += bytes
        progress.path = path
        lock.unlock()
    }

    private func noteDenied() { lock.lock(); progress.denied += 1; lock.unlock() }

    private func merge(_ local: LocalStats) {
        lock.lock()
        for (k, v) in local.types {
            var acc = types[k] ?? TypeAcc()
            acc.count += v.count
            acc.bytes += v.bytes
            types[k] = acc
        }
        largest.append(contentsOf: local.largest)
        if largest.count > 4000 {
            largest.sort { $0.size > $1.size }
            largest.removeLast(largest.count - DiskScanner.largestKept)
        }
        lock.unlock()
    }

    func results() -> (types: [TypeStat], largest: [LargeFile], denied: Int) {
        lock.lock(); defer { lock.unlock() }
        let t = types.map { TypeStat(ext: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            .sorted { $0.bytes > $1.bytes }
        let l = Array(largest.sorted { $0.size > $1.size }.prefix(DiskScanner.largestKept))
        return (t, l, progress.denied)
    }

    // MARK: walking

    func spawn(_ node: FileNode, _ path: String, depth: Int) {
        group.enter()
        queue.addOperation { [self] in
            var local = LocalStats()
            scanDir(path, node, depth: depth, local: &local)
            merge(local)
            group.leave()
        }
    }

    func wait() { group.wait() }

    func takeDeferred() -> [(FileNode, String)] {
        lock.lock(); defer { lock.unlock() }
        let d = deferred
        deferred = []
        return d
    }

    private func scanDir(_ path: String, _ node: FileNode, depth: Int, local: inout LocalStats) {
        if isCancelled { return }
        guard let dir = opendir(path) else {
            if errno == EACCES || errno == EPERM {
                node.unreadable = true
                noteDenied()
            }
            return
        }
        let fd = dirfd(dir)
        let prefix = path.hasSuffix("/") ? path : path + "/"

        var subdirs: [(FileNode, String)] = []
        var smallBytes: Int64 = 0
        var smallCount = 0
        var fileCount = 0
        var fileBytes: Int64 = 0

        while let ent = readdir(dir) {
            let name: String = withUnsafePointer(to: &ent.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tuple.pointee)) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }

            var st = stat()
            if fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }
            let type = st.st_mode & S_IFMT
            let hidden = name.hasPrefix(".") || (st.st_flags & UInt32(UF_HIDDEN)) != 0

            if type == S_IFDIR {
                // Stay on this volume; skip folders already reached through another route.
                guard allowedDevs.contains(st.st_dev) else { continue }
                guard visit(FileID(dev: st.st_dev, ino: st.st_ino)) else { continue }
                let child = FileNode(name: name, kind: .folder, isHidden: hidden)
                child.parent = node
                node.children.append(child)
                subdirs.append((child, prefix + name))
            } else {
                var size = Int64(st.st_blocks) * 512
                if logicalSizes && size == 0 { size = Int64(st.st_size) }
                if type == S_IFREG && st.st_nlink > 1 && !firstLink(FileID(dev: st.st_dev, ino: st.st_ino)) {
                    size = 0
                }
                fileCount += 1
                fileBytes += size
                local.add(name: name, size: size)
                if size >= local.floor { local.offer(path: prefix + name, size: size) }
                if size >= smallThreshold {
                    let child = FileNode(name: name, kind: .file, isHidden: hidden, size: size, fileCount: 1)
                    child.parent = node
                    node.children.append(child)
                } else {
                    smallBytes += size
                    smallCount += 1
                }
            }
        }
        closedir(dir)

        if smallCount > 0 {
            let label = smallCount == 1 ? "1 small file" : "\(Fmt.count(smallCount)) small files"
            let roll = FileNode(name: label, kind: .smallFiles, size: smallBytes, fileCount: smallCount)
            roll.parent = node
            node.children.append(roll)
        }
        report(files: fileCount, bytes: fileBytes, path: path)

        for (child, childPath) in subdirs {
            // On the startup disk, /System/Volumes holds the Data volume, whose folders also appear
            // at "/" through firmlinks. Walk it last so shared folders are counted where users expect.
            if isBoot && childPath == "/System/Volumes" {
                lock.lock(); deferred.append((child, childPath)); lock.unlock()
            } else if depth < parallelDepth {
                spawn(child, childPath, depth: depth + 1)
            } else {
                scanDir(childPath, child, depth: depth + 1, local: &local)
            }
        }
    }
}

enum DiskScanner {
    static let largestKept = 250

    static func makeContext(for volume: Volume) -> ScanContext {
        var devs = Set<Int32>()
        var st = stat()
        if lstat(volume.path, &st) == 0 { devs.insert(st.st_dev) }
        if volume.kind == .boot {
            // The APFS container's sibling volumes (Data, VM, Preboot, …) are part of "Macintosh HD".
            let base = "/System/Volumes"
            for name in (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [] {
                var s = stat()
                if lstat(base + "/" + name, &s) == 0, (s.st_mode & S_IFMT) == S_IFDIR { devs.insert(s.st_dev) }
            }
        }
        return ScanContext(allowedDevs: devs, isBoot: volume.kind == .boot, isNetwork: volume.kind == .network)
    }

    /// Blocking. Call from a background thread.
    static func run(volume: Volume, ctx: ScanContext) -> ScanResult {
        let started = Date()
        let root = FileNode(name: volume.name, kind: .folder)
        root.rootPath = volume.path

        var st = stat()
        if lstat(volume.path, &st) == 0 { _ = ctx.visit(FileID(dev: st.st_dev, ino: st.st_ino)) }

        ctx.spawn(root, volume.path, depth: 0)
        ctx.wait()
        for (node, path) in ctx.takeDeferred() { ctx.spawn(node, path, depth: 2) }
        ctx.wait()

        finalize(root)
        let r = ctx.results()
        return ScanResult(root: root, types: r.types, largest: r.largest, date: Date(),
                          duration: Date().timeIntervalSince(started), denied: r.denied)
    }

    /// Bottom-up totals, largest first, empty entries dropped. Iterative: trees can be very deep.
    static func finalize(_ root: FileNode) {
        var order: [FileNode] = []
        var stack: [FileNode] = [root]
        while let n = stack.popLast() {
            guard n.kind == .folder else { continue }
            order.append(n)
            stack.append(contentsOf: n.children)
        }
        for n in order.reversed() {
            n.children.removeAll { $0.size == 0 && !$0.unreadable }
            var size: Int64 = 0
            var count = 0
            for c in n.children { size += c.size; count += c.fileCount }
            n.size = size
            n.fileCount = count
            n.children.sort { $0.size > $1.size }
        }
    }
}
