//
//  Theme.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI
import UIKit

/// Design tokens: "Noir Lumière". True black, lit only by the artwork; New York
/// serif for titles, SF Pro for everything else; one warm "projector white" for
/// the thing to do and for progress. Colour never sits on artwork; state is text.
enum Theme {
    // MARK: Colour

    /// The screen itself: true black, so artwork carries all the colour.
    static let background = Color.black
    /// Rows, fields and panels (opaque: they also sit over video).
    static let surface = Color(white: 0.06)
    /// Surfaces on surfaces: expanded groups, pressed rows.
    static let elevated = Color(white: 0.10)
    /// Hairline separators and outlines.
    static let hairline = Color.white.opacity(0.12)
    static let textSecondary = Color.white.opacity(0.64)
    /// 46%: still 4.5:1 on black.
    static let textTertiary = Color.white.opacity(0.46)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

    /// "Projector white": the primary action and progress. Yellow is retired.
    static let defaultAccentHex = "F3EFE7"

    // Parsed once. These used to be recomputed (hex parse plus a UIKit colour
    // conversion) on every read, including inside long lists.
    static let accent: Color = Color(hex: defaultAccentHex)
    static let onAccent: Color = accent.contrastingForeground

    /// One horizontal margin on iPhone.
    static let gutter: CGFloat = 20

    // MARK: Shape (radius follows hierarchy: the bigger the thing, the rounder)

    static let stillCorner: CGFloat = 6
    static let posterCorner: CGFloat = 8
    static let rowCorner: CGFloat = 12
    static let cardCorner: CGFloat = 16
    static let posterAspect: CGFloat = 2.0 / 3.0
    /// CinemaScope: the hero and title-page frames.
    static let scopeAspect: CGFloat = 2.39

    // MARK: Motion (only in answer to a touch)

    /// Presses and toggles.
    static let snappy = Animation.snappy(duration: 0.22)
    /// Expanding, collapsing, switching sections.
    static let smooth = Animation.smooth(duration: 0.32)
}

// MARK: - Type

extension Font {
    /// New York, the serif: page, section and title-page titles, and the Top 10
    /// numerals. Scales with Dynamic Type relative to `style`; heavy weights
    /// from the old condensed display face settle to medium.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium,
                        relativeTo style: UIFont.TextStyle = .title1) -> Font {
        let heavy: [Font.Weight] = [.heavy, .black, .bold, .semibold]
        let tone: Font.Weight = heavy.contains(weight) ? .medium : weight
        return .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: tone, design: .serif)
    }

    /// Synopses: New York at body size.
    static let synopsis = Font.system(.body, design: .serif)
}

extension View {
    /// Section title on the dark canvas: New York, one size everywhere.
    func sectionTitleStyle() -> some View {
        font(.display(24, weight: .regular, relativeTo: .title2))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
    }

    /// Glass for controls that sit over imagery or video, never on plain black.
    @ViewBuilder
    func glassChrome<S: Shape>(in shape: S) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                .environment(\.colorScheme, .dark)
        }
        #else
        background(.ultraThinMaterial, in: shape)
        #endif
    }
}
