//
//  HairlineScrubber.swift
//  SceneBox
//

#if !os(tvOS)
import SwiftUI

/// The player's scrubber: a 3 pt hairline with a projector-white thumb that
/// grows under the finger. 44 pt tall to grab; VoiceOver sees a slider.
struct HairlineScrubber: View {
    /// Position as a fraction, 0...1.
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let x = width * min(max(value, 0), 1)
            let thumb: CGFloat = dragging ? 22 : 14
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
                Capsule().fill(Theme.accent).frame(width: x, height: 3)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.35), radius: 4)
                    .offset(x: x - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        value = min(max(drag.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 44)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Theme.snappy, value: dragging)
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
        }
    }
}
#endif
