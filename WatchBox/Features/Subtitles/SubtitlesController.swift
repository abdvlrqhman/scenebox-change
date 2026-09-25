//
//  SubtitlesController.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation
import Observation
import SwiftVLC
#if canImport(Translation) && os(iOS)
@preconcurrency import Translation
#endif

/// Picks, attaches and keeps the subtitle the viewer wants on screen.
///
/// Instead of firing one attach and hoping, it records what should be showing
/// (`Wanted`) and a small loop keeps the player in line with it. That covers
/// the cases that used to lose subtitles: the file arriving before the stream
/// has opened, VLC reopening a torrent stream after an early read error (which
/// drops external tracks), and slow OpenSubtitles responses.
@MainActor
@Observable
final class SubtitlesController {
    private(set) var available: [SubtitleTrack] = []
    private(set) var selectedID: String?
    private(set) var embeddedID: String?
    private(set) var externalTrackIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    /// The version being downloaded after a tap, for the row's spinner.
    private(set) var loadingID: String?
    /// Sync for what's on screen, in milliseconds (negative = earlier).
    private(set) var offsetMilliseconds = 0
    /// 0…1 while an English version is being translated on the device.
    private(set) var translationProgress: Double?

    private enum Wanted: Equatable {
        case undecided                  // default language not resolved yet
        case off
        case embedded(String)           // track id inside the video
        case external(SubtitleTrack, URL)
        case preparing(SubtitleTrack)   // synced copy being written
    }

    @ObservationIgnored private let provider = SubtitlesProvider.shared
    @ObservationIgnored private weak var player: Player?
    @ObservationIgnored private var context: SubtitleContext?
    @ObservationIgnored private var preferred = ""
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var wanted: Wanted = .undecided
    @ObservationIgnored private var preferredFile: (track: SubtitleTrack, file: URL)?
    @ObservationIgnored private var preferredLookupDone = false
    @ObservationIgnored private var embeddedChecked = false
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?

    // Per opened media ("generation"): VLC throws external tracks away whenever
    // the stream is reopened, so everything attached is remembered per open.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var playingSince: Date?
    @ObservationIgnored private var attachedTracks: [URL: String] = [:]
    /// An attach VLC hasn't finished yet; adopted whenever its track shows up.
    @ObservationIgnored private var pendingAttach: (url: URL, before: Set<String>, generation: Int, at: Date)?
    /// Per file, so switching versions or sync never runs out of attempts.
    @ObservationIgnored private var attemptsByURL: [URL: Int] = [:]
    /// Downloaded file of each version; synced copies are made from it.
    @ObservationIgnored private var originals: [String: URL] = [:]
    @ObservationIgnored private var bakeTask: Task<Void, Never>?
    @ObservationIgnored private var offsetTask: Task<Void, Never>?
    @ObservationIgnored private var enforcedGeneration = -1
    @ObservationIgnored private var delayGeneration = -1
    /// What's on screen now, as stored in `SubtitleMemory`.
    @ObservationIgnored private var activeTrackKey: String?
    @ObservationIgnored private var memory: SubtitleMemory.Entry?
    @ObservationIgnored private var fpsChecked = false
    /// Offsets set this session, per version, so comparing A → B → A keeps A's.
    @ObservationIgnored private var sessionDelays: [String: Int] = [:]

    // MARK: Lifecycle

    func load(context: SubtitleContext, preferred: String, player: Player) {
        self.player = player
        guard !loaded else { reconcile(); return }
        loaded = true
        self.context = context
        self.memory = SubtitleMemory.entry(for: context)
        // The version kept last time wins, in whatever language it was: picking
        // an English version for one episode shouldn't revert to Arabic.
        var rememberedID: String?
        if let memory, let key = memory.trackKey, key.hasPrefix("ext:"), let language = memory.language {
            rememberedID = String(key.dropFirst(4))
            self.preferred = SubtitleLanguage.canonical(language)
            fpsChecked = true                 // keep the version the saved offset belongs to
        } else if let language = SubtitleMemory.episodeLanguage(for: context), !language.isEmpty {
            // New source for this episode: same language, best version for this release.
            self.preferred = SubtitleLanguage.canonical(language)
        } else {
            self.preferred = SubtitleLanguage.canonical(preferred)
        }
        if self.preferred.isEmpty { wanted = .off }

        isLoading = true
        fetchTask = Task { [provider] in
            var tracks = await provider.subtitles(for: context)
            guard !Task.isCancelled else { return }
            // A translation made on this device earlier is kept on disk.
            if let rememberedID, rememberedID.hasPrefix(TranslatedSubtitles.idPrefix),
               let cached = TranslatedSubtitles.cached(id: rememberedID) {
                tracks.append(cached.track)
                available = tracks
                preferredFile = cached
                preferredLookupDone = true
                isLoading = false
                reconcile()
                return
            }
            available = tracks
            if !self.preferred.isEmpty {
                preferredFile = await provider.bestFile(for: context, language: self.preferred, tracks: tracks,
                                                        preferredID: rememberedID)
                guard !Task.isCancelled else { return }
                preferredLookupDone = true
            }
            isLoading = false
            reconcile()
        }

        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.reconcile()
            }
        }
    }

    func stop() {
        loop?.cancel()
        fetchTask?.cancel()
        applyTask?.cancel()
        bakeTask?.cancel()
        offsetTask?.cancel()
    }

    /// Called from the screen whenever the player's state changes.
    func playerStateChanged(_ state: PlayerState) {
        switch state {
        case .idle, .stopped, .stopping, .error:
            // The media is gone; a retry will open a fresh one.
            if playingSince != nil || !attachedTracks.isEmpty {
                generation += 1
                playingSince = nil
                attachedTracks.removeAll()
                externalTrackIDs.removeAll()
                pendingAttach = nil
                attemptsByURL.removeAll()
            }
        case .playing:
            if playingSince == nil { playingSince = Date() }
        default:
            break
        }
        reconcile()
    }

    /// Kept for the screen's track-change hooks.
    func syncEmbedded(on player: Player) {
        self.player = player
        reconcile()
    }

    // MARK: User choices

    /// Shows `track`. `exact` is for a version the viewer tapped: no silent
    /// substitute if it fails, and the current subtitle stays up. Otherwise
    /// (picking a language) the next best version is tried.
    func apply(_ track: SubtitleTrack?, on player: Player, exact: Bool = false) {
        self.player = player
        applyTask?.cancel()
        loadingID = nil
        statusMessage = nil
        guard let track else {
            embeddedID = nil
            wanted = .off
            selectedID = nil
            activeTrackKey = nil
            player.selectedSubtitleTrack = nil
            if let context { SubtitleMemory.forgetTrack(for: context) }   // next time: the default language
            return
        }
        let previousSelected = selectedID
        let previousEmbedded = embeddedID
        if !exact {
            selectedID = track.id
            embeddedID = nil
        }
        loadingID = track.id
        applyTask = Task { [provider, context] in
            var file: (SubtitleTrack, URL)?
            if let url = try? await provider.download(track) {
                file = (track, url)
            } else if !exact, let context,
                      let fallback = await provider.bestFile(
                        for: context, language: track.languageCode,
                        tracks: available.filter { $0.id != track.id }) {
                file = fallback
            }
            guard !Task.isCancelled else { return }
            loadingID = nil
            guard let (chosen, url) = file else {
                selectedID = previousSelected
                embeddedID = previousEmbedded
                statusMessage = exact
                    ? "That version didn't download. Your current subtitles are still on."
                    : "Couldn't download \(track.languageName) subtitles. Try another language or try again."
                return
            }
            show(chosen, original: url)
        }
    }

    // MARK: Showing a version (sync baked into the file)

    /// Puts a downloaded version on screen with its saved sync and any
    /// frame-rate correction written into a copy of the file.
    private func show(_ track: SubtitleTrack, original: URL) {
        originals[track.id] = original
        selectedID = track.id
        embeddedID = nil
        offsetMilliseconds = savedOffset(for: track) ?? 0
        try? player?.setSubtitleDelay(.zero)          // the file carries the timing now
        bake(track, offset: offsetMilliseconds)
    }

    private func bake(_ track: SubtitleTrack, offset: Int) {
        guard let original = originals[track.id] else { return }
        let scale = frameRateScale(for: track)
        bakeTask?.cancel()
        // MicroDVD (.sub) counts frames, not time: it can't be re-timed, so it
        // keeps VLC's delay.
        let frameBased = original.pathExtension.lowercased() == "sub"
        if frameBased || (offset == 0 && abs(scale - 1) < 0.000_1) {
            try? player?.setSubtitleDelay(.milliseconds(frameBased ? offset : 0))
            wanted = .external(track, original)
            enforcedGeneration = -1
            reconcile()
            return
        }
        wanted = .preparing(track)
        bakeTask = Task {
            let url = await Task.detached(priority: .userInitiated) {
                (try? SubtitleRetimer.retime(original, offsetMilliseconds: offset, scale: scale)) ?? original
            }.value
            guard !Task.isCancelled else { return }
            wanted = .external(track, url)
            enforcedGeneration = -1
            reconcile()
        }
    }

    /// A version timed for a 25 fps release runs 4% short against a
    /// 23.976 fps video (and the reverse). Stretch it back when both rates are
    /// known and differ that way.
    func frameRateScale(for track: SubtitleTrack) -> Double {
        guard let video = player?.videoTracks.first?.frameRate, video > 1,
              let sub = track.fps, sub > 1, abs(sub - video) > 0.3 else { return 1 }
        let ratio = sub / video
        return (0.9...1.1).contains(ratio) ? ratio : 1
    }

    /// Sync from the panel. External versions get a re-timed copy (works both
    /// ways, unlike VLC's delay, which drops lines when set negative); embedded
    /// tracks can only use VLC's delay.
    func setOffset(_ milliseconds: Int) {
        offsetMilliseconds = milliseconds
        persistOffset(milliseconds)
        switch wanted {
        case .external(let track, _), .preparing(let track):
            offsetTask?.cancel()
            offsetTask = Task {
                try? await Task.sleep(for: .milliseconds(400))    // settle while tapping
                guard !Task.isCancelled else { return }
                bake(track, offset: milliseconds)
            }
        case .embedded:
            try? player?.setSubtitleDelay(.milliseconds(milliseconds))
        default:
            break
        }
    }


    // MARK: Translation (on device)

    #if canImport(Translation) && os(iOS)
    /// Handed to the player screen's `.translationTask`; setting it starts a run.
    private(set) var translationConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private var translationJob: (english: SubtitleTrack, file: URL, target: String)?

    /// English versions the translator can work from (SRT and VTT).
    func canTranslate(to target: String, player: Player) -> Bool {
        SubtitleLanguage.canonical(target) != "eng"
            && SubtitleLanguage.iso639_1(for: target) != nil
            && !translatableEnglish(player: player).isEmpty
    }

    private func translatableEnglish(player: Player) -> [SubtitleTrack] {
        versions(for: "eng", player: player).filter { track in
            let ext = ((track.fileName ?? "") as NSString).pathExtension.lowercased()
            return !["ass", "ssa", "sub"].contains(ext) && !track.isMachineTranslated
        }
    }

    /// Translates the English version that best fits this release. Its timing
    /// is kept exactly, which is the point: English versions are plentiful and
    /// usually match the release, so the result is in sync.
    func translate(to target: String, player: Player) {
        self.player = player
        guard translationProgress == nil else { return }
        let target = SubtitleLanguage.canonical(target)
        guard let code = SubtitleLanguage.iso639_1(for: target),
              let english = translatableEnglish(player: player).first else {
            statusMessage = "There are no English subtitles to translate for this title."
            return
        }
        let id = TranslatedSubtitles.id(englishID: english.id, target: target)
        if let cached = TranslatedSubtitles.cached(id: id) {
            if !available.contains(where: { $0.id == id }) { available.append(cached.track) }
            show(cached.track, original: cached.file)
            return
        }
        statusMessage = nil
        translationProgress = 0
        applyTask?.cancel()
        applyTask = Task { [provider] in
            guard let file = try? await provider.download(english) else {
                translationProgress = nil
                statusMessage = "The English subtitles didn't download, so there was nothing to translate."
                return
            }
            guard !Task.isCancelled else { translationProgress = nil; return }
            translationJob = (english, file, target)
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: code))
        }
    }

    /// One batch, off the main actor: only plain strings go in and out.
    // Running translation: filled as responses stream in.
    @ObservationIgnored private var translationCues: [SubtitleCue] = []
    /// For each distinct line, the cues that say it ("Yeah." appears dozens of times).
    @ObservationIgnored private var translationTargets: [[Int]] = []
    @ObservationIgnored private var translatedCount = 0
    @ObservationIgnored private var translationShownEarly = false
    @ObservationIgnored private var translationTrack: SubtitleTrack?

    /// Streams the translation: Apple's `translate(batch:)` hands back each
    /// line as it's done (the all-at-once call is slower). Only plain strings
    /// cross back to the main actor, in small groups.
    nonisolated private static func translateStreaming(
        _ texts: [String], with session: TranslationSession,
        onResults: @escaping @MainActor ([(Int, String)]) -> Void
    ) async throws {
        let requests = texts.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        var buffer: [(Int, String)] = []
        var lastFlush = Date()
        for try await response in session.translate(batch: requests) {
            if let id = response.clientIdentifier, let index = Int(id) {
                buffer.append((index, response.targetText))
            }
            if buffer.count >= 25 || Date().timeIntervalSince(lastFlush) > 0.4 {
                let flushed = buffer
                buffer.removeAll()
                lastFlush = Date()
                await onResults(flushed)
            }
        }
        if !buffer.isEmpty { await onResults(buffer) }
    }

    /// Runs inside the player's `.translationTask`. iOS asks to download the
    /// language the first time; after that it works offline.
    ///
    /// Lines from the current position come first, so the next few minutes
    /// are ready within seconds and appear on screen while the rest finishes.
    func runTranslation(_ session: TranslationSession) async {
        guard let job = translationJob else { return }
        translationJob = nil
        defer { translationConfiguration = nil }
        do {
            let text = try String(contentsOf: job.file, encoding: .utf8)
            let cues = SubtitleCues.parse(text)
            guard !cues.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

            // Order: from a few seconds before the playhead to the end, then the start.
            let playhead = Int((player?.currentTime.asSeconds ?? 0) * 1000)
            let first = cues.firstIndex { $0.startMilliseconds >= playhead - 5000 } ?? 0
            let order = Array(first..<cues.count) + Array(0..<first)

            var texts: [String] = []
            var targets: [[Int]] = []
            var slot: [String: Int] = [:]
            for index in order {
                let line = cues[index].plainText
                guard !line.isEmpty else { continue }
                if let existing = slot[line] {
                    targets[existing].append(index)
                } else {
                    slot[line] = texts.count
                    texts.append(line)
                    targets.append([index])
                }
            }

            translationCues = cues
            translationTargets = targets
            translatedCount = 0
            translationShownEarly = false
            translationTrack = TranslatedSubtitles.track(from: job.english, target: job.target, url: job.file)

            try await Self.translateStreaming(texts, with: session) { [weak self] results in
                self?.applyTranslated(results, total: texts.count)
            }

            guard let track = translationTrack else { return }
            _ = try TranslatedSubtitles.write(translationCues, track: track)
            guard let saved = TranslatedSubtitles.cached(id: track.id) else { throw CocoaError(.fileWriteUnknown) }
            available.removeAll { $0.id == saved.track.id }
            available.append(saved.track)
            translationProgress = nil
            show(saved.track, original: saved.file)
        } catch {
            translationProgress = nil
            statusMessage = "Translation didn't finish. If iOS asked to download the language, allow it and try again."
        }
        translationCues = []
        translationTargets = []
    }

    private func applyTranslated(_ results: [(Int, String)], total: Int) {
        for (slot, translated) in results where slot < translationTargets.count {
            for index in translationTargets[slot] { translationCues[index].text = translated }
        }
        translatedCount += results.count
        translationProgress = total > 0 ? Double(translatedCount) / Double(total) : 1

        // Once the next few minutes are done, put them on screen; the finished
        // file replaces this when everything is translated.
        let early = min(total, 60)
        if !translationShownEarly, translatedCount >= early, translatedCount < total,
           let track = translationTrack,
           let partial = try? TranslatedSubtitles.writePartial(translationCues, track: track) {
            translationShownEarly = true
            // Listed with the partial file, so picking it from the menu shows this too.
            let listed = SubtitleTrack(id: track.id, languageCode: track.languageCode, url: partial,
                                       fileName: track.fileName, encoding: track.encoding, fps: track.fps,
                                       provider: track.provider, downloads: 0,
                                       isHearingImpaired: track.isHearingImpaired, isMachineTranslated: true)
            available.removeAll { $0.id == track.id }
            available.append(listed)
            show(listed, original: partial)
        }
    }
    #endif

    // MARK: Versions (several subtitle files in one language)

    /// Every version in `languageCode`, best first: same frame rate as the
    /// video, then closest release name.
    func versions(for languageCode: String, player: Player) -> [SubtitleTrack] {
        SubtitlesProvider.candidates(in: available, language: languageCode,
                                     release: context?.releaseName,
                                     videoFPS: player.videoTracks.first?.frameRate)
    }

    /// The external subtitle showing now (or being switched to).
    var selectedTrack: SubtitleTrack? {
        selectedID.flatMap { id in available.first { $0.id == id } }
    }

    /// The offset set for this version, this session or last time.
    func savedOffset(for track: SubtitleTrack) -> Int? {
        let key = "ext:\(track.id)"
        if let value = sessionDelays[key] { return value }
        guard memory?.trackKey == key else { return nil }
        return memory?.delayMilliseconds
    }

    /// The version this episode used last time.
    var lastKeptID: String? {
        guard let key = memory?.trackKey, key.hasPrefix("ext:") else { return nil }
        return String(key.dropFirst(4))
    }

    func selectEmbedded(_ track: Track, on player: Player) {
        self.player = player
        applyTask?.cancel()
        statusMessage = nil
        selectedID = nil
        embeddedID = track.id
        wanted = .embedded(track.id)
        enforcedGeneration = generation
        player.selectedSubtitleTrack = track
        trackBecameActive("emb:\(track.id)", language: track.language, player: player)
    }

    /// Subtitle sync is remembered per episode, source and version, and put
    /// back the next time it plays.
    private func persistOffset(_ milliseconds: Int) {
        guard let context else { return }
        if let activeTrackKey { sessionDelays[activeTrackKey] = milliseconds }
        SubtitleMemory.setDelay(milliseconds, trackKey: activeTrackKey, for: context)
        memory = SubtitleMemory.entry(for: context)
        delayGeneration = generation
    }

    /// A new track is showing: remember it, and use the offset saved for it
    /// (a different file starts from zero).
    private func trackBecameActive(_ key: String, language: String?, player: Player) {
        guard key != activeTrackKey else { return }
        activeTrackKey = key
        guard let context else { return }
        let saved = sessionDelays[key] ?? (memory?.trackKey == key ? (memory?.delayMilliseconds ?? 0) : 0)
        SubtitleMemory.remember(trackKey: key, language: language, for: context)
        if saved != 0 { SubtitleMemory.setDelay(saved, trackKey: key, for: context) }
        memory = SubtitleMemory.entry(for: context)
        offsetMilliseconds = saved
        // External versions already carry their sync in the file, except
        // frame-based .sub files, which keep VLC's delay like embedded tracks.
        var usesPlayerDelay = key.hasPrefix("emb:")
        if case .external(_, let url) = wanted, url.pathExtension.lowercased() == "sub" { usesPlayerDelay = true }
        try? player.setSubtitleDelay(.milliseconds(usesPlayerDelay ? saved : 0))
        delayGeneration = generation
    }

    func embeddedTracks(of player: Player) -> [Track] {
        var seen = Set<String>()
        return player.subtitleTracks.filter {
            !externalTrackIDs.contains($0.id) && seen.insert($0.id).inserted
        }
    }

    // MARK: Keeping the player in line

    private func reconcile() {
        guard let player else { return }
        let state = player.state
        guard state == .opening || state == .buffering || state == .playing || state == .paused else { return }
        if state == .playing, playingSince == nil { playingSince = Date() }
        // Give the video's own tracks a moment to register after playback starts,
        // so a new external track can be told apart from them.
        let tracksSettled = playingSince.map { Date().timeIntervalSince($0) >= 0.8 } ?? false

        // After a reopen, put the offset back once the same track is showing again.
        if tracksSettled, delayGeneration != generation, let activeTrackKey,
           activeTrackKey.hasPrefix("emb:"), memory?.trackKey == activeTrackKey {
            delayGeneration = generation
            try? player.setSubtitleDelay(.milliseconds(memory?.delayMilliseconds ?? 0))
        }

        switch wanted {
        case .undecided:
            guard tracksSettled else { return }
            if !embeddedChecked {
                embeddedChecked = true
                let rememberedEmbedded = memory?.trackKey.flatMap { key in
                    key.hasPrefix("emb:") ? embeddedTracks(of: player).first { "emb:\($0.id)" == key } : nil
                }
                if let match = rememberedEmbedded ?? preferredEmbeddedTrack(in: player) {
                    embeddedID = match.id
                    selectedID = nil
                    wanted = .embedded(match.id)
                    enforcedGeneration = generation
                    player.selectedSubtitleTrack = match
                    trackBecameActive("emb:\(match.id)", language: match.language, player: player)
                    return
                }
            }
            // Now the video's frame rate is known: a file timed for another
            // frame rate drifts further off the longer it plays, so swap it for
            // one that matches when there is one.
            if !fpsChecked, let file = preferredFile, let context,
               let videoFPS = player.videoTracks.first?.frameRate, videoFPS > 1 {
                fpsChecked = true
                if let subFPS = file.track.fps, abs(subFPS - videoFPS) > 0.3,
                   let better = SubtitlesProvider.candidates(in: available, language: preferred,
                                                             release: context.releaseName, videoFPS: videoFPS)
                    .first(where: { $0.fps.map { abs($0 - videoFPS) < 0.05 } ?? false }) {
                    preferredFile = nil
                    preferredLookupDone = false
                    fetchTask = Task { [provider] in
                        if let url = try? await provider.download(better) {
                            preferredFile = (better, url)
                        } else {
                            preferredFile = file
                        }
                        preferredLookupDone = true
                        reconcile()
                    }
                    return
                }
            }
            if let preferredFile {
                show(preferredFile.track, original: preferredFile.file)
            } else if preferredLookupDone {
                wanted = .off
                if !preferred.isEmpty {
                    statusMessage = "No \(SubtitleLanguage.displayName(for: preferred)) subtitles found for this title. You can translate the English ones below."
                }
                enforceOff(in: player, settled: tracksSettled)
            }

        case .off:
            enforceOff(in: player, settled: tracksSettled)

        case .embedded(let id):
            guard tracksSettled, enforcedGeneration != generation else { return }
            enforcedGeneration = generation
            if let track = player.subtitleTracks.first(where: { $0.id == id }), !track.isSelected {
                player.selectedSubtitleTrack = track
            }

        case .external(_, let url):
            ensureAttached(url, in: player, settled: tracksSettled)

        case .preparing:
            break                       // the bake calls back when the copy is ready
        }
    }

    /// VLC can switch on a "default" subtitle by itself. When the viewer wants
    /// none, turn it off once per opened media (and never fight them after).
    private func enforceOff(in player: Player, settled: Bool) {
        guard settled, enforcedGeneration != generation else { return }
        enforcedGeneration = generation
        if player.selectedSubtitleTrack != nil { player.selectedSubtitleTrack = nil }
    }

    private func ensureAttached(_ url: URL, in player: Player, settled: Bool) {
        if let id = attachedTracks[url] {
            guard let track = player.subtitleTracks.first(where: { $0.id == id }) else {
                attachedTracks[url] = nil          // gone with a reopen; attach again
                return
            }
            if !track.isSelected, enforcedGeneration != generation {
                enforcedGeneration = generation
                player.selectedSubtitleTrack = track
            }
            if case .external(let chosen, _) = wanted {
                trackBecameActive("ext:\(chosen.id)", language: chosen.languageCode, player: player)
            }
            return
        }

        // Adopt the track of an earlier attach, however long VLC took (it waits
        // while a torrent stream is buffering).
        if let pending = pendingAttach, pending.generation == generation {
            let added = player.subtitleTracks.filter {
                !pending.before.contains($0.id) && !externalTrackIDs.contains($0.id)
            }
            if let track = added.first(where: \.isSelected) ?? added.last {
                externalTrackIDs.insert(track.id)
                attachedTracks[pending.url] = track.id
                pendingAttach = nil
                if pending.url == url {
                    enforcedGeneration = generation
                    if !track.isSelected { player.selectedSubtitleTrack = track }
                    if case .external(let chosen, _) = wanted {
                        trackBecameActive("ext:\(chosen.id)", language: chosen.languageCode, player: player)
                    }
                }
                return                                   // a newer file attaches on the next pass
            }
            // Wait for it (up to 12 s) even when a newer file is wanted, so a late
            // track can't be taken for the newer one.
            if Date().timeIntervalSince(pending.at) < 12 { return }
            pendingAttach = nil
        }

        guard settled || player.state == .paused else { return }
        let attempts = attemptsByURL[url, default: 0]
        guard attempts < 3 else { return }
        let before = Set(player.subtitleTracks.map(\.id))
        do {
            try player.addExternalTrack(from: url, type: .subtitle, select: true)
        } catch {
            return                                       // no input yet; the loop retries
        }
        attemptsByURL[url] = attempts + 1
        pendingAttach = (url, before, generation, Date())
    }

    /// A subtitle track inside the video in the default language. Embedded
    /// tracks are always in sync, so they win over downloaded ones. "Forced"
    /// tracks only carry signs and foreign dialogue, so they don't count.
    private func preferredEmbeddedTrack(in player: Player) -> Track? {
        guard !preferred.isEmpty else { return nil }
        let name = SubtitleLanguage.displayName(for: preferred).lowercased()
        let matches = embeddedTracks(of: player).filter { track in
            let label = "\(track.name) \(track.trackDescription ?? "")".lowercased()
            if label.contains("forced") || label.contains("signs") { return false }
            if let lang = track.language, !lang.isEmpty, SubtitleLanguage.canonical(lang) == preferred {
                return true
            }
            return !name.isEmpty && label.contains(name)
        }
        return matches.first
    }

    var byLanguage: [(language: String, tracks: [SubtitleTrack])] {
        let groups = Dictionary(grouping: available, by: \.languageName)
        return groups
            .map { (language: $0.key, tracks: $0.value) }
            .sorted { lhs, rhs in
                let l = available.firstIndex { $0.languageName == lhs.language } ?? 0
                let r = available.firstIndex { $0.languageName == rhs.language } ?? 0
                return l < r
            }
    }
}

/// What each episode (or movie) showed on each source: which subtitle version
/// or embedded track, and the sync offset set for it. Every source is its own
/// release with its own timing, so each keeps its own choice; a source played
/// for the first time starts from the language last chosen for the episode.
enum SubtitleMemory {
    struct Entry: Codable {
        var trackKey: String?          // "ext:<OpenSubtitles id>" or "emb:<VLC track id>"
        var language: String?
        var delayMilliseconds: Int = 0
        var lastUsed: Double = 0
    }

    private static let key = "subtitleMemory"
    private static let limit = 400

    static func entry(for context: SubtitleContext) -> Entry? {
        load()[id(context)]
    }

    /// The language last chosen for this episode on any source.
    static func episodeLanguage(for context: SubtitleContext) -> String? {
        guard context.sourceKey != nil else { return nil }
        return load()[episodeID(context)]?.language
    }

    /// Records the track now showing. Keeps the offset only if it's the same track.
    static func remember(trackKey: String, language: String?, for context: SubtitleContext) {
        var all = load()
        var entry = all[id(context)] ?? Entry()
        if entry.trackKey != trackKey { entry.delayMilliseconds = 0 }
        entry.trackKey = trackKey
        entry.language = language
        entry.lastUsed = Date().timeIntervalSince1970
        all[id(context)] = entry
        if context.sourceKey != nil, let language {
            all[episodeID(context)] = Entry(trackKey: nil, language: language, lastUsed: entry.lastUsed)
        }
        save(all)
    }

    static func hasChoice(for context: SubtitleContext) -> Bool {
        load()[id(context)]?.trackKey != nil
    }

    /// Sources of this episode that have a saved subtitle choice.
    static func sourcesWithChoice(for context: SubtitleContext) -> Set<String> {
        let prefix = episodeID(context) + "|"
        return Set(load().compactMap { key, entry in
            key.hasPrefix(prefix) && entry.trackKey != nil ? String(key.dropFirst(prefix.count)) : nil
        })
    }

    static func forgetTrack(for context: SubtitleContext) {
        var all = load()
        all[id(context)] = nil
        all[episodeID(context)] = nil
        save(all)
    }

    static func setDelay(_ milliseconds: Int, trackKey: String?, for context: SubtitleContext) {
        var all = load()
        var entry = all[id(context)] ?? Entry()
        if let trackKey { entry.trackKey = trackKey }
        entry.delayMilliseconds = milliseconds
        entry.lastUsed = Date().timeIntervalSince1970
        all[id(context)] = entry
        save(all)
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all
    }

    private static func save(_ all: [String: Entry]) {
        var trimmed = all
        if trimmed.count > limit {
            for (key, _) in trimmed.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }).prefix(trimmed.count - limit) {
                trimmed[key] = nil
            }
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func id(_ context: SubtitleContext) -> String {
        guard let source = context.sourceKey else { return episodeID(context) }
        return "\(episodeID(context))|\(source)"
    }

    private static func episodeID(_ context: SubtitleContext) -> String {
        guard let season = context.season, let episode = context.episode else { return context.imdbID }
        return "\(context.imdbID):\(season):\(episode)"
    }
}
