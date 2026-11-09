//
//  PlayerChoices.swift
//  SceneBox
//

import SwiftVLC

/// What the viewer picked in the player, carried to the next episode (each one
/// gets a fresh player) and forgotten when the player closes.
@MainActor
enum PlayerChoices {
    static var rate: Float = 1
    static var aspect: AspectRatio?
    /// Voice sync in milliseconds (positive: the voice plays later). Releases of one show
    /// usually share the offset, so it carries to the next episode.
    static var audioDelayMs = 0

    static func reset() {
        rate = 1
        aspect = nil
        audioDelayMs = 0
    }
}

/// The voice and subtitles picked for a show, kept on the phone: the next episode,
/// closing the player and coming back another day all open the same way.
/// Subtitles "" means Off; nil means nothing picked yet (the Settings defaults apply).
nonisolated enum ShowLanguages {
    private static let key = "SBShowLanguages"

    static func audio(for show: String?) -> String? { value("audio", show) }
    static func subtitles(for show: String?) -> String? { value("subtitles", show) }
    static func setAudio(_ code: String?, for show: String?) { set("audio", code, show) }
    static func setSubtitles(_ code: String?, for show: String?) { set("subtitles", code, show) }

    private static func value(_ field: String, _ show: String?) -> String? {
        guard let show, !show.isEmpty else { return nil }
        return stored[show]?[field]
    }

    private static func set(_ field: String, _ value: String?, _ show: String?) {
        guard let show, !show.isEmpty else { return }
        var all = stored
        var entry = all[show] ?? [:]
        entry[field] = value
        all[show] = entry
        UserDefaults.standard.set(all, forKey: key)
    }

    private static var stored: [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
    }
}
