import Foundation
import IOKit

// "Is this as fast as the hardware should go?" Works out what a drive or network link can
// normally sustain, so the app can stay quiet when a job runs at the hardware's pace and say
// something only when it is clearly below it. When the hardware can't be identified, there is
// no expectation and so never a warning.

struct DeviceClass: Sendable {
    let label: String        // "a USB 3 SSD", "a 1 Gb/s network link"
    let mbps: Double         // large-file MB/s it should sustain
    let filesPerSecond: Double   // folder listing rate it should manage while mapping
}

enum Hardware {
    /// What the device behind a path should manage, or nil when it can't be told.
    static func expected(forPath path: String) -> DeviceClass? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        if fs.f_flags & UInt32(MNT_LOCAL) == 0 { return networkClass() }
        let from: String = withUnsafePointer(to: &fs.f_mntfromname) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tuple.pointee)) {
                String(cString: $0)
            }
        }
        guard from.hasPrefix("/dev/") else { return nil }
        return diskClass(bsdName: String(from.dropFirst(5)))
    }

    // MARK: network

    /// Based on the fastest wired or Wi-Fi interface that is up and has an address.
    private static func networkClass() -> DeviceClass? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return nil }
        defer { freeifaddrs(first) }

        var withAddress = Set<String>()
        var speeds: [String: UInt64] = [:]
        var p: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let addr = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            let flags = Int32(ifa.ifa_flags)
            guard name.hasPrefix("en"), flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            let family = Int32(addr.pointee.sa_family)
            if family == AF_INET || family == AF_INET6 {
                withAddress.insert(name)
            } else if family == AF_LINK, let data = ifa.ifa_data {
                let baud = data.assumingMemoryBound(to: if_data.self).pointee.ifi_baudrate
                speeds[name] = UInt64(baud)
            }
        }
        let bps = speeds.filter { withAddress.contains($0.key) }.values.max() ?? 0
        guard bps >= 10_000_000 else { return nil }
        let mbit = Double(bps) / 1_000_000
        let label: String
        if mbit >= 9000 { label = "a 10 Gb/s network link" }
        else if mbit >= 2000 { label = String(format: "a %.1f Gb/s network link", mbit / 1000) }
        else if mbit >= 900 { label = "a 1 Gb/s network link" }
        else { label = String(format: "a %.0f Mb/s network link", mbit) }
        // File sharing overhead takes roughly a fifth off the raw link speed.
        return DeviceClass(label: label, mbps: mbit / 8 * 0.8, filesPerSecond: 300)
    }

    // MARK: disks

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    private static func diskClass(bsdName: String) -> DeviceClass? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let proto = property(service, "Protocol Characteristics") as? [String: Any]
        let device = property(service, "Device Characteristics") as? [String: Any]
        let interconnect = (proto?["Physical Interconnect"] as? String ?? "").lowercased()
        let medium = (device?["Medium Type"] as? String ?? "").lowercased()
        let solid = medium.contains("solid")
        let spinning = medium.contains("rotational")
        if interconnect.isEmpty || interconnect.contains("virtual") { return nil }       // disk images and the like

        if interconnect.contains("usb") {
            // 2 = USB 2 (480 Mb/s), 3 = 5 Gb/s, 4 and up = 10 Gb/s or faster.
            let speed = (property(service, "Device Speed") as? NSNumber)?.intValue
            if speed == 2 { return DeviceClass(label: "a USB 2 connection", mbps: 35, filesPerSecond: 800) }
            if spinning { return DeviceClass(label: "a USB hard drive", mbps: 110, filesPerSecond: 800) }
            if let speed, speed >= 4 { return DeviceClass(label: "a 10 Gb/s USB SSD", mbps: 650, filesPerSecond: 8000) }
            return DeviceClass(label: "a USB 3 SSD", mbps: 350, filesPerSecond: 8000)
        }
        if interconnect.contains("secure digital") {
            return DeviceClass(label: "an SD card", mbps: 60, filesPerSecond: 800)
        }
        if spinning { return DeviceClass(label: "a hard drive", mbps: 120, filesPerSecond: 800) }
        if interconnect.contains("thunderbolt") {
            return DeviceClass(label: "a Thunderbolt SSD", mbps: 900, filesPerSecond: 15000)
        }
        if interconnect.contains("sata") {
            return DeviceClass(label: "a SATA SSD", mbps: 380, filesPerSecond: 10000)
        }
        if interconnect.contains("pci") || interconnect.contains("fabric") || interconnect.contains("nvme") {
            return DeviceClass(label: "an internal SSD", mbps: 1200, filesPerSecond: 20000)
        }
        return solid ? DeviceClass(label: "an SSD", mbps: 350, filesPerSecond: 8000) : nil
    }
}

/// Decides whether a measured rate deserves a note. Quiet unless the hardware is known and the
/// job is well under what it should manage.
enum Pace {
    /// Copying or verifying. `mbps` is the measured rate of the slowest stage, `averageFileBytes`
    /// the typical file in the recent window (lots of small files are slow on any hardware).
    static func transferNote(name: String, verb: String, mbps: Double, expected: DeviceClass?,
                             averageFileBytes: Int64) -> String? {
        guard let expected, mbps > 0, averageFileBytes >= 8_000_000 else { return nil }
        guard mbps < expected.mbps * 0.4 else { return nil }
        let usual = expected.mbps >= 100 ? (expected.mbps / 50).rounded() * 50 : (expected.mbps / 5).rounded() * 5
        return "\(name) is \(verb) at \(Int(mbps.rounded())) MB/s. \(expected.label.capitalizedFirst) usually manages about \(Int(usual)). "
            + hint(for: expected)
    }

    /// Mapping a drive. `rate` is files listed per second over the recent window.
    static func scanNote(name: String, rate: Double, expected: DeviceClass?) -> String? {
        guard let expected, rate > 0, rate < expected.filesPerSecond * 0.2 else { return nil }
        if expected.label.contains("network") {
            return "\(name) is answering slowly (\(Int(rate.rounded())) files a second). The server or the network is the limit here, not your Mac."
        }
        return "\(name) is listing \(Int(rate.rounded())) files a second, well under what \(expected.label) usually manages. Another app may be using the drive heavily."
    }

    private static func hint(for d: DeviceClass) -> String {
        if d.label.contains("network") { return "The server may be busy, or the Mac may be on Wi-Fi." }
        if d.label.contains("USB") { return "Check the cable and port." }
        if d.label.contains("internal") { return "Another app may be using the drive heavily." }
        return "Check the cable, or whether the drive is nearly full."
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
