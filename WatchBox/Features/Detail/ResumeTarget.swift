//
//  ResumeTarget.swift
//  SceneBox
//

import Foundation

extension MediaDetail {
    /// The episode Play starts: the one part-watched, else the next unwatched
    /// one after the last finished, else `fallback`. Movies have none.
    nonisolated func resumeEpisode(saved: WatchProgress?, watched: Set<String>, fallback: Episode?) -> Episode? {
        guard type != .movie else { return nil }
        guard let saved, let epID = saved.episodeID,
              let index = episodes.firstIndex(where: { $0.id == epID }) else {
            guard !watched.isEmpty else { return fallback }
            return episodes.first { !watched.contains($0.label) } ?? fallback
        }
        if saved.isFinished {
            let following = episodes[(index + 1)...]
            if let next = following.first(where: { !watched.contains($0.label) }) { return next }
            return following.first ?? episodes[index]
        }
        return episodes[index]
    }
}
