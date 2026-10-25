import Foundation

public enum NetworkInfo {
    /// IPv4 of Wi-Fi (`en0` on iPhone), or of the phone's Personal Hotspot (`bridge100`) when it's the host.
    public static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var found: [String: String] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found[String(cString: ptr.pointee.ifa_name)] = String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        }
        // Other en* covers the Simulator on Macs whose Wi-Fi isn't en0; 169.254 = link-local, unreachable.
        return found["en0"] ?? found["bridge100"]
            ?? found.sorted { $0.key < $1.key }.first { $0.key.hasPrefix("en") && !$0.value.hasPrefix("169.254.") }?.value
    }
}
