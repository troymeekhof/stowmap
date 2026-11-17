import Foundation
import CryptoKit

// Search and duplicate matching across every scanned drive. Both work from the maps the scanner
// already built; only the duplicate check reads file contents, and only small samples of them.

/// One scanned drive's tree, handed to background work.
struct TreeRoot: @unchecked Sendable {
    let id: String          // volume id
    let name: String
    let root: FileNode
    let date: Date
    let fromCache: Bool
}

/// How far a background pass has got, measured in bytes of the maps it has walked.
final class WorkProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64 = 0
    private var total: Int64 = 1

    func start(total: Int64) { lock.lock(); self.total = max(1, total); done = 0; lock.unlock() }
    func add(_ bytes: Int64) { lock.lock(); done += bytes; lock.unlock() }
    var fraction: Double {
        lock.lock(); defer { lock.unlock() }
        return min(1, Double(done) / Double(total))
    }
}

// MARK: - Search

struct SearchHit: Identifiable, @unchecked Sendable {
    let node: FileNode
    let volumeID: String
    let volumeName: String
    var id: ObjectIdentifier { ObjectIdentifier(node) }
}

struct SearchOutcome: @unchecked Sendable {
    var hits: [SearchHit]
    var total: Int
}

enum TreeSearch {
    /// Every word in the query must appear in the name (any order, case and accents ignored).
    /// Returns the largest matches first. kind: 0 all, 1 folders, 2 files.
    static func run(query: String, roots: [TreeRoot], kind: Int, limit: Int = 400,
                    progress: WorkProgress? = nil) -> SearchOutcome {
        let terms = query.split(whereSeparator: { $0 == " " }).map(String.init)
        guard !terms.isEmpty else { return SearchOutcome(hits: [], total: 0) }
        var hits: [SearchHit] = []
        var total = 0
        progress?.start(total: roots.reduce(Int64(0)) { $0 + $1.root.size })
        var walked: Int64 = 0
        var sinceReport = 0
        for r in roots {
            var stack: [FileNode] = [r.root]
            while let n = stack.popLast() {
                for c in n.children {
                    // Everything that isn't a folder is a leaf; its bytes count as ground covered.
                    if c.kind != .folder {
                        walked += c.size
                        sinceReport += 1
                        if sinceReport >= 4000 { progress?.add(walked); walked = 0; sinceReport = 0 }
                    }
                    if c.kind == .folder { stack.append(c) } else if c.kind != .file { continue }
                    if kind == 1 && c.kind != .folder { continue }
                    if kind == 2 && c.kind != .file { continue }
                    var match = true
                    for t in terms where c.name.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                        match = false
                        break
                    }
                    guard match else { continue }
                    total += 1
                    hits.append(SearchHit(node: c, volumeID: r.id, volumeName: r.name))
                    if hits.count > limit * 8 {
                        hits.sort { $0.node.size > $1.node.size }
                        hits.removeLast(hits.count - limit)
                    }
                }
            }
        }
        progress?.add(walked)
        hits.sort { $0.node.size > $1.node.size }
        if hits.count > limit { hits.removeLast(hits.count - limit) }
        return SearchOutcome(hits: hits, total: total)
    }
}

// MARK: - Duplicates

struct DupItem: Identifiable, @unchecked Sendable {
    let node: FileNode
    let volumeID: String
    let volumeName: String
    let path: String
    var id: ObjectIdentifier { ObjectIdentifier(node) }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

struct DupGroup: Identifiable, @unchecked Sendable {
    enum State { case sampled, identical, different, unreadable }
    let id: Int
    let size: Int64                 // length of each copy, in bytes
    var items: [DupItem]
    var state: State = .sampled
    var wasted: Int64 { size * Int64(max(0, items.count - 1)) }
    var driveCount: Int { Set(items.map(\.volumeID)).count }
}

struct DupProgress {
    var stage = ""
    var checked = 0
    var total = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0

    /// Step one (walking the maps) is the first fifth of the bar; comparing samples is the rest.
    var fraction: Double {
        if total > 0 { return 0.2 + 0.8 * Double(checked) / Double(total) }
        if bytesTotal > 0 { return 0.2 * min(1, Double(bytesDone) / Double(bytesTotal)) }
        return 0
    }
}

final class DuplicateScan: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = DupProgress()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func snapshot() -> DupProgress { lock.lock(); defer { lock.unlock() }; return progress }
    func set(stage: String, total: Int = 0) {
        lock.lock(); progress.stage = stage; progress.total = total; progress.checked = 0; lock.unlock()
    }
    func tick() { lock.lock(); progress.checked += 1; lock.unlock() }
    func walk(total: Int64) { lock.lock(); progress.bytesTotal = max(1, total); progress.bytesDone = 0; lock.unlock() }
    func walked(_ bytes: Int64) { lock.lock(); progress.bytesDone += bytes; lock.unlock() }
}

enum DuplicateFinder {
    private struct Candidate {
        let node: FileNode
        let root: Int
        let length: Int64
    }

    private struct Fingerprint {
        let digest: Data
        let dev: Int32
        let ino: UInt64
    }

    private struct Key: Hashable {
        let length: Int64
        let digest: Data
    }

    /// Blocking. Three narrowing steps: same length → same samples (start, middle, end) → grouped.
    /// A group is "sampled" until `identical(_:)` reads the copies in full.
    static func run(roots: [TreeRoot], minSize: Int64, scan: DuplicateScan) -> [DupGroup] {
        // 1. Same length. Uses what the scan recorded; nothing is read from disk for most files.
        scan.set(stage: "Looking for files of the same size")
        scan.walk(total: roots.reduce(Int64(0)) { $0 + $1.root.size })
        var byLength: [Int64: [Candidate]] = [:]
        for (i, r) in roots.enumerated() {
            var stack: [FileNode] = [r.root]
            while let n = stack.popLast() {
                if scan.isCancelled { return [] }
                var leafBytes: Int64 = 0
                for c in n.children where c.kind != .folder { leafBytes += c.size }
                if leafBytes > 0 { scan.walked(leafBytes) }
                for c in n.children {
                    if c.kind == .folder {
                        stack.append(c)
                    } else if c.kind == .file {
                        var length = c.logical
                        if length == 0 {
                            // Maps saved by an older version didn't record lengths; ask the disk.
                            guard c.size >= minSize / 2 else { continue }
                            length = statLength(c.path)
                        }
                        guard length >= minSize else { continue }
                        byLength[length, default: []].append(Candidate(node: c, root: i, length: length))
                    }
                }
            }
        }
        let candidates = byLength.values.filter { $0.count > 1 }.flatMap { $0 }
        if candidates.isEmpty { return [] }

        // 2. Same samples. Reads at most 192 KB per file, so a 40 GB clip costs the same as a small one.
        scan.set(stage: "Comparing samples", total: candidates.count)
        let paths = candidates.map { $0.node.path }
        var prints = [Fingerprint?](repeating: nil, count: candidates.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            if scan.isCancelled { return }
            let fp = fingerprint(path: paths[i], length: candidates[i].length)
            lock.lock()
            prints[i] = fp
            lock.unlock()
            scan.tick()
        }
        if scan.isCancelled { return [] }

        // 3. Group. The same file reached twice (hard links) is one copy, not two.
        var buckets: [Key: [Int]] = [:]
        for i in candidates.indices {
            guard let fp = prints[i] else { continue }
            buckets[Key(length: candidates[i].length, digest: fp.digest), default: []].append(i)
        }
        var groups: [DupGroup] = []
        for (key, members) in buckets where members.count > 1 {
            var seen = Set<FileID>()
            var items: [DupItem] = []
            for i in members {
                guard let fp = prints[i], seen.insert(FileID(dev: fp.dev, ino: fp.ino)).inserted else { continue }
                let r = roots[candidates[i].root]
                items.append(DupItem(node: candidates[i].node, volumeID: r.id, volumeName: r.name, path: paths[i]))
            }
            guard items.count > 1 else { continue }
            items.sort { ($0.volumeName, $0.path) < ($1.volumeName, $1.path) }
            groups.append(DupGroup(id: 0, size: key.length, items: items))
        }
        groups.sort { $0.wasted > $1.wasted }
        if groups.count > 1000 { groups.removeLast(groups.count - 1000) }
        return groups.enumerated().map { i, g in DupGroup(id: i, size: g.size, items: g.items) }
    }

    private static func statLength(_ path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return 0 }
        return Int64(st.st_size)
    }

    /// Hash of the first, middle and last 64 KB plus the length. nil when the file can't be compared:
    /// gone, changed size since the scan, unreadable, or an iCloud placeholder (reading it would
    /// trigger a download).
    private static func fingerprint(path: String, length: Int64) -> Fingerprint? {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) == length else { return nil }
        if st.st_flags & 0x4000_0000 != 0 { return nil }       // SF_DATALESS
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)

        let chunk = 64 * 1024
        let sampled = length > Int64(chunk) * 3
        let want = sampled ? chunk : Int(length)
        let offsets: [Int64] = sampled ? [0, (length - Int64(chunk)) / 2, length - Int64(chunk)] : [0]
        var hasher = SHA256()
        var buf = [UInt8](repeating: 0, count: want)
        for off in offsets {
            var got = 0
            while got < want {
                let n = buf.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return pread(fd, base + got, want - got, off + Int64(got))
                }
                if n <= 0 { return nil }
                got += n
            }
            hasher.update(data: buf)
        }
        withUnsafeBytes(of: length) { hasher.update(bufferPointer: $0) }
        return Fingerprint(digest: Data(hasher.finalize()), dev: st.st_dev, ino: st.st_ino)
    }

    private static func fullHash(_ path: String) -> Data? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        var buf = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let n = buf.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(fd, base, raw.count)
            }
            if n < 0 { return nil }
            if n == 0 { break }
            hasher.update(data: buf[0..<n])
        }
        return Data(hasher.finalize())
    }

    /// Reads every file from start to end. true = byte-for-byte identical, false = at least one
    /// differs, nil = one couldn't be read.
    static func identical(_ paths: [String]) -> Bool? {
        var first: Data?
        for p in paths {
            guard let h = fullHash(p) else { return nil }
            if let f = first {
                if f != h { return false }
            } else {
                first = h
            }
        }
        return true
    }
}
