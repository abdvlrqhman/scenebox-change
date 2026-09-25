//
//  MediaDetailModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation
import Observation
import Kingfisher

@MainActor
@Observable
final class MediaDetailModel {
    let mediaID: String
    let type: MediaType

    private(set) var detail: MediaDetail?
    private(set) var castMembers: [CastMember] = []
    private(set) var originalLanguage: String?
    private(set) var similar: [MediaResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var imagesReady = false

    var isReady: Bool { detail != nil && imagesReady }

    var selectedSeason: Int = 1

    var releaseRequest: ReleaseRequest?
    private(set) var releases: [TorrentStream] = []
    /// How each source looks right now (live seeders, weight), by source id.
    private(set) var assessments: [String: SourceRanking.Assessment] = [:]
    private(set) var isLoadingReleases = false
    /// "Finding sources…", then "Checking which are alive…".
    private(set) var releaseStage = "Finding sources…"
    private(set) var releaseError: String?

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings

    init(mediaID: String, type: MediaType, settings: AppSettings? = nil) {
        self.mediaID = mediaID
        self.type = type
        let settings = settings ?? .shared
        self.settings = settings
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    deinit {
        loadTask?.cancel()
        releaseTask?.cancel()
    }

    struct ReleaseRequest: Identifiable, Equatable {
        enum Intent { case watch, download }

        let intent: Intent
        let episode: Episode?

        var id: String { "\(intent)-\(episode?.id ?? "movie")" }

        var title: String {
            switch intent {
            case .watch: "Choose a release to stream"
            case .download: "Choose a release to download"
            }
        }
    }

    // MARK: - Metadata

    func load() {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        loadTask = Task { [mediaID, type, search] in
            do {
                let fetched = try await search.detail(id: mediaID, type: type)
                guard !Task.isCancelled else { return }
                detail = fetched
                selectedSeason = fetched.seasons.first ?? 1

                await Self.prefetch([fetched.backdropURL, fetched.logoURL])
                guard !Task.isCancelled else { return }
                imagesReady = true

                async let cast: Void = loadCast(for: fetched)
                async let related: Void = loadSimilar(for: fetched)
                _ = await (cast, related)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadCast(for detail: MediaDetail) async {
        guard let tmdbID = detail.moviedbID,
              let tmdb = TMDBClient(key: settings.tmdbAPIKey) else { return }
        async let members = tmdb.cast(tmdbID: tmdbID, type: detail.type)
        async let language = tmdb.originalLanguage(tmdbID: tmdbID, type: detail.type)
        let (cast, code) = await (members, language)
        guard !Task.isCancelled else { return }
        castMembers = cast
        originalLanguage = code
    }

    private func loadSimilar(for detail: MediaDetail) async {
        guard let genre = detail.genres.first, !genre.isEmpty else { return }
        let items = (try? await search.catalog(type: detail.type, feed: .popular, genre: genre)) ?? []
        guard !Task.isCancelled else { return }
        similar = Array(items.filter { $0.id != detail.id }.prefix(20))
    }

    private static func prefetch(_ urls: [URL?]) async {
        let targets = urls.compactMap { $0 }
        guard !targets.isEmpty else { return }
        await withCheckedContinuation { continuation in
            ImagePrefetcher(urls: targets, completionHandler: { _, _, _ in
                continuation.resume()
            }).start()
        }
    }

    // MARK: - Releases

    func requestReleases(intent: ReleaseRequest.Intent, episode: Episode? = nil) {
        releaseRequest = ReleaseRequest(intent: intent, episode: episode)
        loadReleases(for: episode)
    }

    private func loadReleases(for episode: Episode?) {
        releaseTask?.cancel()
        releases = []
        assessments = [:]
        releaseError = nil
        releaseStage = "Finding sources…"
        isLoadingReleases = true

        releaseTask = Task { [mediaID, type, search] in
            do {
                let found = try await search.streams(
                    id: mediaID, type: type,
                    season: episode?.season, episode: episode?.episode)
                guard !Task.isCancelled else { return }

                releaseStage = "Checking which are alive…"
                let ranked = await rank(found)
                guard !Task.isCancelled else { return }
                releases = ranked.streams
                assessments = ranked.assessments
                releaseError = releases.isEmpty ? "No sources available for this title." : nil
            } catch {
                guard !Task.isCancelled else { return }
                releaseError = error.localizedDescription
            }
            isLoadingReleases = false
        }
    }

    func dismissReleases() {
        releaseTask?.cancel()
        releaseRequest = nil
        releases = []
        assessments = [:]
        releaseError = nil
        isLoadingReleases = false
    }

    /// What to try, in order, if `stream` doesn't start: the next best
    /// sources that still have seeders.
    func fallbacks(after stream: TorrentStream, limit: Int = 3) -> [TorrentStream] {
        Array(releases
            .filter { $0.id != stream.id && !$0.isDebrid && (assessments[$0.id]?.isPlayable ?? true) }
            .prefix(limit))
    }

    func bestStream(for episode: Episode?) async -> TorrentStream? {
        await rankedStreams(for: episode).first
    }

    /// The best sources to try in order (auto-pick and batch downloads): the
    /// one that played last time if it still has seeders, then by live health.
    func rankedStreams(for episode: Episode?, limit: Int = 4) async -> [TorrentStream] {
        let found = (try? await search.streams(
            id: mediaID, type: type,
            season: episode?.season, episode: episode?.episode)) ?? []
        let ranked = await rank(found)
        var ordered = ranked.streams.filter { ranked.assessments[$0.id]?.isPlayable ?? true }
        if ordered.isEmpty { ordered = ranked.streams }      // all quiet: still try the best
        if let last = SourceMemory.last(mediaID: mediaID, season: episode?.season, episode: episode?.episode),
           let index = ordered.firstIndex(where: { SourceKey.make($0) == last.sourceKey }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return Array(ordered.prefix(limit))
    }

    /// Asks the trackers who is sharing each source right now (about a
    /// quarter of a second, 2.5 s at most), then orders them by what will
    /// start and keep playing best.
    private func rank(_ streams: [TorrentStream]) async
        -> (streams: [TorrentStream], assessments: [String: SourceRanking.Assessment]) {
        var seen = Set<String>()
        let unique = streams.filter { seen.insert($0.id).inserted }
        let preferred = settings.preferredResolution
        let debridEnabled = settings.debridEnabled
        let runtime = SourceRanking.runtimeMinutes(detail?.runtime, isSeries: type != .movie)

        async let liveCounts = SwarmHealth.shared.check(unique)
        async let failedIDs = SwarmHealth.shared.failedIDs()
        let (live, failed) = await (liveCounts, failedIDs)

        var assessments: [String: SourceRanking.Assessment] = [:]
        for stream in unique {
            let key = stream.id.lowercased()
            let swarm = live[key]
            let facts = SourceRanking.Facts(
                listedSeeders: stream.seeders, liveSeeders: swarm?.seeders, liveLeechers: swarm?.leechers,
                resolution: stream.resolution, sizeBytes: SourceRanking.sizeBytes(stream.sizeText),
                isDebrid: stream.isDebrid, failedBefore: failed.contains(key))
            assessments[stream.id] = SourceRanking.assess(facts, preferredResolution: preferred,
                                                          runtimeMinutes: runtime, debridEnabled: debridEnabled)
        }
        let ordered = unique.enumerated().sorted { a, b in
            let left = assessments[a.element.id]?.score ?? 0
            let right = assessments[b.element.id]?.score ?? 0
            return left != right ? left > right : a.offset < b.offset
        }.map(\.element)
        return (ordered, assessments)
    }
}
