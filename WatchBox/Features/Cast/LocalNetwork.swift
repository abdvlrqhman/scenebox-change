//
//  LocalNetwork.swift
//  SceneBox
//

import Foundation
import Darwin

/// The phone's address on the Wi-Fi (or on its own hotspot), which TVs use to
/// fetch the video, and the neighbouring addresses to look for TVs at.
nonisolated enum LocalNetwork {
    struct Interface: Sendable, Equatable {
        let name: String
        let address: String
        let prefixLength: Int
    }

    /// Wi-Fi first (en0), then other Ethernet-like links and the Personal
    /// Hotspot bridge. Never cellular or VPN tunnels.
    static func current() -> Interface? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found: [Interface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let flags = Int32(bitPattern: entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let bits = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var copy = ip
            guard inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let text = String(cString: buffer)
            guard !text.hasPrefix("169.254.") else { continue }        // no DHCP answer: not a real network
            found.append(Interface(name: name, address: text, prefixLength: UInt32(bigEndian: bits).nonzeroBitCount))
        }
        return found.first { $0.name == "en0" } ?? found.first
    }

    /// Every other address in our /24 (the whole subnet when it's smaller).
    /// Home networks are /24; on bigger ones the TV is almost always close.
    static func neighbours(of address: String, prefixLength: Int) -> [String] {
        let octets = address.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 < 256 }) else { return [] }
        let ip = octets[0] << 24 | octets[1] << 16 | octets[2] << 8 | octets[3]
        let prefix = min(32, max(24, prefixLength))
        let mask: UInt32 = prefix == 32 ? .max : ~(UInt32.max >> UInt32(prefix))
        let network = ip & mask
        let size = UInt32(1) << UInt32(32 - prefix)
        guard size > 2 else { return [] }
        return (1..<(size - 1)).compactMap { offset in
            let candidate = network | offset
            guard candidate != ip else { return nil }
            return "\(candidate >> 24).\(candidate >> 16 & 255).\(candidate >> 8 & 255).\(candidate & 255)"
        }
    }
}

/// Sends SSDP searches and collects answers (blocking; run off the main
/// thread). Asks the multicast group, which only works when the app holds
/// Apple's multicast permission, and every neighbour directly, which works
/// without it on devices that answer direct searches.
nonisolated enum SSDPSearch {
    static func run(hosts: [String], duration: TimeInterval = 2.6) -> [SSDP.Response] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 150_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = 0                              // any address
        _ = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }

        func send(_ data: Data, to host: String) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = SSDP.port.bigEndian
            guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return }
            data.withUnsafeBytes { bytes in
                _ = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var answers: [String: SSDP.Response] = [:]
        var buffer = [UInt8](repeating: 0, count: 4096)
        func collect(until deadline: Date) {
            while Date() < deadline {
                let count = recv(fd, &buffer, buffer.count, 0)
                guard count > 0 else { continue }
                if let response = SSDP.parseResponse(Data(buffer[0..<count])) {
                    answers[response.location.absoluteString] = response
                }
            }
        }

        // Two rounds, since UDP gets lost.
        let end = Date().addingTimeInterval(duration)
        for round in 0..<2 {
            send(SSDP.searchMessage(host: SSDP.multicastAddress), to: SSDP.multicastAddress)
            for (index, host) in hosts.enumerated() {
                send(SSDP.searchMessage(host: host), to: host)
                if index % 32 == 31 { usleep(2000) }           // don't flood the Wi-Fi
            }
            collect(until: round == 0 ? Date().addingTimeInterval(duration / 2) : end)
        }
        return Array(answers.values)
    }
}
