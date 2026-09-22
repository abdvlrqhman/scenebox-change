//
//  WatchProgressStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private(set) var items: [WatchProgress] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private let minRecordSeconds: Double = 15
    /// Positions saved during playback but not yet shown to the rest of the UI.
    /// Publishing every 5 s re-rendered every poster and row under the video.
    @ObservationIgnored private var unpublished: [String: WatchProgress] = [:]
    @ObservationIgnored private var lastPublished: [String: Date] = [:]
    @ObservationIgnored private var backend: WatchProgressBackend

    init(backend: WatchProgressBackend = LocalWatchProgressBackend()) {
        self.backend = backend
        Task { await reload() }
    }

    func use(_ backend: WatchProgressBackend) {
        self.backend = backend
        unpublished.removeAll()
        items = []
        hasLoaded = false
        Task { await reload() }
    }

    private func reload() async {
        let loaded = await backend.load()
        items = loaded.sorted { $0.updatedAt > $1.updatedAt }
        hasLoaded = true
    }

    func refresh() {
        Task {
            let remote = await backend.load()
            var merged = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
            for item in remote where (merged[item.id]?.updatedAt ?? .distantPast) < item.updatedAt {
                merged[item.id] = item
            }
            items = merged.values.sorted { $0.updatedAt > $1.updatedAt }
            hasLoaded = true
        }
    }

    func progress(for mediaID: String) -> WatchProgress? {
        unpublished[mediaID] ?? items.first { $0.id == mediaID }
    }

    /// What the Continue Watching shelf shows. Finished movies stay in the
    /// history (so they can be marked as watched) but are done.
    var continueItems: [WatchProgress] {
        items.filter { !($0.mediaType == .movie && $0.isFinished) }
    }

    /// How far into this episode playback got, while it's unfinished.
    func episodeFraction(mediaID: String, episodeID: String) -> Double? {
        guard let saved = progress(for: mediaID), saved.episodeID == episodeID,
              !saved.isFinished, saved.fraction > 0.01 else { return nil }
        return saved.fraction
    }

    func isMovieWatched(_ mediaID: String) -> Bool {
        guard let saved = progress(for: mediaID) else { return false }
        return saved.mediaType == .movie && saved.isFinished
    }

    func setMovieWatched(_ watched: Bool, id: String, title: String, posterURL: URL?) {
        guard watched else { remove(id: id); return }
        unpublished[id] = nil
        let item = WatchProgress(
            id: id, mediaType: .movie, title: title,
            posterURLString: posterURL?.absoluteString,
            season: nil, episode: nil, episodeID: nil,
            positionSeconds: 1, durationSeconds: 1,         // fraction 1 → finished
            updatedAt: Date())
        items.removeAll { $0.id == id }
        items.insert(item, at: 0)
        Task { [backend] in await backend.upsert(item) }
    }

    func record(id: String, mediaType: MediaType, title: String, posterURL: URL?,
                season: Int?, episode: Int?, episodeID: String?,
                position: Duration, duration: Duration?, publish: Bool = false) {
        let pos = position.asSeconds
        guard pos >= minRecordSeconds else { return }

        var item = WatchProgress(
            id: id, mediaType: mediaType, title: title,
            posterURLString: posterURL?.absoluteString,
            season: season, episode: episode, episodeID: episodeID,
            positionSeconds: pos, durationSeconds: duration?.asSeconds ?? 0,
            updatedAt: Date())

        if mediaType != .movie, let previous = progress(for: id) {
            var watched = Set(previous.watchedEpisodes ?? [])
            if previous.isFinished, let label = previous.downloadEpisodeLabel { watched.insert(label) }
            if item.isFinished, let label = item.downloadEpisodeLabel { watched.insert(label) }
            item.watchedEpisodes = watched.sorted()
        } else if item.isFinished, let label = item.downloadEpisodeLabel {
            item.watchedEpisodes = [label]
        }

        Task { [backend] in await backend.upsert(item) }

        // Saved every time; shown to the rest of the app when something visible
        // changes, every 30 s, or when playback ends.
        let shown = items.first { $0.id == id }
        let visibleChange = shown == nil || shown?.isFinished != item.isFinished
            || shown?.episodeID != item.episodeID
        let due = Date().timeIntervalSince(lastPublished[id] ?? .distantPast) >= 30
        if publish || visibleChange || due {
            unpublished[id] = nil
            lastPublished[id] = Date()
            items.removeAll { $0.id == id }
            items.insert(item, at: 0)
        } else {
            unpublished[id] = item
        }
    }

    func watchedEpisodes(for mediaID: String) -> Set<String> {
        guard let saved = progress(for: mediaID) else { return [] }
        var set = Set(saved.watchedEpisodes ?? [])
        if saved.isFinished, let label = saved.downloadEpisodeLabel { set.insert(label) }
        return set
    }

    func hasWatched(mediaID: String, episode: Episode) -> Bool {
        watchedEpisodes(for: mediaID).contains(episode.label)
    }

    func setWatched(_ watched: Bool, episode: Episode, mediaID: String, mediaType: MediaType,
                    title: String, posterURL: URL?) {
        var item = progress(for: mediaID) ?? WatchProgress(
            id: mediaID, mediaType: mediaType, title: title,
            posterURLString: posterURL?.absoluteString,
            season: nil, episode: nil, episodeID: nil,
            positionSeconds: 0, durationSeconds: 0, updatedAt: Date())
        var set = Set(item.watchedEpisodes ?? [])
        if item.isFinished, let label = item.downloadEpisodeLabel { set.insert(label) }

        if watched {
            set.insert(episode.label)
            item.season = episode.season
            item.episode = episode.episode
            item.episodeID = episode.id
            item.positionSeconds = 1
            item.durationSeconds = 1          // fraction 1 → finished
        } else {
            set.remove(episode.label)
            if item.episodeID == episode.id {
                item.positionSeconds = 0
                item.durationSeconds = 0      // back to "not started"
            }
        }
        item.watchedEpisodes = set.sorted()
        item.updatedAt = Date()
        unpublished[mediaID] = nil

        if set.isEmpty, item.positionSeconds <= 0 {
            remove(id: mediaID)
            return
        }
        items.removeAll { $0.id == mediaID }
        items.insert(item, at: 0)
        Task { [backend] in await backend.upsert(item) }
    }

    func remove(id: String) {
        unpublished[id] = nil
        items.removeAll { $0.id == id }
        Task { [backend] in await backend.remove(id: id) }
    }

    func clear() {
        unpublished.removeAll()
        items.removeAll()
        Task { [backend] in await backend.clear() }
    }
}

extension Duration {
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
