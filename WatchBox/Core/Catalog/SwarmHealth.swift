//
//  SwarmHealth.swift
//  SceneBox
//

import Foundation

/// Live seeder counts for sources, from tracker scrapes, kept for a few
/// minutes; and the sources that failed to start this session, so they sink
/// in the list and aren't used as fallbacks again.
actor SwarmHealth {
    static let shared = SwarmHealth()

    private var cache: [String: (swarm: TrackerScrape.Swarm, at: Date)] = [:]
    private var failed: Set<String> = []
    private let freshFor: TimeInterval = 10 * 60

    /// Live counts keyed by source id (the info-hash in hex). Sources the
    /// trackers didn't answer for are missing, which ranks them on their
    /// listed count instead.
    func check(_ streams: [TorrentStream],
               timeout: Duration = .milliseconds(2500)) async -> [String: TrackerScrape.Swarm] {
        let torrents = streams.filter { !$0.isDebrid && $0.infoHash.count == 20 }
        let now = Date()
        var result: [String: TrackerScrape.Swarm] = [:]
        var missing: [TorrentStream] = []
        for stream in torrents {
            let key = stream.id.lowercased()
            if let hit = cache[key], now.timeIntervalSince(hit.at) < freshFor {
                result[key] = hit.swarm
            } else {
                missing.append(stream)
            }
        }
        guard !missing.isEmpty else { return result }

        // The big public trackers, plus the ones these sources name most.
        var trackers = DefaultTrackers.scrapeEndpoints
        var counts: [TrackerScrape.Endpoint: Int] = [:]
        for url in missing.flatMap(\.trackers) {
            if let endpoint = TrackerScrape.Endpoint(url) { counts[endpoint, default: 0] += 1 }
        }
        let named = counts.sorted { $0.value > $1.value }.map(\.key)
            .filter { endpoint in !trackers.contains { $0.host == endpoint.host } }
        trackers += named.prefix(3)

        guard let live = await TrackerScrape.scrape(missing.map(\.infoHash), trackers: trackers,
                                                    timeout: timeout) else { return result }
        let answered = Date()
        for stream in missing {
            guard let swarm = live[stream.infoHash] else { continue }
            let key = stream.id.lowercased()
            cache[key] = (swarm, answered)
            result[key] = swarm
        }
        return result
    }

    func markFailed(_ id: String) {
        failed.insert(id.lowercased())
    }

    func failedIDs() -> Set<String> { failed }
}
