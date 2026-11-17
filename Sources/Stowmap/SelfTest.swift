import Foundation

// `Stowmap --selftest` exercises the checksum and copy code against real files in a temporary
// folder and exits non-zero if anything is wrong. The build runs it before a release is published.

enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print((ok ? "PASS  " : "FAIL  ") + name)
            if !ok { failures += 1 }
        }
        func pattern(_ n: Int) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) } }
        func xx(_ bytes: [UInt8], _ chunks: [Int]) -> String {
            var h = XXH64()
            var i = 0, c = 0
            while i < bytes.count {
                let take = min(chunks[c % chunks.count], bytes.count - i)
                bytes[i..<(i + take)].withUnsafeBytes { h.update($0) }
                i += take
                c += 1
            }
            return h.hex()
        }

        // 1. Checksums against known answers (from the reference xxHash and MD5 implementations).
        let vectors: [(Int, String)] = [(0, "ef46db3751d8e999"), (3, "56e6957632a487f9"), (32, "8d57d6a4671cc43d"),
                                        (33, "62c9fd21ed857664"), (1000, "99594f4828043d35")]
        for (n, want) in vectors {
            check(xx(pattern(n), [1 << 20]) == want, "xxHash64 of \(n) bytes")
            check(xx(pattern(n), [5, 1, 40, 13, 200, 7]) == want, "xxHash64 of \(n) bytes, fed in odd pieces")
        }
        check(xx(Array("abc".utf8), [3]) == "44bc2cf5ad770999", "xxHash64 of \"abc\"")
        var md5 = FileHasher(.md5)
        pattern(1000).withUnsafeBytes { md5.update($0) }
        check(md5.hex() == "2b1e78d5765de9e10495a01412a1cf22", "MD5 of 1000 bytes")

        // 2. A small project tree with awkward sizes: empty, one byte, just over a stripe, over a chunk.
        let fm = FileManager.default
        let base = NSTemporaryDirectory() + "stowmap-selftest-" + UUID().uuidString
        let proj = base + "/src/Proj"
        defer { try? fm.removeItem(atPath: base) }
        func write(_ rel: String, _ n: Int, seed: Int = 0) {
            let path = proj + "/" + rel
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let bytes = (0..<n).map { UInt8(truncatingIfNeeded: ($0 &+ seed) &* 131 &+ 17) }
            fm.createFile(atPath: path, contents: Data(bytes))
        }
        write("a.bin", 0)
        write("b.bin", 1)
        write("c.bin", 33)
        write("big.bin", 9 * 1024 * 1024 + 3, seed: 5)
        write("sub/d.bin", 100_000, seed: 9)
        write(".hidden", 10)
        write(".DS_Store", 5)
        try? fm.createDirectory(atPath: proj + "/empty", withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: proj + "/link", withDestinationPath: "b.bin")
        let files = ["a.bin", "b.bin", "c.bin", "big.bin", "sub/d.bin", ".hidden"]
        let d1 = base + "/d1", d2 = base + "/d2", d3 = base + "/d3", d4 = base + "/d4"
        for d in [d1, d2, d3, d4] { try? fm.createDirectory(atPath: d, withIntermediateDirectories: true) }

        func copy(_ dests: [String], _ o: TransferOptions) -> TransferSnapshot {
            let plan = TransferPlanner.build(sources: [proj], options: o)
            let engine = TransferEngine(plan: plan, destinations: dests, options: o)
            engine.run()
            return engine.snapshot()
        }
        func same(_ dest: String, _ rel: String) -> Bool { fm.contentsEqual(atPath: proj + "/" + rel, andPath: dest + "/Proj/" + rel) }
        func leftovers(_ dest: String) -> Int {
            (fm.enumerator(atPath: dest)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".stowmap-partial") }.count
        }

        // 3. Copy to two destinations, verifying source and destination.
        var o = TransferOptions(hash: .xxh64, verify: .both, conflict: .skip)
        var s = copy([d1, d2], o)
        check(s.phase == .finished, "copy finishes")
        check(s.filesDone == files.count, "copies \(files.count) files and skips .DS_Store (did \(s.filesDone))")
        check(s.problems.isEmpty && s.good == files.count, "every file verified on both destinations")
        check(files.allSatisfy { same(d1, $0) && same(d2, $0) }, "copies are byte-for-byte the same as the source")
        check(!fm.fileExists(atPath: d1 + "/Proj/.DS_Store"), ".DS_Store is not copied")
        check(fm.fileExists(atPath: d2 + "/Proj/empty"), "empty folders are kept")
        check((try? fm.destinationOfSymbolicLink(atPath: d1 + "/Proj/link")) == "b.bin", "symbolic links are kept as links")
        check(leftovers(d1) == 0 && leftovers(d2) == 0, "no partial files are left behind")
        check(s.fraction > 0.999, "progress ends at 100% (\(s.fraction))")
        check(s.listPaths.count == 4, "a checksum list and an MHL are written in each destination (\(s.listPaths.count))")
        let bigHash = FileHasher.hashFile(proj + "/big.bin", kind: .xxh64) ?? "?"
        let listText = s.listPaths.first(where: { $0.hasSuffix(".xxh64") }).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        check(listText.contains("\(bigHash)  Proj/big.bin"), "the checksum list holds the right checksum for the big file")
        let mhl = s.listPaths.first(where: { $0.hasSuffix(".mhl") }).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        check(mhl.contains("<xxhash64be>\(bigHash)</xxhash64be>") && mhl.contains("<hashlist version=\"1.1\">"), "the MHL holds it too")

        // 4. Copy again: nothing is rewritten, everything is recognised as already there.
        s = copy([d1], o)
        check(s.problems.isEmpty && s.alreadyThere == files.count, "a second run finds every file already there and identical")

        // 5. A copy that reads back differently is caught.
        o.corruptForTest = "Proj/big.bin"
        s = copy([d3], o)
        o.corruptForTest = nil
        check(s.problems.count == 1 && s.problems.first?.states.first == .mismatch, "a damaged copy is reported as a checksum mismatch")

        // 6. An existing, different file is reported and left alone under Skip…
        let changed = Data((0..<33).map { _ in UInt8(0xAA) })
        fm.createFile(atPath: d1 + "/Proj/c.bin", contents: changed)
        s = copy([d1], o)
        check(s.problems.count == 1 && s.problems.first?.states.first == .existsDifferent, "an existing, different file is flagged")
        check(fm.contents(atPath: d1 + "/Proj/c.bin") == changed, "…and is not touched")

        // 7. …kept alongside under Keep both…
        o.conflict = .keepBoth
        s = copy([d1], o)
        check(fm.contents(atPath: d1 + "/Proj/c.bin") == changed && fm.contentsEqual(atPath: proj + "/c.bin", andPath: d1 + "/Proj/c 2.bin"),
              "Keep both writes the new file beside the old one")

        // 8. …and replaced only under Replace.
        o.conflict = .replace
        s = copy([d1], o)
        check(s.problems.isEmpty && same(d1, "c.bin"), "Replace overwrites it with a verified copy")

        // 9. MD5 and SHA-256 runs verify too.
        for kind in [HashKind.md5, .sha256] {
            let r = copy([d4], TransferOptions(hash: kind, verify: .destination, conflict: .replace))
            check(r.problems.isEmpty && r.good == files.count, "\(kind.title) copy verifies")
        }

        // 10. Check a copy: complete, then with a missing, a short, an extra and a silently changed file.
        let cmp = TransferOptions()
        var r = CompareJob().run(original: proj, copy: d2 + "/Proj", full: true, options: cmp)
        check(r.isComplete && r.matched == files.count && r.extra.isEmpty, "a good copy checks as complete")
        try? fm.removeItem(atPath: d2 + "/Proj/sub/d.bin")
        if let h = FileHandle(forWritingAtPath: d2 + "/Proj/big.bin") { h.truncateFile(atOffset: 9 * 1024 * 1024); h.closeFile() }
        fm.createFile(atPath: d2 + "/Proj/extra.txt", contents: Data("x".utf8))
        fm.createFile(atPath: d2 + "/Proj/c.bin", contents: changed)
        r = CompareJob().run(original: proj, copy: d2 + "/Proj", full: false, options: cmp)
        check(r.missing.count == 1 && r.different.count == 1 && r.extra.count == 1, "quick check finds the missing, short and extra files")
        r = CompareJob().run(original: proj, copy: d2 + "/Proj", full: true, options: cmp)
        check(r.missing.count == 1 && r.different.count == 2 && r.extra.count == 1, "full check also finds the file changed without changing size")

        // 11. Hardware lookup must not crash; what it reports is informational.
        if let c = Hardware.expected(forPath: base) { print("INFO  this disk looks like \(c.label), about \(Int(c.mbps)) MB/s") }
        else { print("INFO  this disk's class could not be determined") }

        print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED: \(failures)")
        return failures == 0 ? 0 : 1
    }
}
