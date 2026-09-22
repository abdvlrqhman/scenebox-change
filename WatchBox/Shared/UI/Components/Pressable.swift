//
//  Pressable.swift
//  SceneBox
//

import SwiftUI

/// Tactile press for artwork and cards: a slight shrink and dim that follows the
/// finger, so every tappable image answers the touch.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .animation(Theme.snappy, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Section title with an optional trailing control ("See all", a menu, …).
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .sectionTitleStyle()
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Badges

/// "You've seen this." Neutral white: it's a fact, not an action.
struct WatchedBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.5, weight: .black))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .accessibilityLabel("Watched")
    }
}

/// "This is on the device."
struct DownloadedBadge: View {
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: size * 0.5, weight: .black))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Theme.success, in: Circle())
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .accessibilityLabel("Downloaded")
    }
}

/// Thin progress line laid over the bottom of artwork.
struct ArtworkProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(Theme.accent)
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int(fraction * 100)) percent watched")
    }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var systemImage: String = "checkmark.circle.fill"
}

extension View {
    /// Brief confirmation at the bottom of the screen that clears itself.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Label(message.text, systemImage: message.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                        .padding(.bottom, 24)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(message.id)
                        .task(id: message.id) {
                            try? await Task.sleep(for: .seconds(2.6))
                            withAnimation(Theme.smooth) { self.message = nil }
                        }
                        .onTapGesture { withAnimation(Theme.smooth) { self.message = nil } }
                }
            }
            .animation(Theme.smooth, value: message)
            .sensoryFeedback(.success, trigger: message?.id) { _, new in new != nil }
    }
}
