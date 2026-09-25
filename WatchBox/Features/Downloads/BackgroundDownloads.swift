//
//  BackgroundDownloads.swift
//  SceneBox
//

import Foundation
import AVFoundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import BackgroundTasks
#endif

/// Keeps torrent downloads running after the user leaves the app.
///
/// iOS suspends an app a few seconds after it leaves the screen. A suspended
/// app's sockets go quiet, so every peer drops and the download stalls until
/// the app is opened again. Two layers keep SceneBox awake while downloads are
/// queued or running:
///
/// 1. **Audio keep-alive** (every iOS version; the approach iTorrent ships).
///    The app already declares the `audio` background mode. A silent, mixable
///    audio session keeps it running without interrupting the user's music.
///    *Smart* plays a short pulse every few seconds and renews a background task
///    each time; *Always-on* loops silence for as long as downloads run.
/// 2. **Continued processing task** (iOS 26+). Apple's API for work a person
///    started that should finish in the background; the system shows its
///    progress in a Live Activity. It expires when progress stalls for about
///    30 seconds, which torrents do while looking for peers, so it is an
///    extra on top of the keep-alive rather than something downloads rely on.
@MainActor
final class BackgroundDownloads {
    static let shared = BackgroundDownloads()

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private let settings = AppSettings.shared
    private var isInBackground = false
    private var keepAlive: AudioKeepAlive?
    private var checkpointTask: UIBackgroundTaskIdentifier = .invalid
    private var started = false
    private var processing: AnyObject?

    private init() {}

    /// Call once at launch.
    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundDownloads.shared.didEnterBackground() }
        }
        _ = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundDownloads.shared.willEnterForeground() }
        }
    }

    /// A tap started or resumed downloads. The system only accepts a continued
    /// processing task in response to a person's action, while in the foreground.
    func userStartedDownloads() {
        guard settings.downloadLiveActivity,
              UIApplication.shared.applicationState == .active else { return }
        if #available(iOS 26.0, *) {
            let task = (processing as? DownloadProcessingTask) ?? DownloadProcessingTask()
            processing = task
            task.include(DownloadStore.shared.pendingIDs)
        }
    }

    /// Called by the download store on every progress tick.
    func downloadsDidUpdate() {
        if #available(iOS 26.0, *), let task = processing as? DownloadProcessingTask {
            if !settings.downloadLiveActivity { task.finish(success: false) }
            task.update()
            if task.isDone { processing = nil }
        }
        updateKeepAlive()
    }

    private func didEnterBackground() {
        isInBackground = true
        updateKeepAlive()
        guard DownloadStore.shared.hasPendingWork else { return }
        // Save resume data while we still have time, in case iOS ends the app.
        endCheckpointTask()
        checkpointTask = UIApplication.shared.beginBackgroundTask(withName: "SceneBox.checkpoint") {
            MainActor.assumeIsolated { BackgroundDownloads.shared.endCheckpointTask() }
        }
        Task {
            await DownloadStore.shared.checkpointAll()
            endCheckpointTask()
        }
    }

    private func willEnterForeground() {
        isInBackground = false
        updateKeepAlive()
    }

    // System callbacks arrive on the main queue; they're routed through the
    // singleton so no closure has to capture an object across isolation.
    fileprivate func keepAliveNeedsRestart() { keepAlive?.restart() }
    fileprivate func audioServicesReset() { keepAlive?.reset() }

    @available(iOS 26.0, *)
    fileprivate func processingTaskLaunched(_ task: BGContinuedProcessingTask) {
        if let processing = processing as? DownloadProcessingTask {
            processing.attach(task)
        } else {
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 26.0, *)
    fileprivate func processingTaskExpired() {
        (processing as? DownloadProcessingTask)?.finish(success: false)
    }

    private func endCheckpointTask() {
        guard checkpointTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(checkpointTask)
        checkpointTask = .invalid
    }

    /// A TV is playing from the phone: the phone has to keep serving the
    /// video with the screen off, so the silent audio runs the whole time.
    func setCasting(_ casting: Bool) {
        guard isCasting != casting else { return }
        isCasting = casting
        updateKeepAlive()
    }

    private var isCasting = false

    private func updateKeepAlive() {
        let downloadMode = settings.backgroundDownloadMode
        let mode: BackgroundDownloadMode = isCasting ? .continuous : downloadMode
        let needed = isInBackground
            && (isCasting || (downloadMode != .off && DownloadStore.shared.hasPendingWork))
        if needed {
            if let keepAlive, keepAlive.mode == mode { return }
            keepAlive?.stop()
            let fresh = AudioKeepAlive(mode: mode)
            keepAlive = fresh
            fresh.start()
        } else if let keepAlive {
            keepAlive.stop()
            self.keepAlive = nil
        }
    }
    #else
    private init() {}
    func start() {}
    func userStartedDownloads() {}
    func downloadsDidUpdate() {}
    func setCasting(_ casting: Bool) {}
    #endif
}

#if os(iOS) && !targetEnvironment(macCatalyst)

// MARK: - Audio keep-alive

/// Holds the app awake with inaudible audio. Uses the `audio` background mode
/// the app already declares for video playback.
@MainActor
private final class AudioKeepAlive {
    let mode: BackgroundDownloadMode
    private var player: AVAudioPlayer?
    private var loop: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private var activatedSession = false
    private var stopped = false

    init(mode: BackgroundDownloadMode) {
        self.mode = mode
    }

    func start() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            // A call or Siri took the audio session. This isn't media the user
            // controls, so resume whenever the interruption ends.
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            MainActor.assumeIsolated { BackgroundDownloads.shared.keepAliveNeedsRestart() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: session, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundDownloads.shared.audioServicesReset() }
        })
        restart()
    }

    func reset() {
        player = nil
        activatedSession = false
        restart()
    }

    func stop() {
        stopped = true
        loop?.cancel()
        loop = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        player?.stop()
        player = nil
        endBackgroundTask()
        if activatedSession, !PlaybackAudioSession.isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        activatedSession = false
    }

    func restart() {
        guard !stopped else { return }
        loop?.cancel()
        switch mode {
        case .continuous:
            player?.stop()
            playAudio(looping: true)
        case .smart:
            loop = Task { [weak self] in await self?.pulseLoop() }
        case .off:
            break
        }
    }

    /// Plays a moment of silence, and while it plays, swaps in a fresh
    /// background task. The task keeps the app running between pulses.
    private func pulseLoop() async {
        var failures = 0
        while !Task.isCancelled, !stopped {
            playAudio(looping: true)
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !stopped else { return }

            let previous = backgroundTask
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SceneBox.downloads") {
                MainActor.assumeIsolated { BackgroundDownloads.shared.keepAliveNeedsRestart() }
            }
            if previous != .invalid { UIApplication.shared.endBackgroundTask(previous) }

            if backgroundTask == .invalid {
                // iOS wouldn't hand out more time. After a few tries, fall back to
                // continuous silence so downloads keep going.
                failures += 1
                if failures >= 3 {
                    playAudio(looping: true)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            failures = 0
            player?.stop()
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func playAudio(looping: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            if !PlaybackAudioSession.isActive {
                // Mixable, so the user's music keeps playing untouched.
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            activatedSession = true
            let player = try self.player ?? AVAudioPlayer(data: Self.silence)
            player.numberOfLoops = looping ? -1 : 0
            player.volume = 0.01
            self.player = player
            if !player.isPlaying { player.play() }
        } catch {
            #if DEBUG
            print("[BackgroundDownloads] audio keep-alive failed: \(error)")
            #endif
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// One second of near-silent 8 kHz mono PCM (a ±1 LSB ripple, about −90 dB).
    private static let silence: Data = {
        let sampleRate: UInt32 = 8_000
        let samples = Int(sampleRate)
        var pcm = Data(capacity: samples * 2)
        for i in 0..<samples {
            var value = Int16(i % 2 == 0 ? 1 : -1).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func append<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16).littleEndian)           // PCM chunk size
        append(UInt16(1).littleEndian)            // PCM
        append(UInt16(1).littleEndian)            // mono
        append(sampleRate.littleEndian)
        append((sampleRate * 2).littleEndian)     // byte rate
        append(UInt16(2).littleEndian)            // block align
        append(UInt16(16).littleEndian)           // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        return wav
    }()
}

// MARK: - Continued processing task (iOS 26+)

/// Runs active downloads as a `BGContinuedProcessingTask`, so iOS knows the
/// person is waiting on them and shows their progress in a Live Activity.
@available(iOS 26.0, *)
@MainActor
private final class DownloadProcessingTask {
    private var task: BGContinuedProcessingTask?
    private var tracked: Set<String> = []
    private var submitted = false
    private(set) var isDone = false
    private var lastDone: Int64 = -1

    /// Adds downloads to the running task, or submits a new one.
    func include(_ ids: Set<String>) {
        guard !isDone, !ids.isEmpty else { return }
        tracked.formUnion(ids)
        guard !submitted else { update(); return }
        submitted = true

        // "<bundle id>.downloads.*" from Info.plist. Signers that rewrite the
        // bundle id break the prefix; then the system refuses and the audio
        // keep-alive carries on alone.
        guard let base = Self.permittedBase else { isDone = true; return }
        let identifier = base + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated { BackgroundDownloads.shared.processingTaskLaunched(task) }
        }
        guard registered else { isDone = true; return }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: "SceneBox downloads",
                                                       subtitle: "Starting…")
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[BackgroundDownloads] continued processing refused: \(error)")
            #endif
            isDone = true
        }
    }

    func attach(_ task: BGContinuedProcessingTask) {
        guard !isDone else {
            task.setTaskCompleted(success: true)
            return
        }
        self.task = task
        task.expirationHandler = {
            // Either the person dismissed it or iOS decided progress stalled; the
            // two can't be told apart. Downloads keep running on the audio
            // keep-alive — pausing here would bring back the original bug.
            Task { @MainActor in BackgroundDownloads.shared.processingTaskExpired() }
        }
        update()
    }

    func update() {
        guard let task, !isDone else { return }
        let store = DownloadStore.shared
        let stillRunning = tracked.contains { id in store.downloads.first { $0.id == id }?.phase.isPending == true }
        guard stillRunning else {
            let allDone = tracked.allSatisfy { id in store.downloads.first { $0.id == id }?.phase == .completed }
            finish(success: allDone)
            return
        }

        let (done, total) = store.aggregateProgress(for: tracked)
        let progress = task.progress
        progress.totalUnitCount = max(total, done, 1)
        if done != lastDone {
            progress.completedUnitCount = done
            lastDone = done
        }

        let active = tracked.compactMap { id in store.downloads.first { $0.id == id } }
        let running = active.filter(\.phase.isPending)
        let rate = active.reduce(0) { $0 + $1.downloadRate }
        let title = running.count == 1
            ? [running[0].record.title, running[0].record.episodeLabel].compactMap { $0 }.joined(separator: " · ")
            : "Downloading \(running.count) items"
        var subtitle = total > 0 ? "\(ByteFormat.size(done)) of \(ByteFormat.size(total))" : "Starting…"
        if rate > 0 { subtitle += " · \(ByteFormat.rate(rate))" }
        task.updateTitle(title, subtitle: subtitle)
    }

    func finish(success: Bool) {
        guard !isDone else { return }
        isDone = true
        task?.setTaskCompleted(success: success)
        task = nil
    }

    private static var permittedBase: String? {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard let wildcard = ids.first(where: { $0.hasSuffix(".downloads.*") }) else { return nil }
        return String(wildcard.dropLast())      // keep the trailing "."
    }
}
#endif
