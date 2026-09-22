//
//  SubtitlesController.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation
import Observation
import SwiftVLC

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

    private enum Wanted: Equatable {
        case undecided                  // default language not resolved yet
        case off
        case embedded(String)           // track id inside the video
        case external(SubtitleTrack, URL)
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
    @ObservationIgnored private var attaching = false
    @ObservationIgnored private var attachAttempts = 0
    @ObservationIgnored private var lastAttachAttempt = Date.distantPast
    @ObservationIgnored private var enforcedGeneration = -1
    @ObservationIgnored private var delayGeneration = -1

    // MARK: Lifecycle

    func load(context: SubtitleContext, preferred: String, player: Player) {
        self.player = player
        guard !loaded else { reconcile(); return }
        loaded = true
        self.context = context
        self.preferred = SubtitleLanguage.canonical(preferred)
        if self.preferred.isEmpty { wanted = .off }

        isLoading = true
        fetchTask = Task { [provider] in
            let tracks = await provider.subtitles(for: context)
            guard !Task.isCancelled else { return }
            available = tracks
            if !self.preferred.isEmpty {
                preferredFile = await provider.bestFile(for: context, language: self.preferred, tracks: tracks)
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
                attachAttempts = 0
                lastAttachAttempt = .distantPast
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

    func apply(_ track: SubtitleTrack?, on player: Player) {
        self.player = player
        applyTask?.cancel()
        statusMessage = nil
        embeddedID = nil
        guard let track else {
            wanted = .off
            selectedID = nil
            player.selectedSubtitleTrack = nil
            return
        }
        selectedID = track.id
        applyTask = Task { [provider, context] in
            // The chosen file first, then other files in the same language.
            var file: (SubtitleTrack, URL)?
            if let url = try? await provider.download(track) {
                file = (track, url)
            } else if let context,
                      let fallback = await provider.bestFile(
                        for: context, language: track.languageCode,
                        tracks: available.filter { $0.id != track.id }) {
                file = fallback
            }
            guard !Task.isCancelled else { return }
            guard let (chosen, url) = file else {
                selectedID = nil
                statusMessage = "Couldn't download \(track.languageName) subtitles. Try another language or try again."
                return
            }
            selectedID = chosen.id
            wanted = .external(chosen, url)
            enforcedGeneration = -1
            reconcile()
        }
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
    }

    /// Subtitle sync is remembered per episode (or movie) and put back the
    /// next time it plays.
    func saveDelay(milliseconds: Int) {
        guard let context else { return }
        SubtitleDelayStore.set(milliseconds, for: context)
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

        if tracksSettled, delayGeneration != generation {
            delayGeneration = generation
            if let context, let saved = SubtitleDelayStore.milliseconds(for: context), saved != 0 {
                try? player.setSubtitleDelay(.milliseconds(saved))
            }
        }

        switch wanted {
        case .undecided:
            guard tracksSettled else { return }
            if !embeddedChecked {
                embeddedChecked = true
                if let match = preferredEmbeddedTrack(in: player) {
                    embeddedID = match.id
                    selectedID = nil
                    wanted = .embedded(match.id)
                    enforcedGeneration = generation
                    player.selectedSubtitleTrack = match
                    return
                }
            }
            if let preferredFile {
                selectedID = preferredFile.track.id
                wanted = .external(preferredFile.track, preferredFile.file)
                ensureAttached(preferredFile.file, in: player, settled: tracksSettled)
            } else if preferredLookupDone {
                wanted = .off
                if !preferred.isEmpty {
                    statusMessage = "No \(SubtitleLanguage.displayName(for: preferred)) subtitles found for this title."
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
            return
        }
        guard settled || player.state == .paused else { return }
        guard !attaching, attachAttempts < 4,
              Date().timeIntervalSince(lastAttachAttempt) > 5 else { return }

        attaching = true
        attachAttempts += 1
        lastAttachAttempt = Date()
        let startedIn = generation
        let before = Set(player.subtitleTracks.map(\.id))
        do {
            try player.addExternalTrack(from: url, type: .subtitle, select: true)
        } catch {
            attaching = false                       // no input yet; the loop retries
            return
        }

        Task { [weak self, weak player] in
            for _ in 0..<40 {                        // up to 8 s for VLC to parse it
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let player else { return }
                guard self.generation == startedIn else { self.attaching = false; return }
                let added = player.subtitleTracks.filter { !before.contains($0.id) }
                if let track = added.first(where: \.isSelected) ?? added.last {
                    self.externalTrackIDs.insert(track.id)
                    self.attachedTracks[url] = track.id
                    self.enforcedGeneration = self.generation
                    if !track.isSelected { player.selectedSubtitleTrack = track }
                    self.attaching = false
                    return
                }
            }
            self?.attaching = false                  // try again on a later pass
        }
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

/// Per-episode subtitle offsets, in milliseconds, kept in user defaults.
enum SubtitleDelayStore {
    private static let key = "subtitleDelays"
    private static let limit = 400

    static func milliseconds(for context: SubtitleContext) -> Int? {
        (UserDefaults.standard.dictionary(forKey: key)?[id(context)] as? [Any])?.first as? Int
    }

    static func set(_ milliseconds: Int, for context: SubtitleContext) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        if milliseconds == 0 {
            all[id(context)] = nil
        } else {
            // [offset, last used] so the oldest entries can be dropped.
            all[id(context)] = [milliseconds, Date().timeIntervalSince1970]
        }
        if all.count > limit {
            let oldest = all.sorted {
                (($0.value as? [Any])?.last as? Double ?? 0) < (($1.value as? [Any])?.last as? Double ?? 0)
            }
            for (key, _) in oldest.prefix(all.count - limit) { all[key] = nil }
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    private static func id(_ context: SubtitleContext) -> String {
        guard let season = context.season, let episode = context.episode else { return context.imdbID }
        return "\(context.imdbID):\(season):\(episode)"
    }
}
