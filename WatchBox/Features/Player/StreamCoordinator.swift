//
//  StreamCoordinator.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation
import Observation
#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class StreamCoordinator {
    struct Target: Identifiable, Equatable {
        let url: URL
        let title: String
        let showsTorrentStats: Bool
        var subtitleContext: SubtitleContext?
        var startPosition: Duration = .zero
        var progress: WatchProgressContext?
        var originalAudioLanguage: String?

        var id: URL { url }
    }

    private(set) var isPresenting = false
    private(set) var target: Target?
    private(set) var preparing: String?
    private(set) var bufferProgress: Double?
    private(set) var errorMessage: String?

    private(set) var title = ""
    private(set) var backdropURL: URL?
    private(set) var logoURL: URL?

    private(set) var episodePlaylist: EpisodePlaylist?

    private(set) var stats = SwarmStats()
    /// Enough is downloaded to begin; the loading screen offers "Play now".
    private(set) var canStartNow = false

    @ObservationIgnored private var session: LibtorrentSession?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var streamDirectory: URL?
    @ObservationIgnored private var startNowRequested = false
    @ObservationIgnored private var reservedTorrent: String?
    @ObservationIgnored private let settings: AppSettings

    static var streamCacheRoot: URL { StreamCache.root }

    static func pruneCacheAtLaunch() {
        StreamCache.removeLegacyLocation()
        let limit = AppSettings.shared.streamCacheLimitBytes
        limit > 0 ? StreamCache.prune(toBytes: limit) : StreamCache.clear()
    }

    static func purgeStreamCache() { StreamCache.clear() }

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
    }

    deinit {
        prepareTask?.cancel()
        statsTask?.cancel()
    }

    var isPreparing: Bool { preparing != nil }

    /// Skip the rest of the cushion and start with what's downloaded.
    func startNow() { startNowRequested = true }

    var preparingStatus: String? {
        if let preparing { return preparing }
        guard bufferProgress != nil, errorMessage == nil else { return nil }
        guard stats.connectedPeers > 0 else { return "Connecting to sources…" }
        return "\(stats.connectedPeers) source\(stats.connectedPeers == 1 ? "" : "s") · \(ByteFormat.rate(stats.downloadRate))"
    }

    func play(_ stream: TorrentStream, title: String, backdropURL: URL?, logoURL: URL? = nil,
              subtitleContext: SubtitleContext? = nil, episodes: EpisodePlaylist? = nil,
              startAt: Duration = .zero, resumeFraction: Double? = nil,
              progress: WatchProgressContext? = nil,
              originalAudioLanguage: String? = nil,
              fallbacks: [TorrentStream] = []) {
        let subtitleContext = subtitleContext?.withRelease(stream.title).withSource(SourceKey.make(stream))
        prefetchSubtitles(subtitleContext)
        episodePlaylist = episodes
        prepareTask?.cancel()
        let previousSession = session
        let previousDirectory = streamDirectory
        session = nil
        streamDirectory = nil

        self.title = title
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.errorMessage = nil
        self.target = nil
        self.stats = SwarmStats()
        self.preparing = "Fetching sources from peers…"
        self.bufferProgress = nil
        self.isPresenting = true

        prepareTask = Task { [settings] in
            await previousSession?.stop()
            let cacheLimit = settings.streamCacheLimitBytes
            let directory = Self.streamCacheRoot
                .appendingPathComponent(stream.id, isDirectory: true)
            if cacheLimit <= 0 || previousDirectory == directory {
                await previousSession?.waitForTeardown()
            }
            if cacheLimit <= 0, let previousDirectory {
                try? FileManager.default.removeItem(at: previousDirectory)
            }
            guard !Task.isCancelled else { return }
            do {
                // One engine per torrent: park any download of the same season
                // pack while it streams, and hand it back afterwards.
                let key = stream.id.lowercased()
                if let previous = self.reservedTorrent, previous != key {
                    DownloadStore.shared.endStreaming(infoHash: previous)
                }
                self.reservedTorrent = key
                await DownloadStore.shared.reserveForStreaming(infoHash: key)
                guard !Task.isCancelled else { return }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                self.streamDirectory = directory
                if cacheLimit > 0 { StreamCache.prune(toBytes: cacheLimit, keeping: [stream.id]) }

                let session = try await LibtorrentSession.resolve(
                    magnet: stream.magnet,
                    downloadDirectory: directory,
                    preferredFileIndex: stream.fileIndex,
                    maxPeers: settings.maxPeers,
                    extraTrackers: settings.customTrackerURLs)
                guard !Task.isCancelled else { await session.stop(); return }
                self.session = session

                preparing = "Starting stream…"
                let url = try await session.startStreaming(port: UInt16(settings.streamingPort),
                                                           resumeFraction: resumeFraction)
                guard !Task.isCancelled else { await session.stop(); return }

                let started = Date()
                preparing = nil
                var lastBytes: Int64 = 0
                var lastProgressAt = Date()
                var readyToStart = false
                var minimumReadyAt: Date?
                startNowRequested = false
                canStartNow = false

                // Start as soon as the video can play, not after a fixed download:
                // the container header plus a few megabytes at the start point,
                // and either a comfortable cushion or a download fast enough to
                // stay ahead of playback. The stream server keeps fetching ahead
                // of the playhead, and everything fetched stays cached.
                let fileLength = await session.streamFileLength()
                let megabyte: Int64 = 1_048_576
                let startOffset: Int64 = resumeFraction.map { fraction in
                    fraction > 0 && fraction < 1 ? Int64(Double(fileLength) * fraction) : 0
                } ?? 0
                let headerBytes = min(fileLength, 2 * megabyte)
                let minimumBytes = min(fileLength - startOffset, 4 * megabyte)
                let cushionBytes = min(fileLength - startOffset,
                                       max(8 * megabyte, min(24 * megabyte, fileLength / 80)))
                // Bytes per second if the file were a ~45 minute episode; longer
                // films come out lower, which only makes the estimate cautious.
                let estimatedBitrate = Double(max(fileLength, 1)) / (45 * 60)

                while !Task.isCancelled {
                    let header = await session.contiguousBytes(from: 0, limit: headerBytes)
                    let ahead = await session.contiguousBytes(from: startOffset, limit: cushionBytes)
                    let stats = await session.currentStats()
                    self.stats = stats
                    bufferProgress = cushionBytes > 0 ? Double(ahead) / Double(cushionBytes) : 1
                    if stats.downloadedBytes > lastBytes {
                        lastBytes = stats.downloadedBytes
                        lastProgressAt = Date()
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    let stalledFor = Date().timeIntervalSince(lastProgressAt)

                    let minimumReady = header >= headerBytes && ahead >= minimumBytes
                    canStartNow = minimumReady
                    if minimumReady {
                        let since = Date().timeIntervalSince(minimumReadyAt ?? Date())
                        if minimumReadyAt == nil { minimumReadyAt = Date() }
                        let keepingUp = stats.downloadRate >= estimatedBitrate * 1.3
                        if ahead >= cushionBytes || keepingUp || startNowRequested || since >= 8 {
                            readyToStart = true
                            break
                        }
                    }
                    #if DEBUG
                    if Int(elapsed * 3.3) % 3 == 0 {   // ~1 line/sec of the 300ms loop
                        torrentLog.notice("gate: elapsed=\(Int(elapsed), privacy: .public)s header=\(header / megabyte, privacy: .public)MB ahead=\(ahead / megabyte, privacy: .public)MB rate=\(Int(stats.downloadRate / 1024), privacy: .public)KB/s")
                    }
                    #endif
                    if elapsed > 300 { break }                   // absolute ceiling: 5 min
                    if lastBytes == 0 {
                        if elapsed > 120 && stats.connectedPeers == 0 { break }
                    } else if stalledFor > 90 {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                canStartNow = false
                guard !Task.isCancelled else { await session.stop(); return }
                if !readyToStart {
                    await session.stop()
                    self.session = nil
                    throw TorrentEngineError.bufferTimeout
                }
                await session.endPrebuffer()

                // This source works: remember it for the episode's source list.
                if let progress {
                    SourceMemory.remember(stream, mediaID: progress.mediaID,
                                          season: progress.season, episode: progress.episode)
                }
                target = Target(url: url, title: title, showsTorrentStats: true,
                                subtitleContext: subtitleContext,
                                startPosition: startAt, progress: progress,
                                originalAudioLanguage: originalAudioLanguage)
                preparing = nil
                pollStats(from: session)
            } catch {
                guard !Task.isCancelled else { return }
                if let engineError = error as? TorrentEngineError,
                   engineError == .metadataTimeout || engineError == .bufferTimeout,
                   let next = fallbacks.first {
                    preparing = "Source unresponsive — trying another…"
                    Task { @MainActor [self] in
                        play(next, title: title, backdropURL: backdropURL, logoURL: logoURL,
                             subtitleContext: subtitleContext, episodes: episodes,
                             startAt: startAt, resumeFraction: resumeFraction,
                             progress: progress, originalAudioLanguage: originalAudioLanguage,
                             fallbacks: Array(fallbacks.dropFirst()))
                    }
                    return
                }
                preparing = nil
                errorMessage = friendlyError(error)
            }
        }
    }

    func playDebrid(url: URL, title: String, backdropURL: URL?, logoURL: URL? = nil,
                    subtitleContext: SubtitleContext? = nil, episodes: EpisodePlaylist? = nil,
                    startAt: Duration = .zero, progress: WatchProgressContext? = nil,
                    originalAudioLanguage: String? = nil) {
        prefetchSubtitles(subtitleContext)
        episodePlaylist = episodes
        prepareTask?.cancel()
        self.title = title
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.errorMessage = nil
        self.preparing = nil
        self.stats = SwarmStats()
        self.isPresenting = true
        self.target = Target(url: url, title: title, showsTorrentStats: false,
                             subtitleContext: subtitleContext,
                             startPosition: startAt, progress: progress,
                             originalAudioLanguage: originalAudioLanguage)
    }

    func playLocalFile(at url: URL, title: String, subtitleContext: SubtitleContext? = nil,
                       startAt: Duration = .zero, progress: WatchProgressContext? = nil,
                       originalAudioLanguage: String? = nil) {
        prefetchSubtitles(subtitleContext)
        episodePlaylist = nil
        self.title = title
        self.backdropURL = nil
        self.logoURL = nil
        self.errorMessage = nil
        self.preparing = nil
        self.isPresenting = true
        self.target = Target(url: url, title: title, showsTorrentStats: false,
                             subtitleContext: subtitleContext,
                             startPosition: startAt, progress: progress,
                             originalAudioLanguage: originalAudioLanguage)
    }

    /// Starts fetching the default-language subtitle while the stream buffers,
    /// so it is ready the moment the video starts.
    private func prefetchSubtitles(_ context: SubtitleContext?) {
        guard let context else { return }
        // What this source used last time, else this episode's language, else the default.
        let memory = SubtitleMemory.entry(for: context)
        var preferredID: String?
        if let key = memory?.trackKey, key.hasPrefix("ext:") { preferredID = String(key.dropFirst(4)) }
        let language = memory?.language ?? SubtitleMemory.episodeLanguage(for: context)
            ?? settings.preferredSubtitleLanguage
        guard !language.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            await SubtitlesProvider.shared.prefetch(context: context, preferredLanguage: language,
                                                    preferredID: preferredID)
        }
    }

    func stop() {
        prepareTask?.cancel(); prepareTask = nil
        statsTask?.cancel(); statsTask = nil
        preparing = nil
        bufferProgress = nil
        errorMessage = nil
        target = nil
        backdropURL = nil
        logoURL = nil
        episodePlaylist = nil
        isPresenting = false
        stats = SwarmStats()

        let finished = session
        let directory = streamDirectory
        let cacheLimit = settings.streamCacheLimitBytes
        let reserved = reservedTorrent
        session = nil
        streamDirectory = nil
        reservedTorrent = nil
        canStartNow = false
        Task {
            await finished?.stop()
            await finished?.waitForTeardown()       // don't delete, or restart a download, under the engine
            if cacheLimit <= 0 {
                if let directory { try? FileManager.default.removeItem(at: directory) }
            } else {
                StreamCache.prune(toBytes: cacheLimit)
            }
            if let reserved { DownloadStore.shared.endStreaming(infoHash: reserved) }
        }
    }

    private func pollStats(from session: LibtorrentSession) {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let current = await session.currentStats()
                guard !Task.isCancelled, let self else { return }
                self.stats = current
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let engineError = error as? TorrentEngineError {
            switch engineError {
            case .failedToStart:
                return "This torrent link could not be started. Try a different source."
            case .metadataTimeout:
                return "Couldn’t reach enough peers for this release. Try a different source; one with more seeders usually connects faster."
            case .noPlayableFile:
                return "This release has no playable video file."
            case .bufferTimeout:
                return "This release isn’t serving data — no seeders reachable right now. Try another source with more seeders."
            }
        }
        return error.localizedDescription
    }
}
