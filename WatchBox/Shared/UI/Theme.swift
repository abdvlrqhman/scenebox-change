//
//  Theme.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI

/// Design tokens. Artwork carries the colour; chrome stays quiet. The marquee
/// yellow means one of two things only: "do this" (primary actions) or "this is
/// moving" (progress, selection).
enum Theme {
    // MARK: Colour

    /// Ink: the screen itself.
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    /// Raised surfaces: rows, cards, fields.
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)
    /// Surfaces on surfaces: expanded groups, pressed rows.
    static let elevated = Color(red: 0.145, green: 0.145, blue: 0.18)
    /// Hairline separators and outlines.
    static let hairline = Color.white.opacity(0.08)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

    static let defaultAccentHex = "EEE600"

    // Parsed once. These used to be recomputed (hex parse plus a UIKit colour
    // conversion) on every read, including inside long lists.
    static let accent: Color = Color(hex: defaultAccentHex)
    static let onAccent: Color = accent.contrastingForeground

    static let accentPresets: [String] = [
        "EEE600",
        "FFD60A",
        "FF9F0A",
        "FF7A00",
        "FF453A",
        "FF375F",
        "BF5AF2",
        "5E5CE6",
        "0A84FF",
        "64D2FF",
        "30D158",
        "66D4CF",
    ]

    // MARK: Shape (radius follows hierarchy: the bigger the thing, the rounder)

    static let posterCorner: CGFloat = 10
    static let rowCorner: CGFloat = 14
    static let cardCorner: CGFloat = 18
    static let posterAspect: CGFloat = 2.0 / 3.0

    // MARK: Motion (only in answer to a touch)

    /// Presses and toggles.
    static let snappy = Animation.snappy(duration: 0.22)
    /// Expanding, collapsing, switching sections.
    static let smooth = Animation.smooth(duration: 0.32)
}

// MARK: - Type

extension Font {
    /// Condensed heavy display type, like a poster's billing block. Used for
    /// page and section titles and the featured title; everything else is SF Pro.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

extension View {
    /// Section title on the dark canvas.
    func sectionTitleStyle() -> some View {
        font(.display(24, weight: .bold))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
    }
}
