//
//  PlaybackScreen.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import SwiftVLC
import UIKit
#if canImport(Translation) && os(iOS)
@preconcurrency import Translation
#endif
#if DEBUG
import OSLog

private let playbackLog = Logger(subsystem: "WatchBox", category: "playback")
#endif

struct PlaybackScreen: View {
    let url: URL
    let title: String
    let stats: SwarmStats?
    var subtitleContext: SubtitleContext? = nil
    var episodes: EpisodePlaylist? = nil
    var startAt: Duration = .zero
    var progress: WatchProgressContext? = nil
    var artworkURL: URL? = nil
    var originalAudioLanguage: String? = nil
    /// After the stream broke off mid-episode: where to reopen it.
    var onRecover: (() async -> URL?)? = nil
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var player = Player()
    #if os(iOS)
    @State private var nowPlaying: NowPlayingController?
    #endif
    @State private var chrome = ChromeVisibility()
    @State private var subs = SubtitlesController()
    @State private var failure: String?
    @State private var isStalled = false
    @State private var didSeekToStart = false
    @State private var openRetries = 0
    /// Replaces `url` after a recovery (e.g. the finished file on disk).
    @State private var sourceOverride: URL?
    /// The last place playback really reached, for picking up after a break.
    @State private var lastGoodPosition: Duration = .zero
    @State private var recoverySeek: Duration?
    @State private var recoveries = 0
    @State private var isRecovering = false
    @State private var recoveredAt: Duration?
    @Environment(\.scenePhase) private var scenePhase
    @State private var knownDuration: Duration = .zero
    /// Seconds left while the next-episode prompt is up (the credits).
    @State private var upNextRemaining: Double?
    /// Dismissed: no prompt and no auto-play, unless the viewer rewinds.
    @State private var upNextCancelled = false
    /// The episode being looked up to play next; further picks wait for it.
    @State private var advancingTo: Episode?
    /// The audio track picked by hand or for the original language, picked again when the video reopens.
    @State private var chosenAudioID: String?
    @State private var cast = CastSession()
    @State private var showCastPicker = false
    @State private var showCastSubtitles = false
    @State private var toast: ToastMessage?
    /// The player closed; work still in flight must not start it again.
    @State private var closed = false
    #if os(iOS)
    @State private var showSettings = false
    @State private var isLandscape = false
    @State private var levels = SwipeLevels()
    @FocusState private var hasKeyboardFocus: Bool
    @State private var lastHoverReveal = Date.distantPast
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            if !Platform.isMac {
                SystemVolumeHost(levels: levels)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            #endif

            VideoView(player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                #if os(tvOS)
                .allowsHitTesting(false)
                .focusable(false)
                #endif

            #if os(iOS)
            Color.clear
                .contentShape(Rectangle())
                // Landscape: swipe up/down on the left for brightness, on the right for volume.
                .swipeToAdjustLevels(levels, enabled: failure == nil)
                // Mac only: anywhere else a double tap would hold back every single tap.
                .gesture(TapGesture(count: 2).onEnded { MacWindow.toggleFullScreen() },
                         including: Platform.isMac ? .all : .subviews)
                .onTapGesture {
                    guard failure == nil else { return }
                    chrome.screenTapped(shouldAutoHide: player.isPlaying && !isBuffering)
                }
                .ignoresSafeArea()
            #endif

            #if os(iOS)
            if cast.isActive {
                CastingOverlay(cast: cast, title: title, artworkURL: artworkURL,
                               subtitlesChanged: subs.fileOnScreen != cast.sentSubtitleFile,
                               onSendSubtitles: { Task { await cast.sendSubtitles(subs.fileOnScreen) } },
                               onSubtitles: { showCastSubtitles = true },
                               onStop: stopCasting,
                               onClose: onClose)
                .transition(.opacity)
                if showCastSubtitles {
                    PlaybackSettingsPanel(player: player, subs: subs) { showCastSubtitles = false }
                        .transition(.opacity)
                }
            }
            #endif

            if let failure {
                FailureOverlay(message: failure, onClose: onClose)
            } else if chrome.isVisible, !cast.isActive {
                #if os(tvOS)
                TVPlaybackChrome(
                    player: player,
                    title: title,
                    stats: stats,
                    isBuffering: isBuffering,
                    subs: subs,
                    onSettingsOpenChanged: { open in
                        open ? chrome.holdVisible()
                             : chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
                    },
                    onInteraction: { chrome.interacted(autoHide: player.isPlaying && !isBuffering) },
                    onAudioSelected: { track in chosenAudioID = track.id },
                    episodes: chromeEpisodes,
                    onClose: onClose
                )
                .transition(.opacity)
                #else
                PlaybackControls(
                    player: player,
                    title: title,
                    stats: stats,
                    isBuffering: isBuffering,
                    subs: subs,
                    showSettings: $showSettings,
                    onSettingsOpenChanged: { open in
                        open ? chrome.holdVisible()
                             : chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
                    },
                    isLandscape: isLandscape,
                    onToggleOrientation: toggleOrientation,
                    onAudioSelected: { track in chosenAudioID = track.id },
                    episodes: chromeEpisodes,
                    onCast: openCastPicker,
                    onClose: onClose
                )
                .transition(.opacity)
                #endif
            }

            #if os(tvOS)
            if failure == nil, !chrome.isVisible {
                Button {
                    chrome.screenTapped(shouldAutoHide: player.isPlaying && !isBuffering)
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(InvisibleButtonStyle())
                .ignoresSafeArea()
            }
            #endif

            if let remaining = upNextRemaining, let episodes, let next = episodes.next {
                #if os(iOS)
                NextEpisodeButton(episode: next,
                                  isNewSeason: episodes.nextIsNewSeason,
                                  autoplayProgress: remaining <= Self.autoplaySeconds
                                      ? 1 - remaining / Self.autoplaySeconds : nil,
                                  onPlay: playNextNow,
                                  onDismiss: dismissUpNext)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, upNextTrailingInset)
                .padding(.bottom, chrome.isVisible ? upNextRaisedInset : upNextBottomInset)
                .animation(.easeInOut(duration: 0.25), value: chrome.isVisible)
                .transition(.opacity.combined(with: .offset(x: 24)))
                #else
                UpNextCard(episode: next,
                           isNewSeason: episodes.nextIsNewSeason,
                           seconds: max(1, Int(remaining.rounded(.up))),
                           onCancel: dismissUpNext)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, upNextTrailingInset)
                .padding(.bottom, chrome.isVisible ? upNextRaisedInset : upNextBottomInset)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                #endif
            }

            if let advancingTo {
                let isNext: Bool = advancingTo == episodes?.next
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(isNext ? "Finding next episode…" : "Finding \(advancingTo.label)…")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, upNextTrailingInset)
                .padding(.bottom, chrome.isVisible ? upNextRaisedInset : upNextBottomInset)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            #if os(iOS)
            SwipeLevelsIndicator(levels: levels)
            #endif
        }
        .animation(.easeInOut(duration: 0.35), value: upNextRemaining != nil)
        .animation(.easeInOut(duration: 0.25), value: advancingTo)
        .animation(.easeInOut(duration: 0.25), value: cast.isActive)
        .toast($toast)
        .onChange(of: cast.computerPlays) { _, _ in
            // A computer is playing it from the page: one player at a time.
            if player.isPlaying { player.pause() }
        }
        #if os(iOS)
        .sheet(isPresented: $showCastPicker) {
            CastSheet(discovery: CastDiscovery.shared, computerPageURL: cast.computerPageURL,
                      hasSubtitles: subs.fileOnScreen != nil) { device in
                showCastPicker = false
                startCasting(on: device)
            }
        }
        #endif
        .contentShape(Rectangle())
        #if os(iOS)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.space) { keyboardTogglePlayback(); return .handled }
        .onKeyPress(.leftArrow) { keyboardSeek(by: -10); return .handled }
        .onKeyPress(.rightArrow) { keyboardSeek(by: 10); return .handled }
        .onKeyPress(.upArrow) { keyboardVolume(by: 0.05); return .handled }
        .onKeyPress(.downArrow) { keyboardVolume(by: -0.05); return .handled }
        .onKeyPress(.escape) { keyboardEscape(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "kK")) { _ in keyboardTogglePlayback(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "fF")) { _ in MacWindow.toggleFullScreen(); return .handled }
        .onChange(of: chrome.isVisible, initial: true) { _, visible in
            MacWindow.setCursorHidden(!visible && failure == nil)
        }
        .onDisappear { MacWindow.setCursorHidden(false) }
        .onContinuousHover { phase in
            guard case .active = phase, failure == nil else { return }
            let now = Date()
            guard now.timeIntervalSince(lastHoverReveal) > 0.5 else { return }
            lastHoverReveal = now
            chrome.reveal(autoHide: player.isPlaying && !isBuffering)
        }
        #endif
        #if os(tvOS)
        .onPlayPauseCommand { player.togglePlaybackReasserting() }
        .onMoveCommand { _ in
            guard failure == nil, !chrome.isVisible else { return }
            chrome.reveal(autoHide: player.isPlaying && !isBuffering)
        }
        .onExitCommand {
            if upNextRemaining != nil {
                dismissUpNext()
            } else if chrome.isVisible {
                chrome.hide()
            } else {
                onClose()
            }
        }
        #endif
        .hideStatusBarCompat()
        .hideSystemOverlaysCompat()
        .preferredColorScheme(.dark)
        .task(id: chrome.autoHideID) { await chrome.autoHide() }
        .task { await watchForStalls() }
        .task { await watchForUpNext() }
        .task { await recordProgressPeriodically() }
        .task { await keepNowPlayingFresh() }
        .task(id: openRetries) {
            guard openRetries > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            beginPlayback()
        }
        #if DEBUG
        .task { await reportPlayerTime() }
        .task { await monitorPlayback() }
        .task { await runAutoSeekScript() }
        #endif
        .onChange(of: player.isSeekable) { _, seekable in
            guard seekable else { return }
            if let target = recoverySeek {
                recoverySeek = nil
                try? player.seek(to: target)
                return
            }
            guard !didSeekToStart, startAt > .zero else { return }
            didSeekToStart = true
            try? player.seek(to: startAt)
        }
        .onChange(of: scenePhase) { _, phase in
            // Save the spot before iOS may suspend the app.
            if phase == .background { recordProgress() }
        }
        .onAppear(perform: start)
        .onChange(of: player.isPlaying) { _, playing in
            ScreenIdle.keepAwake(playing)
            #if os(iOS)
            nowPlaying?.refresh()
            #endif
            guard failure == nil, !isBuffering else { return }
            if playing {
                if chrome.isVisible { chrome.playbackStarted() }
            } else {
                chrome.reveal(autoHide: false)
            }
        }
        .onChange(of: player.subtitleTracks.count) { _, _ in
            subs.syncEmbedded(on: player)
        }
        .onChange(of: player.selectedSubtitleTrack?.id) { _, _ in
            subs.syncEmbedded(on: player)
        }
        .onChange(of: player.audioTracks.count) { _, _ in
            syncOriginalAudio()
        }
        .onChange(of: player.duration) { _, new in
            if let new, new > .zero { knownDuration = new }
        }
        .onChange(of: player.didReachEnd) { _, ended in
            guard ended, !cast.isActive else { return }
            // VLC reports "ended" whenever the stream closes. Mid-episode that
            // means the stream broke (e.g. after the phone was locked): pick
            // up where it stopped, never mark it watched or skip ahead.
            if endedEarly { recoverStream() } else { playbackEnded() }
        }
        .onChange(of: isBuffering) { wasBuffering, buffering in
            if wasBuffering, !buffering { chrome.playbackStarted() }
        }
        .onChange(of: player.state) { _, state in
            subs.playerStateChanged(state)
            if state == .playing { syncOriginalAudio() }   // a reopen may list the same number of tracks
            if state == .playing, let target = recoverySeek, player.isSeekable {
                recoverySeek = nil
                try? player.seek(to: target)
            }
            guard state == .error, failure == nil, !cast.isActive else { return }
            if lastGoodPosition > .zero {
                recoverStream()
            } else if sourceURL.host == "127.0.0.1", player.currentTime == .zero, openRetries < 5 {
                player.stop()
                openRetries += 1
            } else {
                failure = "Playback failed. The release may be corrupt or use an unsupported container."
            }
        }
        .onDisappear(perform: teardown)
        #if canImport(Translation) && os(iOS)
        // Only for the first-time language download prompt; translating runs
        // app-wide (TranslationCenter) so it survives closing the player.
        .translationTask(subs.prepareConfiguration) { session in
            await subs.prepareLanguage(session)
        }
        #endif
    }

    private var sourceURL: URL { sourceOverride ?? url }

    /// "Ended" well before the credits: the stream broke off. A file on the
    /// phone doesn't, and a playhead at the very end (a drag there) is the end.
    private var endedEarly: Bool {
        guard !sourceURL.isFileURL, player.position < 0.98 else { return false }
        return knownDuration > .zero && lastGoodPosition > .zero
            && lastGoodPosition < knownDuration - .seconds(20)
    }

    /// Reopens the video where it stopped: from the file itself when it's all
    /// on the phone, else from the stream once it answers again.
    private func recoverStream() {
        guard !isRecovering, failure == nil, !cast.isActive else { return }
        guard recoveries < 5 else {
            failure = "The stream stopped and couldn't restart. Close the player and open the episode again; it will continue from here."
            return
        }
        recoveries += 1
        isRecovering = true
        let resumeAt = lastGoodPosition
        recoveredAt = resumeAt
        recordProgress()
        let attempt = recoveries
        Task {
            player.stop()
            try? await Task.sleep(for: .milliseconds(500 * attempt))
            if let fresh = await onRecover?() { sourceOverride = fresh }
            guard !closed else { return }
            recoverySeek = resumeAt
            isRecovering = false
            beginPlayback()
        }
    }

    private var isBuffering: Bool {
        guard failure == nil else { return false }
        if isRecovering { return true }   // Play would restart from the beginning
        switch player.state {
        case .opening, .buffering: return true
        case .playing: return player.currentTime == .zero || isStalled
        default: return false
        }
    }

    private func watchForStalls() async {
        var lastSeen = player.currentTime
        var frozenTicks = 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard player.isPlaying else {
                frozenTicks = 0
                isStalled = false
                lastSeen = player.currentTime
                continue
            }

            if player.currentTime == lastSeen {
                frozenTicks += 1
            } else {
                frozenTicks = 0
                lastSeen = player.currentTime
            }
            if recoverySeek == nil, !isRecovering, player.currentTime > .zero {
                // A minute of good playback after a recovery clears the count.
                if let at = recoveredAt, player.currentTime > at + .seconds(60) {
                    recoveries = 0
                    recoveredAt = nil
                }
                lastGoodPosition = player.currentTime
            }
            isStalled = frozenTicks >= 3
        }
    }

    // MARK: - Auto-play next episode

    #if os(tvOS)
    private var upNextTrailingInset: CGFloat { 80 }
    private var upNextBottomInset: CGFloat { 60 }
    private var upNextRaisedInset: CGFloat { 210 }
    #else
    private var upNextTrailingInset: CGFloat { 20 }
    private var upNextBottomInset: CGFloat { 24 }
    private var upNextRaisedInset: CGFloat { 120 }
    #endif

    /// Auto-play follows after this many seconds of the prompt filling up.
    private static let autoplaySeconds = 10.0

    /// When the prompt appears: the last 90 s on iPhone and iPad (credits),
    /// shorter for short episodes; the last 10 s on Apple TV.
    private var upNextWindow: Double {
        #if os(tvOS)
        return Self.autoplaySeconds
        #else
        return max(Self.autoplaySeconds + 5, min(90, knownDuration.asSeconds * 0.08))
        #endif
    }

    private func watchForUpNext() async {
        guard episodes?.next != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard advancingTo == nil, failure == nil, !cast.isActive,
                  knownDuration > .zero, player.currentTime > .zero else {
                upNextRemaining = nil
                continue
            }
            let remaining = (knownDuration - player.currentTime).asSeconds
            // Rewound well before the credits: a dismissed prompt may come back.
            if upNextCancelled, remaining > upNextWindow + 60 { upNextCancelled = false }
            guard !upNextCancelled, remaining > 0, remaining <= upNextWindow else {
                upNextRemaining = nil
                continue
            }
            upNextRemaining = remaining
        }
    }

    private func dismissUpNext() {
        upNextCancelled = true
        upNextRemaining = nil
    }

    /// "Next Episode" during the credits: this one counts as watched.
    private func playNextNow() {
        guard advancingTo == nil, let next = episodes?.next else { return }
        markWatched()
        advance(to: next)
    }

    /// Every switch to another episode (the prompt, the chrome's Next and
    /// episode list) goes through here: one lookup at a time, shown meanwhile.
    private func advance(to episode: Episode) {
        guard advancingTo == nil, let episodes else { return }
        advancingTo = episode
        upNextRemaining = nil
        episodes.onPlay(episode)
        // A new episode replaces this screen; if nothing came of it, let the viewer try again.
        Task {
            try? await Task.sleep(for: .seconds(30))
            if advancingTo == episode { advancingTo = nil }
        }
    }

    private var chromeEpisodes: EpisodePlaylist? {
        guard let episodes else { return nil }
        return EpisodePlaylist(current: episodes.current, all: episodes.all, mediaID: episodes.mediaID,
                               onPlay: { episode in advance(to: episode) })
    }

    private func markWatched() {
        guard let progress, knownDuration > .zero else { return }
        WatchProgressStore.shared.record(
            id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
            posterURL: progress.posterURL, season: progress.season,
            episode: progress.episode, episodeID: progress.episodeID,
            position: knownDuration, duration: knownDuration)
    }

    private func playbackEnded() {
        markWatched()
        guard !upNextCancelled, let next = episodes?.next else { return }
        advance(to: next)
    }

    // MARK: - Original-language audio

    private var targetAudioLanguage: String? {
        let preferred = settings.preferredAudioLanguage.lowercased()
        let original = originalAudioLanguage?.lowercased()
        if preferred.isEmpty { return original?.isEmpty == false ? original : nil }
        guard let original, !original.isEmpty, original != preferred else { return preferred }
        return original
    }

    private func syncOriginalAudio() {
        var seen = Set<String>()
        let tracks = player.audioTracks.filter { seen.insert($0.id).inserted }
        if let id = chosenAudioID {
            // Reopened (recovery, back from the TV): VLC starts on its default track again.
            guard player.selectedAudioTrack?.id != id,
                  let chosen = tracks.first(where: { $0.id == id }) else { return }
            player.selectedAudioTrack = chosen
            return
        }
        guard let code = targetAudioLanguage else { return }
        guard tracks.count > 1 else { return }   // more may still be discovered

        if let selected = player.selectedAudioTrack,
           speaks(selected, code) {
            chosenAudioID = selected.id
            return
        }
        guard let match = tracks.first(where: { speaks($0, code) }) else { return }
        player.selectedAudioTrack = match
        chosenAudioID = match.id
    }

    private func speaks(_ track: Track, _ code: String) -> Bool {
        OriginalAudio.matches(language: track.language, labels: [track.name, track.trackDescription ?? ""], code: code)
    }

    /// What the TV should speak, best first: the track playing here, then the one this player would pick.
    private var castAudioLanguages: [String] {
        [player.selectedAudioTrack?.language, targetAudioLanguage].compactMap { $0 }.filter { !$0.isEmpty }
    }

    #if DEBUG
    private func reportPlayerTime() async {
        guard !url.isFileURL else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            PlayheadTelemetry.shared.notePlayerTime(seconds: player.currentTime.asSeconds)
        }
    }

    private func runAutoSeekScript() async {
        guard url.host == "127.0.0.1",
              let script = UserDefaults.standard.string(forKey: "WBAutoSeekScript") else { return }
        var steps: [(at: Double, delta: Double)] = []
        for part in script.split(separator: ",") {
            let bits = part.split(separator: ":")
            guard bits.count == 2, let at = Double(bits[0]), let delta = Double(bits[1]) else { continue }
            steps.append((at: at, delta: delta))
        }
        steps.sort { $0.at < $1.at }
        guard !steps.isEmpty else { return }
        while player.currentTime == .zero, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let playbackStarted = Date()
        for step in steps {
            while Date().timeIntervalSince(playbackStarted) < step.at, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, failure == nil else { return }
            let target = player.currentTime + .seconds(step.delta)
            playbackLog.notice("autoseek: \(step.delta >= 0 ? "+" : "", privacy: .public)\(Int(step.delta), privacy: .public)s → t=\(Int(target.asSeconds), privacy: .public)s")
            try? player.seek(to: target)
        }
    }

    private func monitorPlayback() async {
        guard !url.isFileURL else { return }
        var last = player.currentTime
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            let now = player.currentTime
            let delta = (now - last).asSeconds
            last = now
            let stalled = player.isPlaying && delta < 0.25

            playbackLog.notice("""
            \(stalled ? "STALL" : "ok", privacy: .public) · playing=\(player.isPlaying, privacy: .public) \
            playhead=\(timecode(now), privacy: .public) Δ=\(String(format: "%.2f", delta), privacy: .public)s \
            state=\(String(describing: player.state), privacy: .public) buffering=\(isBuffering, privacy: .public)
            """)
        }
    }
    #endif

    private func start() {
        player.aspectRatio = settings.fillScreen ? .fill : .default
        player.setSubtitleScale(SubtitleScale(Float(settings.subtitleScale)))
        #if os(iOS)
        // Video opens the way it's watched. The rotate button still returns to
        // portrait, and iPads keep whichever way they're held.
        if UIDevice.current.userInterfaceIdiom == .phone, !Platform.isMac {
            isLandscape = true
            ScreenOrientation.landscape()
        }
        levels.attach(player: player)
        #endif
        Task {
            await PlaybackAudioSession.activate()
            guard !closed else { return }
            beginPlayback()
            #if os(iOS)
            beginNowPlaying()
            #endif
        }
    }

    #if os(iOS)
    private func beginNowPlaying() {
        let controller = NowPlayingController(player: player, title: title)
        controller.begin(artworkURL: artworkURL)
        nowPlaying = controller
    }
    #endif

    private func keepNowPlayingFresh() async {
        #if os(iOS)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            nowPlaying?.refresh()
        }
        #endif
    }

    private func beginPlayback() {
        let url = sourceURL
        do {
            let media = try Media(url: url)
            if !url.isFileURL {
                let isTorrent = url.host == "127.0.0.1"
                // The local torrent server already holds data ahead of the playhead,
                // so a very deep player cache only delays the first frame.
                let cacheMs = isTorrent
                    ? max(settings.networkCacheMilliseconds, 5000)
                    : settings.networkCacheMilliseconds
                media.addOption(":network-caching=\(cacheMs)")

                if isTorrent {
                } else {
                    media.addOption(":http-reconnect")
                }
            }
            try player.play(media)
        } catch {
            failure = error.localizedDescription
        }

        if let subtitleContext {
            subs.load(context: subtitleContext, preferred: settings.preferredSubtitleLanguage, player: player)
        }
    }

    #if os(iOS)
    private func keyboardTogglePlayback() {
        guard failure == nil else { return }
        if cast.isActive { cast.togglePause(); return }   // the phone's player is stopped
        player.togglePlaybackReasserting()
        chrome.reveal(autoHide: !player.isPlaying && !isBuffering)
    }

    private func keyboardSeek(by seconds: Double) {
        if cast.isActive { cast.skip(by: seconds); return }
        guard failure == nil, player.isSeekable else { return }
        try? player.seek(by: .seconds(seconds), fast: true)
        chrome.reveal(autoHide: player.isPlaying && !isBuffering)
    }

    private func keyboardVolume(by delta: Float) {
        try? player.setAudioVolume(Volume(min(1, max(0, player.volume + delta))))
        chrome.reveal(autoHide: player.isPlaying && !isBuffering)
    }

    private func keyboardEscape() {
        if showSettings || showCastSubtitles {
            showSettings = false
            showCastSubtitles = false
        } else if upNextRemaining != nil {
            dismissUpNext()
        } else if chrome.isVisible, player.isPlaying {
            chrome.hide()
        } else {
            onClose()
        }
    }

    private func toggleOrientation() {
        isLandscape.toggle()
        isLandscape ? ScreenOrientation.landscape() : ScreenOrientation.reset()
    }
    #endif

    private func recordProgressPeriodically() async {
        guard progress != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            // While casting the phone's player sits paused; the TV's position counts.
            if player.isPlaying || cast.phase == .playing { recordProgress() }
        }
    }

    private func recordProgress(publish: Bool = false) {
        guard let progress, failure == nil else { return }
        let position = cast.isActive ? Duration.seconds(cast.position) : player.currentTime
        let duration = cast.isActive && cast.duration > 0 ? Duration.seconds(cast.duration) : player.duration
        guard position > .zero else { return }
        WatchProgressStore.shared.record(
            id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
            posterURL: progress.posterURL, season: progress.season,
            episode: progress.episode, episodeID: progress.episodeID,
            position: position, duration: duration, publish: publish)
    }

    // MARK: - Casting

    /// Opens the screen picker, serving the video on the Wi-Fi meanwhile so
    /// a computer can open it too.
    private func openCastPicker() {
        showCastPicker = true
        let media = CastSession.Media(source: sourceURL, title: title,
                                      durationSeconds: knownDuration.asSeconds,
                                      audioLanguages: castAudioLanguages)
        let subtitleFile = subs.fileOnScreen
        Task { await cast.prepare(media, subtitleFile: subtitleFile) }
    }

    /// The phone's player stops (so the TV gets the whole stream) and the TV
    /// takes over from the same spot.
    private func startCasting(on device: RendererDescription) {
        let from = player.currentTime > .zero ? player.currentTime : lastGoodPosition
        lastGoodPosition = from
        recordProgress()
        upNextRemaining = nil
        let media = CastSession.Media(source: sourceURL, title: title,
                                      durationSeconds: knownDuration.asSeconds,
                                      audioLanguages: castAudioLanguages)
        player.stop()
        #if os(iOS)
        // Lock screen, AirPods and Control Center would drive the stopped phone player.
        nowPlaying?.end()
        nowPlaying = nil
        #endif
        Task {
            let serving = await cast.prepare(media, subtitleFile: subs.fileOnScreen)
            guard !closed else { return }
            guard serving else {
                toast = ToastMessage(text: "Couldn't reach the Wi-Fi to cast.", systemImage: "wifi.exclamationmark")
                resumeHere(at: from)
                return
            }
            await cast.cast(to: device, from: from.asSeconds)
        }
    }

    /// Back to the phone, where the TV got to.
    private func stopCasting() {
        recordProgress()   // the TV's position, while it's still the one that counts
        Task {
            let reached = await cast.stop()
            guard !closed else { return }
            showCastSubtitles = false
            let resumeAt = reached > 1 ? Duration.seconds(reached) : lastGoodPosition
            lastGoodPosition = resumeAt
            resumeHere(at: resumeAt)
        }
    }

    /// The phone's player picks up at `position`, lock-screen controls included.
    private func resumeHere(at position: Duration) {
        recoverySeek = position
        beginPlayback()
        #if os(iOS)
        beginNowPlaying()
        #endif
    }

    private func teardown() {
        closed = true
        recordProgress(publish: true)   // before the cast shuts down: while casting, the TV's position counts
        cast.shutdown()
        subs.stop()
        #if os(iOS)
        nowPlaying?.end()
        nowPlaying = nil
        levels.detach()
        #endif
        chrome.viewDisappeared()
        ScreenIdle.keepAwake(false)
        #if os(iOS)
        ScreenOrientation.reset()
        #endif

        let player = player
        Task {
            await player.stopAndWait()
            PlaybackAudioSession.deactivate()
        }
    }
}

#if os(tvOS)
private struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

private struct FailureOverlay: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}
