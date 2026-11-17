import Foundation

// MARK: - Scan tree

/// One entry in the scanned tree. Built on background threads during a scan (each folder node is
/// only ever mutated by the one worker that owns it), then handed to the UI read-only.
final class FileNode: Identifiable, @unchecked Sendable {
    enum Kind: UInt8, Codable {
        case folder, file
        case smallFiles    // many little files in one folder, rolled into a single entry
        case hiddenSpace   // space the volume reports as used but no scan can see
    }

    let name: String
    let kind: Kind
    let isHidden: Bool
    var size: Int64
    var fileCount: Int
    var children: [FileNode] = []
    weak var parent: FileNode?
    var rootPath: String?          // set on the root node only
    var unreadable = false         // permission denied while listing
    var linkedVolumeID: String?    // an entry standing in for another share on the same server

    init(name: String, kind: Kind, isHidden: Bool = false, size: Int64 = 0, fileCount: Int = 0) {
        self.name = name
        self.kind = kind
        self.isHidden = isHidden
        self.size = size
        self.fileCount = fileCount
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Real on-disk path. Roll-up entries resolve to the folder that contains them.
    var path: String {
        if let rootPath { return rootPath }
        guard let parent else { return name }
        let base = parent.path
        if kind == .smallFiles || kind == .hiddenSpace { return base }
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var isFolder: Bool { kind == .folder }
    var canDrill: Bool { kind == .folder && !children.isEmpty }
    var isReal: Bool { kind == .folder || kind == .file }

    var ext: String { kind == .file ? FileTypes.ext(of: name) : "" }

    /// Root → self.
    var ancestry: [FileNode] {
        var chain: [FileNode] = [self]
        var cur = parent
        while let c = cur { chain.append(c); cur = c.parent }
        return chain.reversed()
    }
}

// MARK: - File types

struct TypeStat: Codable, Identifiable {
    var ext: String        // "" = no extension
    var count: Int
    var bytes: Int64
    var id: String { ext }
    var category: FileCategory { FileTypes.category(for: ext) }
    var label: String { ext.isEmpty ? "No extension" : "." + ext }
}

struct LargeFile: Codable, Identifiable {
    var path: String
    var size: Int64
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

enum FileCategory: String, CaseIterable, Codable, Identifiable {
    case video, images, audio, documents, code, archives, apps, system, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .images: return "Images"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .code: return "Code & Data"
        case .archives: return "Archives & Disk Images"
        case .apps: return "Apps & Libraries"
        case .system: return "System & Caches"
        case .other: return "Everything Else"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .images: return "photo"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archives: return "shippingbox"
        case .apps: return "app.badge"
        case .system: return "gearshape.2"
        case .other: return "doc"
        }
    }
}

enum FileTypes {
    private static let table: [String: FileCategory] = {
        var t: [String: FileCategory] = [:]
        func add(_ c: FileCategory, _ list: String) { for e in list.split(separator: " ") { t[String(e)] = c } }
        add(.video, "mov mp4 m4v mkv avi mxf braw r3d ari webm mpg mpeg mts m2ts wmv flv prores 3gp insv lrv crm dav ts vob")
        add(.images, "jpg jpeg png heic heif gif tif tiff bmp webp raw cr2 cr3 nef arw dng raf orf rw2 psd psb ai svg ico icns exr dpx tga hdr avif xmp lrcat lrdata")
        add(.audio, "mp3 wav aif aiff m4a flac aac ogg opus caf wma mid midi alac band logicx")
        add(.documents, "pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf md epub mobi csv tsv odt ods odp indd idml eml emlx msg")
        add(.code, "swift js ts jsx tsx py rb go rs c h cpp hpp m mm java kt cs php html css scss json xml yaml yml toml sh zsh sql sqlite db plist map lock ipynb wasm pack idx")
        add(.archives, "zip dmg pkg tar gz tgz bz2 xz 7z rar iso sparsebundle sparseimage zst img ipsw xip cpgz")
        add(.apps, "app dylib framework so a o bundle kext car nib tbd jar exe dll node")
        add(.system, "log cache tmp temp swp bak dat bin db-wal db-shm sqlite-wal sqlite-shm asl tracev3 diag crash ips download part")
        return t
    }()

    static func category(for ext: String) -> FileCategory { table[ext] ?? .other }

    /// Lower-cased extension, or "" when there is none (or it isn't a plausible extension).
    static func ext(of name: String) -> String {
        let u = name.utf8
        guard let dot = u.lastIndex(of: UInt8(ascii: ".")), dot != u.startIndex else { return "" }
        let tail = u[u.index(after: dot)...]
        guard !tail.isEmpty, tail.count <= 12 else { return "" }
        for b in tail {
            let alnum = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45
            if !alnum { return "" }
        }
        return String(decoding: tail, as: UTF8.self).lowercased()
    }
}

// MARK: - Scan result

struct ScanResult: @unchecked Sendable {
    var root: FileNode
    var types: [TypeStat]
    var largest: [LargeFile]
    var date: Date
    var duration: TimeInterval
    var denied: Int              // folders that couldn't be read (needs Full Disk Access)
    var fromCache = false        // restored from the saved index: small items are rolled up

    var categories: [(category: FileCategory, bytes: Int64, count: Int)] {
        var acc: [FileCategory: (Int64, Int)] = [:]
        for t in types {
            let cur = acc[t.category] ?? (0, 0)
            acc[t.category] = (cur.0 + t.bytes, cur.1 + t.count)
        }
        return acc.map { (category: $0.key, bytes: $0.value.0, count: $0.value.1) }
            .sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Volumes

struct Volume: Identifiable, Equatable {
    enum Kind: Int { case boot, internalDrive, external, network, folder }

    var id: String { path }
    var name: String
    var path: String
    var kind: Kind
    var total: Int64 = 0
    var free: Int64 = 0          // what Finder shows (includes purgeable)
    var realFree: Int64 = 0      // blocks actually free right now
    var format: String = ""
    var uuid: String?
    var server: String?          // network shares: the host they are mounted from

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// Shares from one server that report the same capacity sit on the same storage pool.
    var poolKey: String? {
        guard kind == .network, let server, total > 0 else { return nil }
        return server + "|" + String(total)
    }

    var symbol: String {
        switch kind {
        case .boot, .internalDrive: return "internaldrive.fill"
        case .external: return "externaldrive.fill"
        case .network: return "externaldrive.connected.to.line.below.fill"
        case .folder: return "folder.fill"
        }
    }

    var kindLabel: String {
        switch kind {
        case .boot: return "Startup disk"
        case .internalDrive: return "Internal"
        case .external: return "External"
        case .network: return "Network share"
        case .folder: return "Folder"
        }
    }

    var cacheKey: String {
        let raw = uuid ?? path
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return String(safe.suffix(120))
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, b), countStyle: .file)
    }

    static func count(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    static func pct(_ f: Double) -> String {
        if f <= 0 { return "0%" }
        if f < 0.001 { return "<0.1%" }
        if f < 0.1 { return String(format: "%.1f%%", f * 100) }
        return String(format: "%.0f%%", f * 100)
    }

    static func ago(_ d: Date) -> String {
        if Date().timeIntervalSince(d) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func duration(_ t: TimeInterval) -> String {
        t < 60 ? String(format: "%.1f s", t) : String(format: "%d min %02d s", Int(t) / 60, Int(t) % 60)
    }
}
