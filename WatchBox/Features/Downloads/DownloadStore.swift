//
//  DownloadStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadStore {
    static let shared = DownloadStore()

    private(set) var downloads: [Download] = []
    private(set) var diskUsage: Int64 = 0

    @ObservationIgnored private let root: URL
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var startTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastDiskSample = Date.distantPast
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    private(set) var isOnCellular = false
    @ObservationIgnored private var waitingForWiFi: Set<String> = []
    /// Torrents whose engine is still shutting down. libtorrent removes a
    /// torrent asynchronously, so the next episode of the same pack waits.
    @ObservationIgnored private var retiringTorrents: [String: Int] = [:]
    @ObservationIgnored private var metadataRetries: [String: Int] = [:]
    @ObservationIgnored private var lastCheckpoint = Date()

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
        let documents = AppDirectories.documents
        root = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        BackupExclusion.exclude(root)
        load()
        refreshDiskUsage()
        pollTask = Task { await pollForever() }
        startPathMonitor()
        startQueuedDownloads()
    }

    // MARK: - Wi-Fi only

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
                && !path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in self?.pathChanged(isCellular: cellular || path.isExpensive) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "downloads.path"))
    }

    private func pathChanged(isCellular: Bool) {
        guard isCellular != isOnCellular else { return }
        isOnCellular = isCellular
        guard settings.wifiOnly else { return }
        if isCellular {
            for download in downloads where download.phase.isPending {
                waitingForWiFi.insert(download.id)
                stopTransfer(download, phase: .paused)
                download.failureMessage = Self.waitingForWiFiMessage
            }
        } else {
            let resume = waitingForWiFi
            waitingForWiFi.removeAll()
            for download in downloads where resume.contains(download.id) {
                download.failureMessage = nil
                enqueue(download)
            }
            startQueuedDownloads()
        }
    }

    private var blockedByWiFiOnly: Bool { settings.wifiOnly && isOnCellular }
    private static let waitingForWiFiMessage = "Waiting for Wi-Fi"

    // MARK: - Library

    /// Queued plus transferring: the Library badge and the background keeper use it.
    var activeCount: Int { downloads.filter { $0.phase.isPending }.count }

    var hasPendingWork: Bool { downloads.contains { $0.phase.isPending } }

    func contains(infoHash: String, episodeLabel: String? = nil) -> Bool {
        let key = infoHash.lowercased()
        return downloads.contains { $0.record.torrentKey == key && $0.record.episodeLabel == episodeLabel }
    }

    /// Any download (finished or not) for this movie or episode.
    func download(mediaID: String, episodeLabel: String?) -> Download? {
        downloads.first { $0.record.mediaID == mediaID && $0.record.episodeLabel == episodeLabel }
    }

    func completedDownload(mediaID: String, episodeLabel: String?) -> Download? {
        downloads.first {
            $0.record.mediaID == mediaID
                && $0.record.episodeLabel == episodeLabel
                && ($0.phase == .completed || $0.record.isComplete)
        }
    }

    func isDownloaded(mediaID: String, episodeLabel: String? = nil) -> Bool {
        completedDownload(mediaID: mediaID, episodeLabel: episodeLabel) != nil
    }

    @discardableResult
    func add(stream: TorrentStream, title: String, mediaID: String, mediaType: MediaType,
             posterURL: URL?, episode: Episode? = nil) -> Download {
        let id = DownloadRecord.makeID(infoHash: stream.id, episodeLabel: episode?.label)
        if let existing = downloads.first(where: { $0.id == id }) {
            if existing.phase == .paused || existing.phase == .failed { resume(existing) }
            return existing
        }

        let record = DownloadRecord(
            id: id,
            title: title,
            releaseName: stream.displayName,
            mediaID: mediaID,
            mediaType: mediaType.rawValue,
            posterURLString: posterURL?.absoluteString,
            episodeLabel: episode?.label,
            magnetURI: stream.isDebrid ? "" : stream.magnet.magnetURI,
            fileIndex: stream.fileIndex,
            totalBytes: stream.isDebrid ? 0 : (stream.sizeText.flatMap(ByteFormat.bytes(fromSizeText:)) ?? 0),
            isComplete: false,
            addedAt: Date(),
            debridURLString: stream.url?.absoluteString,
            debridFileName: stream.url.map { Self.fileName(from: $0, title: title) },
            infoHash: stream.id.lowercased()
        )
        let download = Download(record: record, phase: .paused)
        downloads.insert(download, at: 0)
        resume(download)
        if let context = record.subtitleContext {
            let language = settings.preferredSubtitleLanguage
            Task.detached(priority: .utility) {
                await SubtitlesProvider.shared.prefetch(context: context, preferredLanguage: language)
            }
        }
        return download
    }

    /// User asked for this download to run: queue it and start what fits.
    func resume(_ download: Download) {
        guard download.phase == .paused || download.phase == .failed else { return }
        metadataRetries[download.id] = nil
        if blockedByWiFiOnly {
            waitingForWiFi.insert(download.id)
            download.record.wantsRunning = true
            download.phase = .paused
            download.failureMessage = Self.waitingForWiFiMessage
            save()
            return
        }
        download.failureMessage = nil
        enqueue(download)
        startQueuedDownloads()
        BackgroundDownloads.shared.userStartedDownloads()
    }

    func resumeAll() {
        for download in downloads where download.phase == .paused || download.phase == .failed {
            resume(download)
        }
    }

    func pauseAll() {
        for download in downloads where download.phase.isPending { pause(download) }
    }

    private func enqueue(_ download: Download) {
        download.phase = .queued
        download.record.wantsRunning = true
        save()
    }

    // MARK: - Queue

    /// Starts queued downloads, oldest first, up to the simultaneous limit.
    /// Episodes of one season pack share a torrent, so only one of them
    /// transfers at a time; the others wait their turn.
    private func startQueuedDownloads() {
        let limit = max(1, settings.maxSimultaneousDownloads)
        var running = downloads.filter { $0.phase.isActive }.count
        for download in downloads.reversed() where download.phase == .queued {
            guard running < limit else { break }
            if !download.record.isDebrid, let blocker = torrentBlocker(for: download) {
                download.failureMessage = blocker
                continue
            }
            download.failureMessage = nil
            start(download)
            if download.phase.isActive { running += 1 }
        }
        for download in downloads where download.phase == .queued && download.failureMessage == nil {
            if !download.record.isDebrid, let blocker = torrentBlocker(for: download) {
                download.failureMessage = blocker
            }
        }
    }

    private func torrentBlocker(for download: Download) -> String? {
        let key = download.record.torrentKey
        if let busy = downloads.first(where: {
            $0.id != download.id && !$0.record.isDebrid && $0.record.torrentKey == key && $0.phase.isActive
        }) {
            return "Queued · after \(busy.record.episodeLabel ?? busy.record.title) (same torrent)"
        }
        if retiringTorrents[key] != nil { return "Queued · starting soon" }
        return nil
    }

    private func start(_ download: Download) {
        guard hasRoomForMoreDownloads else {
            download.phase = .failed
            download.record.wantsRunning = false
            download.failureMessage = DownloadError.storageCapReached.errorDescription
            save()
            return
        }

        if download.record.isDebrid {
            resumeDebrid(download)
            return
        }

        guard startTasks[download.id] == nil else { return }

        download.phase = .resolving

        startTasks[download.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.startTasks[download.id] = nil }
            do {
                let session = try await self.makeSession(for: download)
                guard download.phase == .resolving else {
                    self.retire(session, key: download.record.torrentKey)   // paused while resolving
                    return
                }
                download.session = session
                download.phase = .downloading
                await session.startDownload()
            } catch is CancellationError {
                return
            } catch {
                guard download.phase == .resolving else { return }
                self.handleStartFailure(download, error: error)
            }
        }
    }

    /// Metadata lookups time out now and then (few peers, or iOS briefly cut
    /// the network). Retry a couple of times before giving up.
    private func handleStartFailure(_ download: Download, error: Error) {
        let attempts = metadataRetries[download.id, default: 0]
        if case TorrentEngineError.metadataTimeout = error, attempts < 2 {
            metadataRetries[download.id] = attempts + 1
            download.phase = .queued
            download.failureMessage = "Retrying… no peers answered yet"
            markRetiring(download.record.torrentKey, for: .seconds(3))
            return
        }
        download.phase = .failed
        download.record.wantsRunning = false
        download.failureMessage = error.localizedDescription
        save()
        startQueuedDownloads()
    }

    // MARK: - Debrid (direct HTTP) downloads

    private func resumeDebrid(_ download: Download) {
        guard download.debridDownloader == nil else { return }
        guard let url = download.record.debridURL else {
            download.phase = .failed
            download.record.wantsRunning = false
            download.failureMessage = "This release has no debrid link."
            save()
            return
        }
        download.failureMessage = nil
        download.phase = .downloading
        download.rateSample = (download.downloadedBytes, Date())

        let id = download.id
        let downloader = DebridDownloader(
            destination: debridFileURL(for: download.record),
            onProgress: { progress in
                Task { @MainActor [weak self] in self?.applyDebridProgress(id: id, progress: progress) }
            },
            onComplete: { result in
                Task { @MainActor [weak self] in self?.finishDebrid(id: id, result: result) }
            })
        download.debridDownloader = downloader
        downloader.start(url: url)
    }

    private func applyDebridProgress(id: String, progress: DebridDownloader.Progress) {
        guard let download = downloads.first(where: { $0.id == id }), download.phase == .downloading else { return }
        download.downloadedBytes = progress.downloadedBytes
        if progress.totalBytes > 0, download.record.totalBytes == 0 {
            download.record.totalBytes = progress.totalBytes
            save()
        }
        let total = download.record.totalBytes
        download.progress = total > 0 ? min(1, Double(progress.downloadedBytes) / Double(total)) : 0

        let now = Date()
        if let sample = download.rateSample, now.timeIntervalSince(sample.at) >= 0.5 {
            let dt = now.timeIntervalSince(sample.at)
            let instant = Double(progress.downloadedBytes - sample.bytes) / dt
            download.downloadRate = 0.5 * download.downloadRate + 0.5 * max(0, instant)
            download.rateSample = (progress.downloadedBytes, now)
        }
    }

    private func finishDebrid(id: String, result: Result<URL, Error>) {
        guard let download = downloads.first(where: { $0.id == id }) else { return }
        download.debridDownloader = nil
        guard download.phase == .downloading else { return }
        switch result {
        case .success:
            download.phase = .completed
            download.progress = 1
            download.downloadRate = 0
            download.record.isComplete = true
            download.record.wantsRunning = false
            if download.record.totalBytes == 0 { download.record.totalBytes = download.downloadedBytes }
        case .failure(let error):
            download.phase = .failed
            download.record.wantsRunning = false
            download.failureMessage = error.localizedDescription
        }
        save()
        startQueuedDownloads()
    }

    private func debridFileURL(for record: DownloadRecord) -> URL {
        folder(for: record.id).appendingPathComponent(record.debridFileName ?? "video.mp4")
    }

    private static func fileName(from url: URL, title: String) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, (last as NSString).pathExtension.isEmpty == false { return last }
        return title.replacingOccurrences(of: "/", with: "-") + ".mp4"
    }

    // MARK: - Lifecycle

    /// User paused (or dequeued) this download.
    func pause(_ download: Download) {
        waitingForWiFi.remove(download.id)
        download.failureMessage = nil
        download.record.wantsRunning = false
        stopTransfer(download, phase: .paused)
        save()
        startQueuedDownloads()
    }

    /// Stops any transfer in flight and parks the download in `phase`.
    private func stopTransfer(_ download: Download, phase: Download.Phase) {
        if download.record.isDebrid {
            download.debridDownloader?.cancel()
            download.debridDownloader = nil
        }
        if let resolving = startTasks[download.id] {
            resolving.cancel()
            startTasks[download.id] = nil
            // The half-started engine shuts down on its own; give it a moment
            // before another episode of the same torrent starts.
            markRetiring(download.record.torrentKey, for: .milliseconds(1500))
        }
        download.phase = phase
        download.downloadRate = 0
        download.connectedPeers = 0

        let session = download.session
        download.session = nil
        retire(session, key: download.record.torrentKey)
    }

    /// Stops an engine and keeps its torrent marked busy until libtorrent has
    /// really let go of it.
    private func retire(_ session: LibtorrentSession?, key: String, then cleanup: (@MainActor () -> Void)? = nil) {
        guard let session else { cleanup?(); return }
        retiringTorrents[key, default: 0] += 1
        Task { [weak self] in
            await session.stop()
            await session.waitForTeardown()
            cleanup?()
            try? await Task.sleep(for: .milliseconds(1500))
            self?.releaseRetiring(key)
        }
    }

    private func markRetiring(_ key: String, for delay: Duration) {
        retiringTorrents[key, default: 0] += 1
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.releaseRetiring(key)
        }
    }

    private func releaseRetiring(_ key: String) {
        if let count = retiringTorrents[key], count > 1 {
            retiringTorrents[key] = count - 1
        } else {
            retiringTorrents[key] = nil
        }
        startQueuedDownloads()
    }

    func remove(_ download: Download) {
        waitingForWiFi.remove(download.id)
        metadataRetries[download.id] = nil
        download.debridDownloader?.cancel()
        download.debridDownloader = nil
        startTasks[download.id]?.cancel()
        startTasks[download.id] = nil

        let session = download.session
        download.session = nil
        let directory = folder(for: download.id)
        downloads.removeAll { $0.id == download.id }
        save()

        if session == nil {
            try? FileManager.default.removeItem(at: directory)
            refreshDiskUsage()
            startQueuedDownloads()
        } else {
            retire(session, key: download.record.torrentKey) { [weak self] in
                try? FileManager.default.removeItem(at: directory)   // not under a live engine
                self?.refreshDiskUsage()
            }
        }
    }

    func localFileURL(for download: Download) async -> URL? {
        guard download.phase == .completed else { return nil }
        if download.record.isDebrid {
            let url = debridFileURL(for: download.record)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let relative = download.record.localRelativePath {
            let url = folder(for: download.id).appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let session = download.session {
            let url = await session.localFileURL()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    // MARK: - Background

    /// Saves resume data for every running torrent. Called when the app leaves
    /// the screen, in case iOS ends it later.
    func checkpointAll() async {
        lastCheckpoint = Date()
        let sessions = downloads.compactMap(\.session)
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { await session.checkpoint() }
            }
        }
    }

    /// Bytes done / bytes wanted across queued and running downloads, for the
    /// system progress UI.
    func aggregateProgress(for ids: Set<String>) -> (done: Int64, total: Int64) {
        var done: Int64 = 0, total: Int64 = 0
        for download in downloads where ids.contains(download.id) {
            let size = max(download.record.totalBytes, download.downloadedBytes)
            total += size
            done += download.phase == .completed
                ? size
                : Int64(min(max(download.progress, 0), 1) * Double(size))
        }
        return (done, total)
    }

    var pendingIDs: Set<String> { Set(downloads.filter { $0.phase.isPending }.map(\.id)) }

    // MARK: - Storage accounting

    func refreshDiskUsage() {
        lastDiskSample = Date()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []
        ) else { diskUsage = 0; return }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let allocated = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
            total += Int64(allocated ?? 0)
        }
        diskUsage = total
    }

    var hasRoomForMoreDownloads: Bool {
        settings.storageCapBytes <= 0 || diskUsage < settings.storageCapBytes
    }

    func removeAll() {
        for download in downloads {
            startTasks[download.id]?.cancel()
            download.debridDownloader?.cancel()
            download.debridDownloader = nil
            let session = download.session
            download.session = nil
            Task { await session?.stop() }
        }
        startTasks.removeAll()
        waitingForWiFi.removeAll()
        metadataRetries.removeAll()
        downloads.removeAll()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        save()
        refreshDiskUsage()
    }

    // MARK: - Sessions

    private func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func makeSession(for download: Download) async throws -> LibtorrentSession {
        let directory = folder(for: download.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let magnet = download.record.magnet else { throw DownloadError.badMagnet }
        return try await LibtorrentSession.resolve(
            magnet: magnet, downloadDirectory: directory,
            preferredFileIndex: download.record.fileIndex,
            maxPeers: settings.maxPeers, extraTrackers: settings.customTrackerURLs)
    }

    // MARK: - Polling

    private func pollForever() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            var needsSave = false
            var finished = false
            for download in downloads where download.phase == .downloading {
                guard let session = download.session else { continue }
                let stats = await session.currentStats()
                guard download.phase == .downloading, download.session != nil else { continue }

                if download.record.totalBytes == 0 {
                    download.record.totalBytes = await session.streamFileLength()
                    needsSave = true
                }
                if download.record.localRelativePath == nil {
                    download.record.localRelativePath = await session.localRelativePath()
                    needsSave = true
                }

                download.downloadedBytes = stats.downloadedBytes
                download.downloadRate = stats.downloadRate
                download.connectedPeers = stats.connectedPeers

                download.progress = stats.progress

                if stats.isComplete {
                    download.phase = .completed
                    download.progress = 1
                    download.downloadRate = 0
                    download.record.isComplete = true
                    download.record.wantsRunning = false
                    download.session = nil
                    needsSave = true
                    finished = true
                    retire(session, key: download.record.torrentKey)
                }
            }
            if needsSave { save() }
            if finished { startQueuedDownloads() }

            if downloads.contains(where: { $0.phase.isActive }) {
                if Date().timeIntervalSince(lastDiskSample) >= 2 { refreshDiskUsage() }
                if Date().timeIntervalSince(lastCheckpoint) >= 120 {
                    Task { await checkpointAll() }
                }
            }
            BackgroundDownloads.shared.downloadsDidUpdate()
        }
    }

    // MARK: - Persistence

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data)
        else { return }

        // Downloads that were running when the app last closed (or iOS ended
        // it) go straight back into the queue.
        downloads = records.map {
            let phase: Download.Phase = $0.isComplete ? .completed : ($0.wantsRunning == true ? .queued : .paused)
            return Download(record: $0, phase: phase)
        }
    }

    private func save() {
        let records = downloads.map(\.record)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
