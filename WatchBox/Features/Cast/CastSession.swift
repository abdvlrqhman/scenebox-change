//
//  CastSession.swift
//  SceneBox
//

import Foundation
import Observation

// MARK: - Finding TVs

/// TVs and players on the Wi-Fi. Remembered ones show at once (checked in the
/// background); a search asks the network, then repeats while the list is
/// open, which also catches the moment the local-network permission is given.
@MainActor
@Observable
final class CastDiscovery {
    static let shared = CastDiscovery()

    struct Found: Identifiable, Equatable {
        let device: RendererDescription
        var isReachable: Bool
        var id: String { device.id }
    }

    private(set) var found: [Found] = []
    private(set) var isScanning = false
    private(set) var network: LocalNetwork.Interface?
    private(set) var manualMessage: String?
    private(set) var isAddingManually = false

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private static let rememberedKey = "SBCastDevices"

    private init() {}

    func startScanning() {
        guard loop == nil else { return }
        network = LocalNetwork.current()
        for device in Self.remembered() where !found.contains(where: { $0.id == device.id }) {
            found.append(Found(device: device, isReachable: false))
        }
        loop = Task { [weak self] in
            var round = 0
            while !Task.isCancelled {
                await self?.scan(probePorts: round == 0)
                round += 1
                try? await Task.sleep(for: .seconds(round == 1 ? 4 : 12))
            }
        }
    }

    func stopScanning() {
        loop?.cancel()
        loop = nil
        isScanning = false
    }

    private func scan(probePorts: Bool) async {
        network = LocalNetwork.current()
        isScanning = true
        defer { isScanning = false }
        // Remembered TVs first: one quick request each.
        await withTaskGroup(of: RendererDescription?.self) { group in
            for item in found where !item.isReachable {
                let location = item.device.location
                group.addTask { await Self.describe(location) }
            }
            for await device in group { if let device { add(device) } }
        }
        guard let network else { return }
        let hosts = LocalNetwork.neighbours(of: network.address, prefixLength: network.prefixLength)
        async let answers = Task.detached(priority: .userInitiated) { SSDPSearch.run(hosts: hosts) }.value
        async let samsung = Self.probeSamsung(probePorts ? hosts : [])
        let responses = await answers
        let extra = await samsung
        let locations = Set(responses.map(\.location) + extra)
        await withTaskGroup(of: RendererDescription?.self) { group in
            for location in locations where !found.contains(where: { $0.device.location == location && $0.isReachable }) {
                group.addTask { await Self.describe(location) }
            }
            for await device in group { if let device { add(device) } }
        }
    }

    /// "192.168.1.20", "192.168.1.20:9197" or a description address.
    func add(address raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isAddingManually = true
        manualMessage = nil
        defer { isAddingManually = false }
        var locations: [URL] = []
        if text.lowercased().hasPrefix("http"), let url = URL(string: text) {
            locations.append(url)
        } else {
            let host = text.split(separator: ":").first.map(String.init) ?? text
            let answers = await Task.detached(priority: .userInitiated) {
                SSDPSearch.run(hosts: [host], duration: 1.6)
            }.value
            locations += answers.map(\.location)
            locations += Self.knownDescriptionPaths.compactMap { URL(string: "http://\(host)\($0)") }
        }
        for location in locations {
            if let device = await Self.describe(location) {
                add(device)
                manualMessage = "Added \(device.name)."
                return
            }
        }
        manualMessage = "Nothing that plays video answered at \(text). Check the TV is on, on this Wi-Fi, and that sharing / DLNA is on in its settings."
    }

    func forget(_ device: RendererDescription) {
        found.removeAll { $0.id == device.id }
        Self.save(Self.remembered().filter { $0.id != device.id })
    }

    private func add(_ device: RendererDescription) {
        if let index = found.firstIndex(where: { $0.id == device.id }) {
            found[index] = Found(device: device, isReachable: true)
        } else {
            found.append(Found(device: device, isReachable: true))
        }
        found.sort { ($0.isReachable ? 0 : 1, $0.device.name) < ($1.isReachable ? 0 : 1, $1.device.name) }
        var saved = Self.remembered().filter { $0.id != device.id }
        saved.insert(device, at: 0)
        Self.save(Array(saved.prefix(12)))
    }

    // MARK: Network helpers

    /// Where TVs that don't answer direct searches keep their description:
    /// Samsung (Tizen and older), then common UPnP stacks.
    nonisolated static let knownDescriptionPaths = [":9197/dmr", ":7676/smp_2_", ":1150/", ":8080/description.xml"]

    nonisolated static func describe(_ location: URL, timeout: TimeInterval = 3) async -> RendererDescription? {
        var request = URLRequest(url: location)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UPnPDescription.parse(data, location: location)
    }

    /// Samsung TVs often ignore direct searches but serve their renderer at a
    /// fixed port: ask every neighbour, a few dozen at a time.
    nonisolated static func probeSamsung(_ hosts: [String]) async -> [URL] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var found: [URL] = []
        await withTaskGroup(of: URL?.self) { group in
            var next = 0
            func enqueue() {
                guard next < hosts.count, let url = URL(string: "http://\(hosts[next]):9197/dmr") else { return }
                next += 1
                group.addTask {
                    guard let (_, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return url
                }
            }
            for _ in 0..<min(48, hosts.count) { enqueue() }
            for await url in group {
                if let url { found.append(url) }
                enqueue()
            }
        }
        return found
    }

    private static func remembered() -> [RendererDescription] {
        guard let data = UserDefaults.standard.data(forKey: rememberedKey) else { return [] }
        return (try? JSONDecoder().decode([RendererDescription].self, from: data)) ?? []
    }

    private static func save(_ devices: [RendererDescription]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(devices), forKey: rememberedKey)
    }
}

// MARK: - A cast in progress

/// One video on one TV: loads it (with subtitles and from where the phone
/// was), keeps its position and state, and passes on play, pause and seek.
/// The phone's own player stays stopped meanwhile, so the two don't fight
/// over the stream.
@MainActor
@Observable
final class CastSession {
    enum Phase: Equatable {
        case idle
        case connecting
        case buffering
        case playing
        case paused
        case finished
        case failed(String)
    }

    struct Media {
        let source: URL            // torrent stream (127.0.0.1), file, or a remote address
        let title: String
        let durationSeconds: Double
    }

    private(set) var phase: Phase = .idle
    private(set) var device: RendererDescription?
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// The address to open on a computer, once the video is being served.
    private(set) var computerPageURL: URL?
    /// The subtitle file that went to the TV (nil: none).
    private(set) var sentSubtitleFile: URL?
    private(set) var isSendingSubtitles = false
    /// Goes up when a computer starts playing the video from the page, so the
    /// phone's own player can pause (two players would fight over the stream).
    private(set) var computerPlays = 0

    var isActive: Bool { device != nil }

    @ObservationIgnored private let server = CastServer()
    @ObservationIgnored private var media: Media?
    @ObservationIgnored private var fileExtension = "mkv"
    @ObservationIgnored private var size: Int64?
    @ObservationIgnored private var subtitles: (srt: Data, vtt: Data)?
    @ObservationIgnored private var controller: DLNAController?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    // MARK: Serving

    /// Starts serving `media` on the Wi-Fi. Returns false without a Wi-Fi
    /// (or hotspot) address.
    @discardableResult
    func prepare(_ media: Media, subtitleFile: URL?) async -> Bool {
        guard let network = LocalNetwork.current() else { return false }
        self.media = media
        if media.source.isFileURL {
            fileExtension = media.source.pathExtension.isEmpty ? "mkv" : media.source.pathExtension.lowercased()
            size = (try? media.source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        } else if media.source.host == "127.0.0.1" {
            (fileExtension, size) = await Self.inspect(media.source)
        } else {
            let ext = media.source.pathExtension.lowercased()
            fileExtension = ext.isEmpty || ext.count > 4 ? "mkv" : ext
        }
        sentSubtitleFile = subtitleFile
        subtitles = subtitleFile.flatMap(CastSubtitles.make)
        do {
            try await server.start(host: network.address)
        } catch {
            return false
        }
        await server.setOnVideoRequest { [weak self] in
            Task { @MainActor in
                guard let self, !self.isActive else { return }
                self.computerPlays += 1
            }
        }
        await server.update(content())
        computerPageURL = await server.baseURL
        return true
    }

    private func content() -> CastServer.Content {
        var source = CastServer.Source.file(URL(fileURLWithPath: "/dev/null"))
        if let url = media?.source {
            if url.isFileURL {
                source = .file(url)
            } else if url.host == "127.0.0.1" {
                source = .upstream(url)
            } else {
                source = .remote(url)          // a debrid link: the TV fetches it itself
            }
        }
        return CastServer.Content(source: source, fileExtension: fileExtension,
                                  title: media?.title ?? "SceneBox", subtitles: subtitles)
    }

    /// The torrent stream's type and size, from its answer to a HEAD request.
    private nonisolated static func inspect(_ url: URL) async -> (String, Int64?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return ("mkv", nil) }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let ext = type.contains("mp4") ? "mp4" : type.contains("webm") ? "webm"
            : type.contains("msvideo") ? "avi" : type.contains("quicktime") ? "mov" : "mkv"
        let size = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        return (ext, size)
    }

    // MARK: Casting

    func cast(to device: RendererDescription, from seconds: Double) async {
        guard let media, let video = await server.videoURL else {
            phase = .failed("Nothing to send yet.")
            return
        }
        pollTask?.cancel()
        generation += 1
        let current = generation
        self.device = device
        phase = .connecting
        position = seconds
        duration = media.durationSeconds
        let controller = DLNAController(device: device)
        self.controller = controller
        BackgroundDownloads.shared.setCasting(true)
        do {
            try await load(on: controller, video: video, media: media, at: seconds)
            guard current == generation else { return }
            startPolling(current)
        } catch {
            guard current == generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func load(on controller: DLNAController, video: URL, media: Media, at seconds: Double) async throws {
        let metadata = DLNA.didl(title: media.title, videoURL: video, mimeType: await server.videoMimeType,
                                 size: size, durationSeconds: media.durationSeconds > 0 ? media.durationSeconds : nil,
                                 subtitleURL: await server.subtitleURL)
        try? await controller.stop()                     // some TVs only take a new video when stopped
        try await controller.load(video, metadata: metadata)
        try await controller.play()
        // Pick up where the phone was, once the TV is actually playing.
        guard seconds > 5 else { return }
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(700))
            if (try? await controller.transportState()) == "PLAYING" { break }
        }
        try? await controller.seek(to: seconds)
    }

    private func startPolling(_ current: Int) {
        pollTask = Task { [weak self] in
            var failures = 0
            var stoppedTicks = 0
            var hasPlayed = false
            while !Task.isCancelled {
                guard let self, current == self.generation, let controller = self.controller else { return }
                do {
                    async let stateCall = controller.transportState()
                    async let positionCall = controller.position()
                    let (state, info) = try await (stateCall, positionCall)
                    failures = 0
                    if let position = info.position, position > 0 { self.position = position }
                    if let duration = info.duration, duration > 0 { self.duration = duration }
                    switch state {
                    case "PLAYING":
                        hasPlayed = true
                        stoppedTicks = 0
                        self.phase = .playing
                    case "PAUSED_PLAYBACK", "PAUSED":
                        self.phase = .paused
                    case "TRANSITIONING":
                        self.phase = .buffering
                    case "STOPPED", "NO_MEDIA_PRESENT":
                        stoppedTicks += 1
                        if hasPlayed, stoppedTicks >= 3 {
                            let nearEnd = self.duration > 0 && self.position > self.duration - 60
                            self.phase = nearEnd ? .finished : .failed("Stopped on the TV.")
                        } else if !hasPlayed, stoppedTicks > 20 {
                            self.phase = .failed("The TV didn't start the video. It may not play this format.")
                        } else if !hasPlayed {
                            self.phase = .buffering
                        }
                    default:
                        break
                    }
                } catch {
                    failures += 1
                    if failures >= 6 { self.phase = .failed("The TV stopped answering.") }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Controls

    func togglePause() {
        guard let controller else { return }
        let pausing = phase == .playing || phase == .buffering
        phase = pausing ? .paused : .playing
        Task {
            if pausing { try? await controller.pause() } else { try? await controller.play() }
        }
    }

    func seek(to seconds: Double) {
        guard let controller else { return }
        let target = max(0, duration > 0 ? min(seconds, duration - 1) : seconds)
        position = target
        Task { try? await controller.seek(to: target) }
    }

    func skip(by seconds: Double) { seek(to: position + seconds) }

    /// Sends the subtitles now showing on the phone, reloading at the same spot.
    func sendSubtitles(_ file: URL?) async {
        guard let device, let media, let video = await server.videoURL, let controller else { return }
        isSendingSubtitles = true
        defer { isSendingSubtitles = false }
        sentSubtitleFile = file
        subtitles = file.flatMap(CastSubtitles.make)
        await server.update(content())
        let resumeAt = position
        pollTask?.cancel()
        generation += 1
        let current = generation
        phase = .connecting
        do {
            try await load(on: controller, video: video, media: media, at: resumeAt)
            guard current == generation, self.device == device else { return }
            startPolling(current)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops the TV and returns where it got to, for the phone to go on from.
    func stop() async -> Double {
        pollTask?.cancel()
        generation += 1
        let reached = position
        if let controller { try? await controller.stop() }
        controller = nil
        device = nil
        phase = .idle
        BackgroundDownloads.shared.setCasting(false)
        return reached
    }

    /// The player is closing: the TV stops and the address goes away.
    func shutdown() {
        pollTask?.cancel()
        generation += 1
        if let controller { Task { try? await controller.stop() } }
        controller = nil
        device = nil
        phase = .idle
        computerPageURL = nil
        BackgroundDownloads.shared.setCasting(false)
        let server = server
        Task { await server.stop() }
    }
}
