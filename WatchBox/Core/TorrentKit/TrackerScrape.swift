//
//  TrackerScrape.swift
//  SceneBox
//

import Foundation
import Network

/// Asks trackers how many people share each torrent right now (the UDP
/// tracker "scrape", BEP 15). Source lists carry seeder counts from whenever
/// they were indexed, often weeks old; a scrape takes a fraction of a second
/// and tells a live torrent from a dead one before anything is opened.
nonisolated enum TrackerScrape {
    struct Swarm: Sendable, Codable, Equatable {
        var seeders: Int
        var leechers: Int
        var completed: Int
    }

    struct Endpoint: Sendable, Hashable {
        let host: String
        let port: UInt16

        /// udp://host:port/announce → an endpoint; other schemes → nil.
        init?(_ url: URL) {
            guard url.scheme?.lowercased() == "udp", let host = url.host, !host.isEmpty,
                  let port = url.port, port > 0, port <= Int(UInt16.max) else { return nil }
            self.host = host
            self.port = UInt16(port)
        }
    }

    /// A scrape answer holds 12 bytes per torrent and must fit one UDP packet.
    static let hashesPerPacket = 70
    private static let protocolID: UInt64 = 0x417_2710_1980

    // MARK: Asking several trackers

    /// The largest count any tracker reports for each info-hash (keyed by the
    /// 20-byte hash). Nil when no tracker answered at all, which means the
    /// network blocks UDP: "unknown", not "dead".
    static func scrape(_ hashes: [Data], trackers: [Endpoint],
                       timeout: Duration = .milliseconds(2500)) async -> [Data: Swarm]? {
        let hashes = Array(Set(hashes.filter { $0.count == 20 }))
        guard !hashes.isEmpty, !trackers.isEmpty else { return nil }
        return await withTaskGroup(of: [Swarm]?.self) { group in
            for tracker in trackers {
                group.addTask { await scrape(hashes, at: tracker, timeout: timeout) }
            }
            var best: [Data: Swarm]?
            for await answer in group {
                guard let answer, answer.count == hashes.count else { continue }
                var merged = best ?? [:]
                for (hash, swarm) in zip(hashes, answer) {
                    let seen = merged[hash]
                    merged[hash] = Swarm(seeders: max(seen?.seeders ?? 0, swarm.seeders),
                                         leechers: max(seen?.leechers ?? 0, swarm.leechers),
                                         completed: max(seen?.completed ?? 0, swarm.completed))
                }
                best = merged
            }
            return best
        }
    }

    /// One tracker: connect, then scrape in packets of `hashesPerPacket`.
    static func scrape(_ hashes: [Data], at endpoint: Endpoint, timeout: Duration) async -> [Swarm]? {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .udp)
        let queue = DispatchQueue(label: "watchbox.scrape")
        defer { connection.cancel() }
        return try? await NetworkIO.withTimeout(timeout, throwing: URLError(.timedOut)) {
            try await NetworkIO.start(connection, on: queue)
            let hello = UInt32.random(in: .min ... .max)
            try await NetworkIO.send(connection, connectRequest(transaction: hello))
            let accepted = try await NetworkIO.receiveMessage(connection, minimumLength: 8)
            guard let connectionID = parseConnect(accepted, transaction: hello) else {
                throw TorrentError.trackerFailed("scrape connect refused")
            }
            var swarms: [Swarm] = []
            var start = 0
            while start < hashes.count {
                let batch = Array(hashes[start..<min(hashes.count, start + hashesPerPacket)])
                let transaction = UInt32.random(in: .min ... .max)
                try await NetworkIO.send(connection, scrapeRequest(connectionID: connectionID,
                                                                   transaction: transaction, hashes: batch))
                let reply = try await NetworkIO.receiveMessage(connection, minimumLength: 8)
                guard let parsed = parseScrape(reply, transaction: transaction, count: batch.count) else {
                    throw TorrentError.trackerFailed("scrape refused")
                }
                swarms += parsed
                start += batch.count
            }
            return swarms
        }
    }

    // MARK: Packets

    static func connectRequest(transaction: UInt32) -> Data {
        var data = Data()
        data.appendBigEndian(protocolID)
        data.appendBigEndian(UInt32(0))            // action: connect
        data.appendBigEndian(transaction)
        return data
    }

    /// The connection id, if this is the answer to our connect.
    static func parseConnect(_ data: Data, transaction: UInt32) -> UInt64? {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, bytes.readUInt32(at: 0) == 0,
              bytes.readUInt32(at: 4) == transaction else { return nil }
        return bytes.readUInt64(at: 8)
    }

    static func scrapeRequest(connectionID: UInt64, transaction: UInt32, hashes: [Data]) -> Data {
        var data = Data()
        data.appendBigEndian(connectionID)
        data.appendBigEndian(UInt32(2))            // action: scrape
        data.appendBigEndian(transaction)
        for hash in hashes { data.append(hash) }
        return data
    }

    /// Seeders, completed and leechers per hash, in request order. Nil for an
    /// error answer (action 3), a stray packet or a short one.
    static func parseScrape(_ data: Data, transaction: UInt32, count: Int) -> [Swarm]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 + 12 * count, bytes.readUInt32(at: 0) == 2,
              bytes.readUInt32(at: 4) == transaction else { return nil }
        return (0..<count).map { index in
            let base = 8 + 12 * index
            return Swarm(seeders: Int(bytes.readUInt32(at: base)),
                         leechers: Int(bytes.readUInt32(at: base + 8)),
                         completed: Int(bytes.readUInt32(at: base + 4)))
        }
    }
}

nonisolated private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

nonisolated private extension [UInt8] {
    func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        self[offset..<offset + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
