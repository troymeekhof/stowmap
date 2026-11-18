import Foundation

// Copy & Verify: copies files to one or more destinations and proves each copy with a checksum.
//
// Rules the engine keeps:
//  - The source is only ever opened for reading.
//  - Every file is written as "<name>.stowmap-partial" and renamed only after all of it is on disk.
//  - An existing file is never replaced unless the policy says Replace.
//  - Verification re-reads what was written from the disk (not the cache) and compares checksums.

enum VerifyMode: String, CaseIterable, Identifiable, Sendable {
    case destination, both, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .destination: return "Destination"
        case .both: return "Source and destination"
        case .off: return "Off"
        }
    }
}

enum ConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case skip, replace, keepBoth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .skip: return "Skip"
        case .replace: return "Replace"
        case .keepBoth: return "Keep both"
        }
    }
}

struct TransferOptions: Sendable {
    var hash: HashKind = .xxh64
    var verify: VerifyMode = .destination
    var conflict: ConflictPolicy = .skip
    var includeHidden = true
    var skipClutter = true          // .DS_Store, ._ files, Spotlight and Trash folders
    var writeLists = true           // MHL + plain checksum list in each destination
    var corruptForTest: String?     // self-test only: damage this file after copying, before verifying
}

struct PlanEntry: Sendable {
    enum Kind: Sendable { case folder, file, symlink }
    let source: String              // absolute path
    let rel: String                 // path under the destination root
    let kind: Kind
    let size: Int64
    let modified: Date
}

struct TransferPlan: Sendable {
    var entries: [PlanEntry] = []
    var fileCount = 0
    var totalBytes: Int64 = 0
    var unreadable: [String] = []
}

enum TransferPlanner {
    private static let clutter: Set<String> = [".DS_Store", ".Spotlight-V100", ".fseventsd", ".Trashes",
                                               ".TemporaryItems", ".DocumentRevisions-V100", ".apdisk",
                                               ".stowmap-partial"]

    static func skips(_ name: String, _ o: TransferOptions) -> Bool {
        if name.hasSuffix(".stowmap-partial") { return true }
        if o.skipClutter && (clutter.contains(name) || name.hasPrefix("._")) { return true }
        if !o.includeHidden && name.hasPrefix(".") { return true }
        return false
    }

    /// Everything under the given files and folders. A folder "A" lands as "A/…" in the destination.
    /// `found` is called (from background threads) with the number of files discovered so far.
    static func build(sources: [String], options: TransferOptions, keepGoing: @escaping () -> Bool = { true },
                      found: @escaping (Int) -> Void = { _ in }) -> TransferPlan {
        var plan = TransferPlan()
        var starts: [(String, String)] = []
        for src in sources {
            let name = (src as NSString).lastPathComponent
            starts.append((src, name.isEmpty ? "Volume" : name))
        }
        walk(starts, options: options, into: &plan, keepGoing: keepGoing, found: found)
        return plan
    }

    /// The contents of one folder, with paths relative to that folder (used to compare two folders).
    static func contents(of root: String, options: TransferOptions, keepGoing: @escaping () -> Bool = { true },
                         found: @escaping (Int) -> Void = { _ in }) -> TransferPlan {
        var plan = TransferPlan()
        guard let top = list(root) else {
            plan.unreadable.append(root)
            return plan
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        var folders: [(String, String)] = []
        add(top, under: prefix, rel: "", options: options, into: &plan, folders: &folders)
        found(plan.fileCount)
        walkFolders(folders, options: options, into: &plan, keepGoing: keepGoing, found: found)
        plan.entries.sort { $0.rel < $1.rel }
        return plan
    }

    /// One folder's items. Asks for names, kinds, sizes and dates in a single request where the
    /// volume supports it (one round trip per folder on a network share, not one per file).
    private static func list(_ path: String) -> [DirEntry]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        if let fast = DirLister.bulk(fd: fd) { return fast }
        rewinddir(dir)
        return DirLister.classic(dir: dir, fd: fd)
    }

    private static func add(_ items: [DirEntry], under prefix: String, rel: String, options: TransferOptions,
                            into plan: inout TransferPlan, folders: inout [(String, String)]) {
        for e in items where !skips(e.name, options) {
            let path = prefix + e.name
            let r = rel.isEmpty ? e.name : rel + "/" + e.name
            let modified = Date(timeIntervalSince1970: TimeInterval(e.modified))
            if e.isDirectory {
                plan.entries.append(PlanEntry(source: path, rel: r, kind: .folder, size: 0, modified: modified))
                folders.append((path, r))
            } else if e.isRegular {
                plan.entries.append(PlanEntry(source: path, rel: r, kind: .file, size: e.length, modified: modified))
                plan.fileCount += 1
                plan.totalBytes += e.length
            } else if e.isSymlink {
                plan.entries.append(PlanEntry(source: path, rel: r, kind: .symlink, size: 0, modified: modified))
            }
            // Sockets, devices and pipes are not files; they are left out.
        }
    }

    /// Starting points can be files or folders.
    private static func walk(_ starts: [(String, String)], options: TransferOptions, into plan: inout TransferPlan,
                             keepGoing: @escaping () -> Bool, found: @escaping (Int) -> Void) {
        var folders: [(String, String)] = []
        for (p, r) in starts {
            var st = stat()
            guard lstat(p, &st) == 0 else { plan.unreadable.append(p); continue }
            let type = st.st_mode & S_IFMT
            let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            if type == S_IFDIR {
                plan.entries.append(PlanEntry(source: p, rel: r, kind: .folder, size: 0, modified: modified))
                folders.append((p, r))
            } else if type == S_IFREG {
                plan.entries.append(PlanEntry(source: p, rel: r, kind: .file, size: Int64(st.st_size), modified: modified))
                plan.fileCount += 1
                plan.totalBytes += Int64(st.st_size)
            } else if type == S_IFLNK {
                plan.entries.append(PlanEntry(source: p, rel: r, kind: .symlink, size: 0, modified: modified))
            }
        }
        walkFolders(folders, options: options, into: &plan, keepGoing: keepGoing, found: found)
        plan.entries.sort { $0.rel < $1.rel }
    }

    /// Level by level, listing every folder of a level at the same time.
    private static func walkFolders(_ start: [(String, String)], options: TransferOptions, into plan: inout TransferPlan,
                                    keepGoing: @escaping () -> Bool, found: @escaping (Int) -> Void) {
        var frontier = start
        let lock = NSLock()
        while !frontier.isEmpty {
            if !keepGoing() { return }
            let level = frontier
            var results = [[DirEntry]?](repeating: nil, count: level.count)
            DispatchQueue.concurrentPerform(iterations: level.count) { i in
                if !keepGoing() { return }
                let items = list(level[i].0)
                lock.lock()
                results[i] = items
                lock.unlock()
            }
            var next: [(String, String)] = []
            for (i, items) in results.enumerated() {
                guard let items else { plan.unreadable.append(level[i].0); continue }
                let p = level[i].0
                add(items, under: p.hasSuffix("/") ? p : p + "/", rel: level[i].1, options: options,
                    into: &plan, folders: &next)
            }
            found(plan.fileCount)
            frontier = next
        }
    }
}

// MARK: - Results

enum FileState: Equatable, Sendable {
    case pending
    case copying
    case verifying
    case verified                 // written, re-read, checksums match
    case copied                   // written, verification was off
    case alreadyThere             // existed before; its checksum matches the source
    case existsDifferent          // existed before and is NOT the same; left untouched
    case mismatch                 // written, but what was read back doesn't match
    case failed(String)

    var isProblem: Bool {
        switch self {
        case .existsDifferent, .mismatch, .failed: return true
        default: return false
        }
    }
    var isGood: Bool { self == .verified || self == .copied || self == .alreadyThere }
}

struct FileResult: Identifiable, Sendable {
    let id: Int
    let rel: String
    let size: Int64
    var hash = ""
    var states: [FileState]          // one per destination

    var name: String { (rel as NSString).lastPathComponent }
    var worst: FileState {
        if let p = states.first(where: { $0.isProblem }) { return p }
        if let busy = states.first(where: { $0 == .copying || $0 == .verifying }) { return busy }
        if states.contains(.pending) { return .pending }
        if states.allSatisfy({ $0 == .alreadyThere }) { return .alreadyThere }
        if states.contains(.copied) { return .copied }
        return .verified
    }
}

struct TransferSnapshot: Sendable {
    enum Phase: Sendable { case preparing, running, finished, stopped }
    var phase: Phase = .preparing
    var paused = false
    var totalBytes: Int64 = 0
    var copiedBytes: Int64 = 0
    var verifyTotal: Int64 = 0
    var verifiedBytes: Int64 = 0
    var filesTotal = 0
    var filesDone = 0
    var activity = ""                 // "Copying" / "Verifying"
    var currentName = ""
    var currentSize: Int64 = 0
    var currentDone: Int64 = 0
    var destCopied: [Int64] = []
    var destVerified: [Int64] = []
    var destFilesVerified: [Int] = []
    var destDead: [String?] = []      // why a destination was dropped, if it was
    var recent: [FileResult] = []     // newest first
    var problems: [FileResult] = []
    var good = 0
    var alreadyThere = 0
    var readNanos: UInt64 = 0         // time spent reading the source
    var writeNanos: [UInt64] = []     // time spent writing, per destination
    var verifyNanos: [UInt64] = []
    var started = Date()
    var finished: Date?
    var listPaths: [String] = []      // checksum lists written at the end

    var fraction: Double {
        let total = totalBytes + verifyTotal
        guard total > 0 else { return phase == .finished ? 1 : 0 }
        return min(1, Double(copiedBytes + verifiedBytes) / Double(total))
    }
    var copyFraction: Double { totalBytes > 0 ? min(1, Double(copiedBytes) / Double(totalBytes)) : (phase == .finished ? 1 : 0) }
    var verifyFraction: Double { verifyTotal > 0 ? min(1, Double(verifiedBytes) / Double(verifyTotal)) : (phase == .finished ? 1 : 0) }
}

// MARK: - Engine

final class TransferEngine: @unchecked Sendable {
    let plan: TransferPlan
    let destinations: [String]
    let options: TransferOptions

    private let lock = NSCondition()
    private var snap = TransferSnapshot()
    private var paused = false
    private var cancelled = false
    private var destAlive: [Bool]
    private var manifest: [[(rel: String, size: Int64, hash: String, modified: Date)]]
    private var madeDirs = Set<String>()
    private let chunk = 4 << 20

    init(plan: TransferPlan, destinations: [String], options: TransferOptions) {
        self.plan = plan
        self.destinations = destinations
        self.options = options
        let n = destinations.count
        destAlive = Array(repeating: true, count: n)
        manifest = Array(repeating: [], count: n)
        snap.totalBytes = plan.totalBytes
        snap.filesTotal = plan.fileCount
        let passes: Int64 = options.verify == .off ? 0 : Int64(n) + (options.verify == .both ? 1 : 0)
        snap.verifyTotal = plan.totalBytes * passes
        snap.destCopied = Array(repeating: 0, count: n)
        snap.destVerified = Array(repeating: 0, count: n)
        snap.destFilesVerified = Array(repeating: 0, count: n)
        snap.destDead = Array(repeating: nil, count: n)
        snap.writeNanos = Array(repeating: 0, count: n)
        snap.verifyNanos = Array(repeating: 0, count: n)
    }

    // MARK: control

    func snapshot() -> TransferSnapshot { lock.lock(); defer { lock.unlock() }; return snap }
    func pause() { lock.lock(); paused = true; snap.paused = true; lock.unlock() }
    func resume() { lock.lock(); paused = false; snap.paused = false; lock.broadcast(); lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; paused = false; snap.paused = false; lock.broadcast(); lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Blocks while paused. Returns false once the job has been stopped.
    private func proceed() -> Bool {
        lock.lock()
        while paused && !cancelled { lock.wait() }
        let go = !cancelled
        lock.unlock()
        return go
    }

    private func update(_ body: (inout TransferSnapshot) -> Void) {
        lock.lock(); body(&snap); lock.unlock()
    }

    // MARK: run (blocking; call from a background thread)

    func run() {
        update { $0.phase = .running; $0.started = Date() }
        var folders: [PlanEntry] = []
        var index = 0
        for e in plan.entries {
            guard proceed() else { break }
            switch e.kind {
            case .folder:
                for (i, root) in destinations.enumerated() where destAlive[i] { makeDir(Self.join(root, e.rel), dest: i) }
                folders.append(e)
            case .symlink:
                copyLink(e)
            case .file:
                copyFile(e, id: index)
                index += 1
            }
        }
        let stopped = isCancelled
        if !stopped {
            // Folder dates and attributes last, deepest first, so writing files doesn't disturb them.
            for e in folders.reversed() {
                for (i, root) in destinations.enumerated() where destAlive[i] {
                    _ = copyfile(e.source, Self.join(root, e.rel), nil, copyfile_flags_t(COPYFILE_METADATA))
                }
            }
            if options.writeLists { writeLists() }
        }
        update {
            $0.phase = stopped ? .stopped : .finished
            $0.finished = Date()
            $0.activity = ""
            $0.currentName = ""
        }
    }

    static func join(_ root: String, _ rel: String) -> String {
        root.hasSuffix("/") ? root + rel : root + "/" + rel
    }

    private func makeDir(_ path: String, dest: Int) {
        if madeDirs.contains(path) { return }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            madeDirs.insert(path)
        } catch {
            dropDestination(dest, "Couldn't create folders there: \(error.localizedDescription)")
        }
    }

    private func dropDestination(_ i: Int, _ why: String) {
        guard destAlive[i] else { return }
        destAlive[i] = false
        update { $0.destDead[i] = why }
    }

    private func copyLink(_ e: PlanEntry) {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let n = readlink(e.source, &buf, Int(PATH_MAX))
        guard n > 0 else { return }
        let target = String(cString: buf)
        for (i, root) in destinations.enumerated() where destAlive[i] {
            let final = Self.join(root, e.rel)
            makeDir((final as NSString).deletingLastPathComponent, dest: i)
            var st = stat()
            if lstat(final, &st) == 0 {
                if options.conflict != .replace { continue }
                unlink(final)
            }
            _ = symlink(target, final)
        }
    }

    private static func uniqueName(_ path: String) -> String {
        let ns = path as NSString
        let dir = ns.deletingLastPathComponent
        let ext = ns.pathExtension
        let stem = (ns.lastPathComponent as NSString).deletingPathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = (dir as NSString).appendingPathComponent(name)
            var st = stat()
            if lstat(candidate, &st) != 0 { return candidate }
            n += 1
        }
    }

    private struct Target {
        let dest: Int
        var final: String
        var tmp: String
        var fd: Int32
        var ok = true
    }

    private func copyFile(_ e: PlanEntry, id: Int) {
        let count = destinations.count
        var result = FileResult(id: id, rel: e.rel, size: e.size, states: Array(repeating: .pending, count: count))
        var targets: [Target] = []
        var existing: [(dest: Int, path: String, size: Int64)] = []

        for (i, root) in destinations.enumerated() {
            guard destAlive[i] else { result.states[i] = .failed("Destination unavailable"); continue }
            var final = Self.join(root, e.rel)
            makeDir((final as NSString).deletingLastPathComponent, dest: i)
            guard destAlive[i] else { result.states[i] = .failed("Destination unavailable"); continue }
            var st = stat()
            if lstat(final, &st) == 0 {
                switch options.conflict {
                case .skip:
                    existing.append((i, final, Int64(st.st_size)))
                    continue
                case .replace:
                    break
                case .keepBoth:
                    final = Self.uniqueName(final)
                }
            }
            let tmp = final + ".stowmap-partial"
            let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd < 0 {
                result.states[i] = .failed("Couldn't create the file: \(String(cString: strerror(errno)))")
                continue
            }
            _ = fcntl(fd, F_NOCACHE, 1)
            targets.append(Target(dest: i, final: final, tmp: tmp, fd: fd))
            result.states[i] = .copying
        }

        update {
            $0.activity = "Copying"
            $0.currentName = result.name
            $0.currentSize = e.size
            $0.currentDone = 0
        }

        func abandon(_ why: String) {
            for t in targets where t.ok { close(t.fd); unlink(t.tmp) }
            for i in 0..<count where !result.states[i].isProblem && result.states[i] != .pending || result.states[i] == .copying {
                result.states[i] = .failed(why)
            }
            for x in existing { result.states[x.dest] = .failed(why) }
            finish(result, verifiedSkipBytes: e.size)
        }

        // 1. Read the source once; write every destination; checksum what was read.
        let src = open(e.source, O_RDONLY)
        guard src >= 0 else {
            abandon("Couldn't read the source: \(String(cString: strerror(errno)))")
            update { $0.copiedBytes += e.size }
            return
        }
        _ = fcntl(src, F_NOCACHE, 1)
        let buf = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 16384)
        defer { buf.deallocate() }
        var hasher = FileHasher(options.hash)
        var readTotal: Int64 = 0
        var sourceError: String?

        while true {
            if !proceed() {
                close(src)
                for t in targets where t.ok { close(t.fd); unlink(t.tmp) }
                return                                  // stopped: nothing half-written is left behind
            }
            let t0 = DispatchTime.now().uptimeNanoseconds
            let n = read(src, buf, chunk)
            let t1 = DispatchTime.now().uptimeNanoseconds
            if n < 0 {
                if errno == EINTR { continue }
                sourceError = "Reading the source failed: \(String(cString: strerror(errno)))"
                break
            }
            if n == 0 { break }
            hasher.update(UnsafeRawBufferPointer(start: buf, count: n))
            readTotal += Int64(n)
            var writeTimes = [UInt64](repeating: 0, count: count)
            for k in targets.indices where targets[k].ok {
                let w0 = DispatchTime.now().uptimeNanoseconds
                var off = 0
                while off < n {
                    let w = write(targets[k].fd, buf + off, n - off)
                    if w < 0 {
                        if errno == EINTR { continue }
                        let why = String(cString: strerror(errno))
                        close(targets[k].fd)
                        unlink(targets[k].tmp)
                        targets[k].ok = false
                        result.states[targets[k].dest] = .failed("Writing failed: \(why)")
                        if errno == ENOSPC || errno == EIO || errno == ENXIO || errno == EROFS {
                            dropDestination(targets[k].dest, "Writing failed: \(why)")
                        }
                        break
                    }
                    off += w
                }
                writeTimes[targets[k].dest] = DispatchTime.now().uptimeNanoseconds - w0
            }
            update {
                $0.copiedBytes += Int64(n)
                $0.currentDone += Int64(n)
                $0.readNanos += t1 - t0
                for i in 0..<count {
                    $0.writeNanos[i] += writeTimes[i]
                    if writeTimes[i] > 0 { $0.destCopied[i] += Int64(n) }
                }
            }
        }
        close(src)

        if let sourceError {
            update { $0.copiedBytes += max(0, e.size - readTotal) }
            abandon(sourceError)
            return
        }
        if readTotal != e.size {
            // The file changed size while it was being read; keep the progress totals honest.
            update { $0.copiedBytes += e.size - readTotal }
        }
        let sourceHash = hasher.hex()
        result.hash = sourceHash

        // 2. Flush to the disk, copy dates and attributes, and only then give the file its real name.
        for k in targets.indices where targets[k].ok {
            let t = targets[k]
            if fcntl(t.fd, F_FULLFSYNC) != 0 { _ = fsync(t.fd) }
            close(t.fd)
            _ = copyfile(e.source, t.tmp, nil, copyfile_flags_t(COPYFILE_METADATA))
            if rename(t.tmp, t.final) != 0 {
                let why = String(cString: strerror(errno))
                unlink(t.tmp)
                targets[k].ok = false
                result.states[t.dest] = .failed("Couldn't finish the file: \(why)")
            }
        }

        if let damage = options.corruptForTest, damage == e.rel, let t = targets.first(where: { $0.ok }) {
            Self.flipFirstByte(t.final)
        }

        // 3. Verify.
        var sourceStable = true
        if options.verify == .both {
            update { $0.activity = "Verifying"; $0.currentDone = 0 }
            let again = FileHasher.hashFile(e.source, kind: options.hash, onBytes: { n in
                self.update { $0.verifiedBytes += Int64(n); $0.currentDone += Int64(n) }
            }, keepGoing: { self.proceed() })
            if isCancelled { return }
            sourceStable = again == sourceHash
        }

        for t in targets where t.ok {
            if options.verify == .off {
                result.states[t.dest] = sourceStable ? .copied : .failed("The source read differently twice")
                continue
            }
            result.states[t.dest] = .verifying
            update { $0.activity = "Verifying"; $0.currentDone = 0 }
            let v0 = DispatchTime.now().uptimeNanoseconds
            let back = FileHasher.hashFile(t.final, kind: options.hash, onBytes: { n in
                self.update { $0.verifiedBytes += Int64(n); $0.destVerified[t.dest] += Int64(n); $0.currentDone += Int64(n) }
            }, keepGoing: { self.proceed() })
            let spent = DispatchTime.now().uptimeNanoseconds - v0
            if isCancelled { return }
            update { $0.verifyNanos[t.dest] += spent }
            if !sourceStable {
                result.states[t.dest] = .failed("The source read differently twice")
            } else if back == sourceHash {
                result.states[t.dest] = .verified
            } else if back == nil {
                result.states[t.dest] = .failed("Couldn't read the copy back")
            } else {
                result.states[t.dest] = .mismatch
            }
        }

        // Files that were already in a destination: compare, never touch.
        for x in existing {
            if x.size != e.size {
                result.states[x.dest] = .existsDifferent
                update { $0.verifiedBytes += self.options.verify == .off ? 0 : e.size }
                continue
            }
            update { $0.activity = "Verifying"; $0.currentDone = 0 }
            var counted: Int64 = 0
            let there = FileHasher.hashFile(x.path, kind: options.hash, onBytes: { n in
                counted += Int64(n)
                if self.options.verify != .off {
                    self.update { $0.verifiedBytes += Int64(n); $0.destVerified[x.dest] += Int64(n) }
                }
            }, keepGoing: { self.proceed() })
            if isCancelled { return }
            result.states[x.dest] = there == sourceHash ? .alreadyThere : .existsDifferent
        }

        // Destinations that failed still owe their share of the verify total; settle it so the bar ends at 100%.
        let unverified = result.states.filter { if case .failed = $0 { return true }; return false }.count
        finish(result, verifiedSkipBytes: options.verify == .off ? 0 : e.size * Int64(unverified))

        for (i, state) in result.states.enumerated() where state.isGood {
            manifest[i].append((e.rel, e.size, sourceHash, e.modified))
        }
    }

    private func finish(_ result: FileResult, verifiedSkipBytes: Int64) {
        update {
            $0.filesDone += 1
            $0.verifiedBytes += verifiedSkipBytes
            let worst = result.worst
            if worst.isProblem { $0.problems.append(result) } else { $0.good += 1 }
            if worst == .alreadyThere { $0.alreadyThere += 1 }
            for (i, s) in result.states.enumerated() where s == .verified || s == .alreadyThere {
                $0.destFilesVerified[i] += 1
            }
            $0.recent.insert(result, at: 0)
            if $0.recent.count > 60 { $0.recent.removeLast($0.recent.count - 60) }
        }
    }

    private static func flipFirstByte(_ path: String) {
        let fd = open(path, O_RDWR)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var b: UInt8 = 0
        guard pread(fd, &b, 1, 0) == 1 else { return }
        b = ~b
        _ = pwrite(fd, &b, 1, 0)
        _ = fsync(fd)
    }

    // MARK: checksum lists

    private func writeLists() {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd_HHmmss"
        let iso = ISO8601DateFormatter()
        let name = "Stowmap_\(stamp.string(from: Date()))"
        var written: [String] = []

        for (i, root) in destinations.enumerated() where destAlive[i] && !manifest[i].isEmpty {
            let rows = manifest[i].sorted { $0.rel < $1.rel }

            // Plain list: "<checksum>  <path>", the layout md5sum, shasum and xxhsum read.
            let text = rows.map { "\($0.hash)  \($0.rel)" }.joined(separator: "\n") + "\n"
            let listPath = Self.join(root, "\(name).\(options.hash.listExtension)")
            if (try? text.write(toFile: listPath, atomically: true, encoding: .utf8)) != nil { written.append(listPath) }

            // MHL 1.1, for tools on set and in post that check hand-offs.
            if let tag = options.hash.mhlTag {
                var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<hashlist version=\"1.1\">\n"
                xml += "  <creatorinfo>\n"
                xml += "    <name>\(Self.xml(NSFullUserName()))</name>\n"
                xml += "    <username>\(Self.xml(NSUserName()))</username>\n"
                xml += "    <hostname>\(Self.xml(ProcessInfo.processInfo.hostName))</hostname>\n"
                xml += "    <tool>Stowmap</tool>\n"
                xml += "    <startdate>\(iso.string(from: snapshot().started))</startdate>\n"
                xml += "    <finishdate>\(iso.string(from: Date()))</finishdate>\n"
                xml += "  </creatorinfo>\n"
                let now = iso.string(from: Date())
                for r in rows {
                    xml += "  <hash>\n"
                    xml += "    <file>\(Self.xml(r.rel))</file>\n"
                    xml += "    <size>\(r.size)</size>\n"
                    xml += "    <lastmodificationdate>\(iso.string(from: r.modified))</lastmodificationdate>\n"
                    xml += "    <\(tag)>\(r.hash)</\(tag)>\n"
                    xml += "    <hashdate>\(now)</hashdate>\n"
                    xml += "  </hash>\n"
                }
                xml += "</hashlist>\n"
                let mhlPath = Self.join(root, "\(name).mhl")
                if (try? xml.write(toFile: mhlPath, atomically: true, encoding: .utf8)) != nil { written.append(mhlPath) }
            }
        }
        update { $0.listPaths = written }
    }

    private static func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Check a copy (compare two folders)

struct CompareItem: Identifiable, Sendable {
    let rel: String
    let sizeOriginal: Int64
    let sizeCopy: Int64
    let why: String
    var id: String { rel }
    var name: String { (rel as NSString).lastPathComponent }
}

struct CompareResult: Sendable {
    var matched = 0
    var matchedBytes: Int64 = 0
    var missing: [CompareItem] = []        // in the original, not in the copy
    var different: [CompareItem] = []      // in both, but not the same
    var extra: [CompareItem] = []          // only in the copy
    var unreadable: [String] = []
    var full = false                       // checksums were compared, not just sizes
    var isComplete: Bool { missing.isEmpty && different.isEmpty }
}

/// A value handed between threads under its own lock.
final class Shared<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

final class CompareJob: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64 = 0
    private var total: Int64 = 0
    private var stage = "Listing both folders"
    private var listedA = 0
    private var listedB = 0
    private var hashing = false
    private var pairsDone = 0
    private var pairsTotal = 0
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    struct Progress: Sendable {
        var stage: String
        var listed: Int          // files found so far, both sides
        var hashing: Bool        // false while listing
        var fraction: Double     // of the checksum pass (0 while listing)
        var bytesDone: Int64     // read so far, both sides
        var bytesTotal: Int64
        var filesDone: Int       // files compared so far
        var filesTotal: Int
    }
    var progress: Progress {
        lock.lock(); defer { lock.unlock() }
        return Progress(stage: stage, listed: listedA + listedB, hashing: hashing,
                        fraction: hashing ? min(1, Double(done) / Double(max(1, total))) : 0,
                        bytesDone: done, bytesTotal: total, filesDone: pairsDone, filesTotal: pairsTotal)
    }
    private func add(_ n: Int64) { lock.lock(); done += n; lock.unlock() }
    private func pairFinished() { lock.lock(); pairsDone += 1; lock.unlock() }
    private func setListed(a: Int? = nil, b: Int? = nil) {
        lock.lock()
        if let a { listedA = a }
        if let b { listedB = b }
        lock.unlock()
    }
    private func digest(_ path: String, _ kind: HashKind) -> String? {
        FileHasher.hashFile(path, kind: kind, onBytes: { self.add(Int64($0)) }, keepGoing: { !self.isCancelled })
    }

    /// Blocking. Quick = names and sizes; full = also reads both sides and compares checksums.
    func run(original: String, copy: String, full: Bool, options: TransferOptions) -> CompareResult {
        var out = CompareResult()
        out.full = full

        // List both folders at the same time; they are usually on different drives.
        let planA = Shared(TransferPlan()), planB = Shared(TransferPlan())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            planA.value = TransferPlanner.contents(of: original, options: options, keepGoing: { !self.isCancelled },
                                                   found: { n in self.setListed(a: n) })
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            planB.value = TransferPlanner.contents(of: copy, options: options, keepGoing: { !self.isCancelled },
                                                   found: { n in self.setListed(b: n) })
            group.leave()
        }
        group.wait()
        if isCancelled { return out }
        let a = planA.value, b = planB.value

        out.unreadable = a.unreadable + b.unreadable
        var copyFiles: [String: PlanEntry] = [:]
        for e in b.entries where e.kind == .file { copyFiles[e.rel] = e }

        var toHash: [(PlanEntry, PlanEntry)] = []
        for e in a.entries where e.kind == .file {
            guard let other = copyFiles.removeValue(forKey: e.rel) else {
                out.missing.append(CompareItem(rel: e.rel, sizeOriginal: e.size, sizeCopy: 0, why: "Not in the copy"))
                continue
            }
            if other.size != e.size {
                let why = other.size < e.size ? "The copy is smaller (incomplete)" : "The copy is larger"
                out.different.append(CompareItem(rel: e.rel, sizeOriginal: e.size, sizeCopy: other.size, why: why))
            } else if full {
                toHash.append((e, other))
            } else {
                out.matched += 1
                out.matchedBytes += e.size
            }
        }
        for (_, e) in copyFiles {
            out.extra.append(CompareItem(rel: e.rel, sizeOriginal: 0, sizeCopy: e.size, why: "Only in the copy"))
        }

        if full {
            lock.lock()
            stage = "Comparing checksums"
            total = toHash.reduce(Int64(0)) { $0 + $1.0.size } * 2
            done = 0
            pairsTotal = toHash.count
            hashing = true
            lock.unlock()

            let kind = options.hash
            let smallLimit: Int64 = 4 * 1024 * 1024
            let small = toHash.filter { $0.0.size < smallLimit }
            let large = toHash.filter { $0.0.size >= smallLimit }
            // (original, copy, checksum of the original, checksum of the copy)
            let verdicts = Shared([(PlanEntry, PlanEntry, String?, String?)]())
            let vlock = NSLock()
            func record(_ e: PlanEntry, _ other: PlanEntry, _ ha: String?, _ hb: String?) {
                vlock.lock()
                var list = verdicts.value
                list.append((e, other, ha, hb))
                verdicts.value = list
                vlock.unlock()
                pairFinished()
            }

            // Small files: several at once. Their cost is the wait per file, not the bytes.
            let workers = 4
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                var i = w
                while i < small.count {
                    if self.isCancelled { return }
                    let (e, other) = small[i]
                    let ha = self.digest(e.source, kind)
                    let hb = self.digest(other.source, kind)
                    record(e, other, ha, hb)
                    i += workers
                }
            }
            // Large files: one at a time, reading the two sides at the same time.
            for (e, other) in large {
                if isCancelled { break }
                let left = Shared<String?>(nil)
                let pair = DispatchGroup()
                pair.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    left.value = self.digest(e.source, kind)
                    pair.leave()
                }
                let hb = digest(other.source, kind)
                pair.wait()
                record(e, other, left.value, hb)
            }
            if isCancelled { return out }
            for (e, other, ha, hb) in verdicts.value {
                if let ha, let hb, ha == hb {
                    out.matched += 1
                    out.matchedBytes += e.size
                } else if ha == nil || hb == nil {
                    out.different.append(CompareItem(rel: e.rel, sizeOriginal: e.size, sizeCopy: other.size,
                                                     why: "Couldn't read one side"))
                } else {
                    out.different.append(CompareItem(rel: e.rel, sizeOriginal: e.size, sizeCopy: other.size,
                                                     why: "Same size, different contents"))
                }
            }
        }
        out.missing.sort { $0.sizeOriginal > $1.sizeOriginal }
        out.different.sort { $0.sizeOriginal > $1.sizeOriginal }
        out.extra.sort { $0.sizeCopy > $1.sizeCopy }
        return out
    }
}
