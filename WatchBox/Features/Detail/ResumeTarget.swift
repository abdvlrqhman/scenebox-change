//
//  ResumeTarget.swift
//  SceneBox
//

import Foundation

extension MediaDetail {
    /// The episode Play starts, shared by the title page and Home's Up next:
    /// - the one part-watched;
    /// - else the next unwatched one after the last finished;
    /// - else, for a show not started yet, its first downloaded episode
    ///   (that's what the viewer got ready), or `fallback`.
    /// Once watching has begun, order wins: Play never skips an episode just
    /// because a later one is downloaded. Movies have none. `downloaded` holds
    /// episode labels ("S1E3").
    nonisolated func resumeEpisode(savedEpisodeID: String?, savedFinished: Bool, watched: Set<String>,
                                   downloaded: Set<String> = [], fallback: Episode?) -> Episode? {
        guard type != .movie else { return nil }
        if let id = savedEpisodeID, let index = episodes.firstIndex(where: { $0.id == id }) {
            guard savedFinished else { return episodes[index] }
            let following = episodes[(index + 1)...]
            return following.first { !watched.contains($0.label) } ?? following.first ?? episodes[index]
        }
        if !watched.isEmpty { return episodes.first { !watched.contains($0.label) } ?? fallback }
        let firstDownload = episodes
            .filter { $0.season > 0 && downloaded.contains($0.label) }
            .min { ($0.season, $0.episode) < ($1.season, $1.episode) }
        return firstDownload ?? fallback
    }
}
