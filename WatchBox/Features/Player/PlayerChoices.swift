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
    static var audioLanguage: String?
    /// Subtitle language picked in the panel ("" = Off); nil until the viewer picks one.
    static var subtitleLanguage: String?

    static func reset() {
        rate = 1
        aspect = nil
        audioLanguage = nil
        subtitleLanguage = nil
    }
}
