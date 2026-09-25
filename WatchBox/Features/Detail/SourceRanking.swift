//
//  SourceRanking.swift
//  SceneBox
//

import Foundation

/// Orders sources by how likely they are to start quickly and play without
/// buffering: live seeders first, then the preferred resolution, with files
/// too heavy to stream over a phone connection pushed down. Pure, so the CI
/// self-test checks it.
nonisolated enum SourceRanking {
    enum Health: Sendable, Equatable {
        case strong      // 20+ seeders right now
        case fair        // 5–19
        case weak        // 1–4, or leechers only
        case dead        // trackers answered: nobody is sharing it
        case unknown     // no live answer; only the source list's old count
    }

    struct Facts: Sendable {
        var listedSeeders: Int?          // from the source list, possibly weeks old
        var liveSeeders: Int?            // from a tracker scrape just now
        var liveLeechers: Int?
        var resolution: String?
        var sizeBytes: Int64?
        var isDebrid = false
        var failedBefore = false         // didn't start earlier this session
    }

    struct Assessment: Sendable, Equatable {
        let health: Health
        /// Live when `isLive`, else the listed count.
        let seeders: Int?
        let isLive: Bool
        /// The bitrate the file needs, from its size and the runtime.
        let megabitsPerSecond: Double?
        /// Didn't start when tried earlier this session.
        var failedBefore = false
        let score: Double

        /// Worth trying without asking: skipped by auto-pick and fallbacks otherwise.
        var isPlayable: Bool { health != .dead }
        /// Needs a fast, steady connection to play without pauses.
        var isHeavy: Bool { (megabitsPerSecond ?? 0) > 25 }
    }

    static func assess(_ facts: Facts, preferredResolution: String,
                       runtimeMinutes: Double, debridEnabled: Bool) -> Assessment {
        let mbps: Double? = facts.sizeBytes.map { bytes in
            Double(bytes) * 8 / (max(runtimeMinutes, 10) * 60) / 1_000_000
        }
        let resolution = resolutionBonus(facts.resolution, preferred: preferredResolution)

        // Cached on a debrid service: streams from a server, always first.
        if debridEnabled, facts.isDebrid {
            return Assessment(health: .strong, seeders: facts.listedSeeders, isLive: false,
                              megabitsPerSecond: mbps, failedBefore: facts.failedBefore,
                              score: 1000 + resolution)
        }

        let isLive = facts.liveSeeders != nil
        let seeders = facts.liveSeeders ?? facts.listedSeeders ?? 0
        let leechers = facts.liveLeechers ?? 0
        let health: Health
        if isLive {
            switch seeders {
            case 20...: health = .strong
            case 5...: health = .fair
            case 1...: health = .weak
            default: health = leechers >= 3 ? .weak : .dead
            }
        } else {
            health = .unknown
        }

        // Each doubling of the swarm is worth about the same up to ~60 peers,
        // which is plenty to stream; beyond that it counts for little. Leechers
        // hold pieces too. An old listed count is trusted less than a live one.
        let swarm = log2(1 + Double(seeders) + 0.25 * Double(leechers))
        var score = swarm > 6 ? 6 + (swarm - 6) * 0.25 : swarm
        if !isLive { score *= 0.8 }
        score += resolution
        if let mbps {
            if mbps > 40 { score -= 4 } else if mbps > 25 { score -= 2 } else if mbps > 15 { score -= 0.75 }
        }
        if facts.failedBefore { score -= 8 }
        if health == .dead { score -= 30 }
        return Assessment(health: health, seeders: isLive ? seeders : facts.listedSeeders,
                          isLive: isLive, megabitsPerSecond: mbps, failedBefore: facts.failedBefore,
                          score: score)
    }

    /// The preferred resolution counts about as much as an eightfold swarm, so
    /// a well-seeded 1080p beats a huge 720p swarm, but a near-dead 1080p
    /// doesn't.
    static func resolutionBonus(_ resolution: String?, preferred: String) -> Double {
        let order = ["480p": 1, "720p": 2, "1080p": 3, "2160p": 4]
        guard let wanted = order[preferred.lowercased()] else { return 0 }
        guard let have = resolution.flatMap({ order[$0.lowercased()] }) else { return 0.5 }
        if have == wanted { return 3.5 }
        if have == wanted - 1 { return 1.2 }
        if have > wanted { return 0.8 }
        return 0
    }

    /// "1.4 GB" / "700 MB" / "2.1 GiB" → bytes.
    static func sizeBytes(_ text: String?) -> Int64? {
        guard let text else { return nil }
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: " ")
        guard parts.count >= 2, let value = Double(parts[0]), value > 0 else { return nil }
        let unit = parts[1].uppercased()
        let scale: Double
        if unit.hasPrefix("T") { scale = 1_099_511_627_776 }
        else if unit.hasPrefix("G") { scale = 1_073_741_824 }
        else if unit.hasPrefix("M") { scale = 1_048_576 }
        else if unit.hasPrefix("K") { scale = 1024 }
        else { return nil }
        return Int64(value * scale)
    }

    /// "58 min" / "2h 10min" → minutes; a typical length when unknown.
    static func runtimeMinutes(_ text: String?, isSeries: Bool) -> Double {
        let fallback: Double = isSeries ? 45 : 110
        guard let text = text?.lowercased(), !text.isEmpty else { return fallback }
        var minutes = 0.0
        var number = ""
        var sawUnit = false
        for character in text + " " {
            if character.isNumber { number.append(character); continue }
            if let value = Double(number) {
                if character == "h" { minutes += value * 60; sawUnit = true }
                else { minutes += value; sawUnit = true }
            }
            number = ""
        }
        return sawUnit && minutes >= 5 ? minutes : fallback
    }
}
