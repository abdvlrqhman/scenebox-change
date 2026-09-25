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
    @ObservationIgnored private var wanted: Wanted = .undecided {
        didSet {
            var file: URL?
            if case .external(_, let url) = wanted { file = url }
            if file != fileOnScreen { fileOnScreen = file }
        }
    }
    /// The subtitle file showing now, sync written in: what a TV gets.
    private(set) var fileOnScreen: URL?
    @ObservationIgnored private var preferredFile: (track: SubtitleTrack, file: URL)?
    @ObservationIgnored private var preferredLookupDone = false
    @ObservationIgnored private var embeddedChecked = false
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?

    // Per opened media ("generation"): VLC throws external tracks away whenever
    // the stream is reopened, so everything attached is remembered per open.
    /// Set by "Translate": the first translated lines go on screen when ready,
    /// unless the viewer picks something else first.
    @ObservationIgnored private var showsFirstTranslatedLines = false

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
            // Translations finished on this device for this episode are
            // versions like any other.
            let targets = Set([self.preferred, SubtitleMemory.episodeLanguage(for: context) ?? ""]
                .map(SubtitleLanguage.canonical)).filter { !$0.isEmpty && $0 != "eng" }
            let englishIDs = tracks.filter { SubtitleLanguage.canonical($0.languageCode) == "eng" }.map(\.id)
            for englishID in englishIDs {
                for target in targets {
                    let id = TranslatedSubtitles.id(englishID: englishID, target: target)
                    if let cached = TranslatedSubtitles.cached(id: id) { tracks.append(cached.track) }
                }
            }
            // A translation made on this device: finished, or as far as it got
            // (it carries on in the background and updates here).
            if let rememberedID, rememberedID.hasPrefix(TranslatedSubtitles.idPrefix) {
                var found: (track: SubtitleTrack, file: URL)?
                if let cached = TranslatedSubtitles.cached(id: rememberedID) {
                    found = cached
                } else if let saved = TranslationCenter.loadWork(id: rememberedID),
                          let url = TranslationCenter.shared.currentFile(for: rememberedID) {
                    found = (TranslatedSubtitles.track(from: saved.english, target: saved.target, url: url), url)
                    #if canImport(Translation) && os(iOS)
                    followedTranslation = (rememberedID, saved.english, saved.target)
                    #endif
                }
                if let found {
                    tracks.removeAll { $0.id == found.track.id }
                    tracks.append(found.track)
                    available = tracks
                    preferredFile = found
                    preferredLookupDone = true
                    isLoading = false
                    reconcile()
                    return
                }
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
        showsFirstTranslatedLines = false
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


    // MARK: Translation (on device, run by TranslationCenter)

    #if canImport(Translation) && os(iOS)
    /// Used only to download the language the first time: the prompt has to
    /// come from the visible player. The translating itself runs app-wide.
    private(set) var prepareConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private var pendingTranslation: (english: SubtitleTrack, file: URL, target: String,
                                                          code: String, startAt: Int)?
    /// The translation this player shows or waits for.
    @ObservationIgnored private var followedTranslation: (id: String, english: SubtitleTrack, target: String)?
    @ObservationIgnored private var shownTranslationRevision = -1

    /// English versions the translator can work from (SRT and VTT).
    func canTranslate(to target: String, player: Player) -> Bool {
        SubtitleLanguage.canonical(target) != "eng"
            && SubtitleLanguage.iso639_1(for: target) != nil
            && translationSource(for: target, player: player) != nil
    }

    func translationState(to target: String, player: Player) -> TranslationCenter.State {
        guard let id = translationID(for: target, player: player) else { return .none }
        return TranslationCenter.shared.state(for: id)
    }

    func translationError(to target: String, player: Player) -> String? {
        translationID(for: target, player: player).flatMap { TranslationCenter.shared.lastError[$0] }
    }

    private func translationID(for target: String, player: Player) -> String? {
        translationSource(for: target, player: player).map {
            TranslatedSubtitles.id(englishID: $0.id, target: SubtitleLanguage.canonical(target))
        }
    }

    private func translatableEnglish(player: Player) -> [SubtitleTrack] {
        versions(for: "eng", player: player).filter { track in
            let ext = ((track.fileName ?? "") as NSString).pathExtension.lowercased()
            return !["ass", "ssa", "sub"].contains(ext) && !track.isMachineTranslated
        }
    }

    /// A translation already begun for this episode keeps its English source,
    /// so "Continue" picks up the same one.
    private func translationSource(for target: String, player: Player) -> SubtitleTrack? {
        let target = SubtitleLanguage.canonical(target)
        if let followed = followedTranslation, followed.target == target { return followed.english }
        let prefix = "\(TranslatedSubtitles.idPrefix)\(target)-"
        if let kept = lastKeptID, kept.hasPrefix(prefix) {
            let englishID = String(kept.dropFirst(prefix.count))
            if let english = available.first(where: { $0.id == englishID }) { return english }
        }
        return translatableEnglish(player: player).first
    }

    /// Translates (or continues translating) the English version that best
    /// fits this release. Its timing is kept exactly, so the result is in
    /// sync; sentences split across lines are translated whole.
    func translate(to target: String, player: Player) {
        self.player = player
        let target = SubtitleLanguage.canonical(target)
        guard let code = SubtitleLanguage.iso639_1(for: target),
              let english = translationSource(for: target, player: player) else {
            statusMessage = "There are no English subtitles to translate for this title."
            return
        }
        let id = TranslatedSubtitles.id(englishID: english.id, target: target)
        followedTranslation = (id, english, target)
        shownTranslationRevision = TranslationCenter.shared.updates[id]?.revision ?? -1
        statusMessage = nil

        if let cached = TranslatedSubtitles.cached(id: id) {
            showTranslated(id: id, english: english, target: target, url: cached.file)
            return
        }
        // What's translated so far goes on screen while the rest continues;
        // with nothing yet, the first lines go on screen the moment they exist.
        if let partial = TranslationCenter.shared.currentFile(for: id) {
            showTranslated(id: id, english: english, target: target, url: partial)
        } else {
            showsFirstTranslatedLines = true
        }
        let startAt = Int(player.currentTime.asSeconds * 1000)
        applyTask?.cancel()
        applyTask = Task { [provider] in
            guard let file = try? await provider.download(english) else {
                statusMessage = "The English subtitles didn't download, so there was nothing to translate."
                return
            }
            guard !Task.isCancelled else { return }
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"),
                                                             to: Locale.Language(identifier: code))
            switch status {
            case .installed:
                TranslationCenter.shared.enqueue(english: english, file: file, target: target,
                                                 code: code, startAt: startAt)
            case .supported:
                // Needs the one-time language download first.
                pendingTranslation = (english, file, target, code, startAt)
                prepareConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: code))
            default:
                statusMessage = "This iPhone can't translate English to \(SubtitleLanguage.displayName(for: target))."
            }
        }
    }

    /// Runs in the player's `.translationTask` so iOS can show its download prompt.
    func prepareLanguage(_ session: TranslationSession) async {
        defer { prepareConfiguration = nil }
        guard let pending = pendingTranslation else { return }
        pendingTranslation = nil
        do {
            try await session.prepareTranslation()
            TranslationCenter.shared.enqueue(english: pending.english, file: pending.file, target: pending.target,
                                             code: pending.code, startAt: pending.startAt)
        } catch {
            statusMessage = "The language wasn't downloaded, so the translation didn't start."
        }
    }

    private func showTranslated(id: String, english: SubtitleTrack, target: String, url: URL) {
        let track = TranslatedSubtitles.track(from: english, target: target, url: url)
        list(track)
        show(track, original: url)
    }

    /// Keeps the translation in the versions list while it's being made, and
    /// swaps in newer lines as they arrive while the viewer is on it.
    private func followTranslation() {
        adoptRunningTranslation()
        guard let followed = followedTranslation,
              let update = TranslationCenter.shared.updates[followed.id],
              update.revision > shownTranslationRevision else { return }
        shownTranslationRevision = update.revision
        if selectedID == followed.id || showsFirstTranslatedLines {
            showsFirstTranslatedLines = false
            showTranslated(id: followed.id, english: followed.english, target: followed.target, url: update.url)
        } else {
            list(TranslatedSubtitles.track(from: followed.english, target: followed.target, url: update.url))
        }
    }

    /// A translation started earlier for this episode (then the player was
    /// closed) is listed among the versions as far as it has got.
    private func adoptRunningTranslation() {
        guard followedTranslation == nil,
              let job = TranslationCenter.shared.runningJob,
              available.contains(where: { $0.id == job.english.id }) else { return }
        followedTranslation = (job.id, job.english, job.target)
        shownTranslationRevision = -1
        if TranslationCenter.shared.updates[job.id] == nil,
           let partial = TranslationCenter.shared.currentFile(for: job.id) {
            list(TranslatedSubtitles.track(from: job.english, target: job.target, url: partial))
        }
    }

    private func list(_ track: SubtitleTrack) {
        if let index = available.firstIndex(where: { $0.id == track.id }) {
            available[index] = track
        } else {
            available.append(track)
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
        showsFirstTranslatedLines = false
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
        #if canImport(Translation) && os(iOS)
        followTranslation()
        #endif
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
