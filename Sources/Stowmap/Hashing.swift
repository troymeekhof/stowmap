import Foundation
import CryptoKit

// Checksums for Copy & Verify. xxHash64 is the fast one used on film sets (and in MHL lists);
// MD5 and SHA-256 are there for hand-offs that ask for them.

/// Streaming xxHash64 (seed 0). Checked against the reference implementation by the self-test.
struct XXH64 {
    private static let p1: UInt64 = 11400714785074694791
    private static let p2: UInt64 = 14029467366897019727
    private static let p3: UInt64 = 1609587929392839161
    private static let p4: UInt64 = 9650029242287828579
    private static let p5: UInt64 = 2870177450012600261

    private var v1: UInt64 = XXH64.p1 &+ XXH64.p2
    private var v2: UInt64 = XXH64.p2
    private var v3: UInt64 = 0
    private var v4: UInt64 = 0 &- XXH64.p1
    private var total: UInt64 = 0
    private var buffer = [UInt8](repeating: 0, count: 32)
    private var buffered = 0

    @inline(__always) private static func rotl(_ x: UInt64, _ r: UInt64) -> UInt64 { (x << r) | (x >> (64 - r)) }

    @inline(__always) private static func round(_ acc: UInt64, _ input: UInt64) -> UInt64 {
        rotl(acc &+ input &* p2, 31) &* p1
    }

    @inline(__always) private static func merge(_ acc: UInt64, _ val: UInt64) -> UInt64 {
        (acc ^ round(0, val)) &* p1 &+ p4
    }

    @inline(__always) private static func read64(_ p: UnsafeRawPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    @inline(__always) private static func read32(_ p: UnsafeRawPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    private mutating func consumeStripe(_ p: UnsafeRawPointer, _ offset: Int) {
        v1 = XXH64.round(v1, XXH64.read64(p, offset))
        v2 = XXH64.round(v2, XXH64.read64(p, offset + 8))
        v3 = XXH64.round(v3, XXH64.read64(p, offset + 16))
        v4 = XXH64.round(v4, XXH64.read64(p, offset + 24))
    }

    mutating func update(_ data: UnsafeRawBufferPointer) {
        guard let base = data.baseAddress, data.count > 0 else { return }
        total &+= UInt64(data.count)
        var offset = 0
        var remaining = data.count

        // Top up a partly filled stripe first.
        if buffered > 0 {
            let take = min(32 - buffered, remaining)
            buffer.withUnsafeMutableBytes { dst in
                dst.baseAddress!.advanced(by: buffered).copyMemory(from: base, byteCount: take)
            }
            buffered += take
            offset += take
            remaining -= take
            if buffered < 32 { return }
            buffer.withUnsafeBytes { consumeStripe($0.baseAddress!, 0) }
            buffered = 0
        }
        while remaining >= 32 {
            consumeStripe(base, offset)
            offset += 32
            remaining -= 32
        }
        if remaining > 0 {
            buffer.withUnsafeMutableBytes { dst in
                dst.baseAddress!.copyMemory(from: base.advanced(by: offset), byteCount: remaining)
            }
            buffered = remaining
        }
    }

    /// The digest so far. Does not disturb the running state.
    func digest() -> UInt64 {
        var h: UInt64
        if total >= 32 {
            h = XXH64.rotl(v1, 1) &+ XXH64.rotl(v2, 7) &+ XXH64.rotl(v3, 12) &+ XXH64.rotl(v4, 18)
            h = XXH64.merge(h, v1)
            h = XXH64.merge(h, v2)
            h = XXH64.merge(h, v3)
            h = XXH64.merge(h, v4)
        } else {
            h = XXH64.p5
        }
        h &+= total
        buffer.withUnsafeBytes { raw in
            let p = raw.baseAddress!
            var i = 0
            while buffered - i >= 8 {
                h ^= XXH64.round(0, XXH64.read64(p, i))
                h = XXH64.rotl(h, 27) &* XXH64.p1 &+ XXH64.p4
                i += 8
            }
            if buffered - i >= 4 {
                h ^= UInt64(XXH64.read32(p, i)) &* XXH64.p1
                h = XXH64.rotl(h, 23) &* XXH64.p2 &+ XXH64.p3
                i += 4
            }
            while i < buffered {
                h ^= UInt64(p.load(fromByteOffset: i, as: UInt8.self)) &* XXH64.p5
                h = XXH64.rotl(h, 11) &* XXH64.p1
                i += 1
            }
        }
        h ^= h >> 33
        h = h &* XXH64.p2
        h ^= h >> 29
        h = h &* XXH64.p3
        h ^= h >> 32
        return h
    }

    /// Big-endian hex, the form MHL lists and `xxhsum` print.
    func hex() -> String { String(format: "%016llx", digest()) }
}

enum HashKind: String, CaseIterable, Identifiable, Sendable {
    case xxh64, md5, sha256
    var id: String { rawValue }

    var title: String {
        switch self {
        case .xxh64: return "xxHash64"
        case .md5: return "MD5"
        case .sha256: return "SHA-256"
        }
    }

    /// File extension for the plain checksum list.
    var listExtension: String { rawValue }

    /// Element name in an MHL 1.1 list; SHA-256 isn't part of that format.
    var mhlTag: String? {
        switch self {
        case .xxh64: return "xxhash64be"
        case .md5: return "md5"
        case .sha256: return nil
        }
    }
}

/// One running checksum of the chosen kind.
struct FileHasher {
    let kind: HashKind
    private var xx = XXH64()
    private var md5 = Insecure.MD5()
    private var sha = SHA256()

    init(_ kind: HashKind) { self.kind = kind }

    mutating func update(_ data: UnsafeRawBufferPointer) {
        switch kind {
        case .xxh64: xx.update(data)
        case .md5: md5.update(bufferPointer: data)
        case .sha256: sha.update(bufferPointer: data)
        }
    }

    func hex() -> String {
        switch kind {
        case .xxh64: return xx.hex()
        case .md5: return md5.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha256: return sha.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Checksum of a whole file, read from the disk and not from the system's cache.
    /// `onBytes` reports progress; return false from `keepGoing` to stop early.
    static func hashFile(_ path: String, kind: HashKind, onBytes: (Int) -> Void = { _ in },
                         keepGoing: () -> Bool = { true }) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = FileHasher(kind)
        let size = 4 << 20
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
        defer { buf.deallocate() }
        while true {
            if !keepGoing() { return nil }
            let n = read(fd, buf, size)
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { break }
            hasher.update(UnsafeRawBufferPointer(start: buf, count: n))
            onBytes(n)
        }
        return hasher.hex()
    }
}
