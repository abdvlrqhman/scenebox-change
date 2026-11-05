//
//  EpisodePlaylist.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation

@MainActor
struct EpisodePlaylist {
    let current: Episode
    let all: [Episode]
    /// The show's id, for watched marks in the episode list.
    var mediaID: String = ""
    let onPlay: (Episode) -> Void

    var next: Episode? {
        let ordered = all
            .filter { $0.season > 0 }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard let index = ordered.firstIndex(of: current), index + 1 < ordered.count else { return nil }
        // An episode that hasn't aired has nothing to play; the season ends here.
        let following = ordered[index + 1]
        return (following.released ?? .distantPast) > Date() ? nil : following
    }

    var nextIsNewSeason: Bool {
        guard let next else { return false }
        return next.season != current.season
    }

    var seasons: [Int] { Array(Set(all.map(\.season))).sorted() }

    func episodes(inSeason season: Int) -> [Episode] {
        all.filter { $0.season == season }.sorted { $0.episode < $1.episode }
    }
}
