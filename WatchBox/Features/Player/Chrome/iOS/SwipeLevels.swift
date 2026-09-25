//
//  SwipeLevels.swift
//  SceneBox
//

#if os(iOS)
import AVFoundation
import MediaPlayer
import SwiftUI
import SwiftVLC
import UIKit

/// Swiping up and down on the video in landscape: the left half sets the
/// screen brightness, the right half the volume. Volume is the phone's own,
/// the same one the side buttons move, so the two never disagree.
@MainActor @Observable
final class SwipeLevels {
    enum Kind: Equatable { case brightness, volume }

    struct Shown: Equatable {
        let kind: Kind
        let value: Double
    }

    /// What the on-screen indicator shows; nil hides it.
    private(set) var shown: Shown?
    /// Goes up each time a swipe reaches 0% or 100%, for a light tap.
    private(set) var limitHits = 0

    /// The hidden system volume control; setting its slider sets the volume.
    @ObservationIgnored weak var volumeView: MPVolumeView?
    /// Used for volume only if the system control can't be found.
    @ObservationIgnored weak var player: Player?

    private enum Axis { case vertical, horizontal }
    @ObservationIgnored private var axis: Axis?
    @ObservationIgnored private var dragging: (kind: Kind, value: Double, lastY: CGFloat)?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?

    /// Swipes starting this close to the top or bottom edge are left to iOS
    /// (Notification Center, Control Center, the home indicator).
    private let edgeMargin: CGFloat = 36
    /// Share of the screen height a swipe covers to go from 0% to 100%.
    private let fullSwipe: CGFloat = 0.75

    // MARK: Lifetime

    func attach(player: Player) {
        self.player = player
        guard volumeObservation == nil else { return }
        // The side buttons: the system's own indicator is hidden while the
        // player is up, so they show this one instead.
        volumeObservation = Self.observeVolume { [weak self] volume in
            Task { @MainActor in self?.volumeChangedOutside(Double(volume)) }
        }
    }

    func detach() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        hideTask?.cancel()
        shown = nil
        axis = nil
        dragging = nil
    }

    // MARK: Swipes

    func dragChanged(start: CGPoint, translation: CGSize, in size: CGSize) {
        if axis == nil {
            // The direction is decided once, at the first movement: a sideways
            // swipe is ignored rather than turning into a level change.
            let nearEdge = start.y < edgeMargin || start.y > size.height - edgeMargin
            guard abs(translation.height) > abs(translation.width), !nearEdge else {
                axis = .horizontal
                return
            }
            axis = .vertical
            let kind: Kind = start.x < size.width / 2 ? .brightness : .volume
            let value = level(of: kind)
            dragging = (kind, value, translation.height)
            hideTask?.cancel()
            shown = Shown(kind: kind, value: value)
        }
        guard axis == .vertical, var current = dragging else { return }

        // Up raises, down lowers. Applied step by step, so turning back at
        // 100% lowers it straight away.
        let delta = Double(-(translation.height - current.lastY) / max(1, size.height * fullSwipe))
        current.lastY = translation.height
        let old = current.value
        current.value = min(1, max(0, old + delta))
        dragging = current

        guard current.value != old else { return }
        if current.value == 0 || current.value == 1 { limitHits += 1 }
        set(current.kind, to: current.value)
        shown = Shown(kind: current.kind, value: current.value)
    }

    /// Called when the finger lifts or the gesture is cancelled.
    func dragEnded() {
        axis = nil
        guard dragging != nil else { return }
        dragging = nil
        hideSoon()
    }

    // MARK: Levels

    private func level(of kind: Kind) -> Double {
        switch kind {
        case .brightness:
            return Double(screen?.brightness ?? 0.5)
        case .volume:
            if volumeSlider == nil, let player { return Double(player.volume) }
            return Double(AVAudioSession.sharedInstance().outputVolume)
        }
    }

    private func set(_ kind: Kind, to value: Double) {
        switch kind {
        case .brightness:
            screen?.brightness = CGFloat(value)
        case .volume:
            if let slider = volumeSlider {
                slider.value = Float(value)
            } else {
                try? player?.setAudioVolume(Volume(Float(value)))
            }
        }
    }

    private func volumeChangedOutside(_ value: Double) {
        guard dragging?.kind != .volume else { return }   // our own change coming back
        hideTask?.cancel()
        shown = Shown(kind: .volume, value: value)
        hideSoon(after: .seconds(1.2))
    }

    private func hideSoon(after delay: Duration = .milliseconds(800)) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.shown = nil
        }
    }

    private var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    private var volumeSlider: UISlider? {
        guard let volumeView else { return nil }
        return Self.firstSlider(in: volumeView)
    }

    private static func firstSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let slider = firstSlider(in: subview) { return slider }
        }
        return nil
    }

    /// Kept off the main actor: iOS reports volume changes on any thread.
    private nonisolated static func observeVolume(
        _ onChange: @escaping @Sendable (Float) -> Void
    ) -> NSKeyValueObservation {
        AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            if let volume = change.newValue { onChange(volume) }
        }
    }
}

// MARK: - Gesture

extension View {
    /// Vertical swipes set brightness (left half) and volume (right half),
    /// only while the video fills a landscape screen. Taps still go through.
    func swipeToAdjustLevels(_ levels: SwipeLevels, enabled: Bool) -> some View {
        modifier(SwipeLevelsGesture(levels: levels, enabled: enabled))
    }
}

private struct SwipeLevelsGesture: ViewModifier {
    let levels: SwipeLevels
    let enabled: Bool

    @State private var size: CGSize = .zero
    @GestureState private var isDragging = false

    private var isActive: Bool {
        enabled && !Platform.isMac && size.width > size.height
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .gesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .local)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        levels.dragChanged(start: value.startLocation,
                                           translation: value.translation, in: size)
                    },
                including: isActive ? .all : .subviews
            )
            // Resets on lift and on cancel alike, so the indicator never sticks.
            .onChange(of: isDragging) { _, dragging in
                if !dragging { levels.dragEnded() }
            }
    }
}

// MARK: - Indicator

/// A Control Center style bar at the edge that was swiped: brightness on the
/// left, volume on the right.
struct SwipeLevelsIndicator: View {
    let levels: SwipeLevels

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let shown = levels.shown {
                LevelBar(kind: shown.kind, value: shown.value)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: shown.kind == .brightness ? .leading : .trailing)
                    .padding(.horizontal, 20)
                    .transition(transition(for: shown.kind))
            }
        }
        .animation(.easeOut(duration: 0.2), value: levels.shown?.kind)
        .sensoryFeedback(.impact(weight: .light), trigger: levels.limitHits)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func transition(for kind: SwipeLevels.Kind) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(x: kind == .brightness ? -16 : 16))
    }
}

private struct LevelBar: View {
    let kind: SwipeLevels.Kind
    let value: Double

    private let width: CGFloat = 50
    private let height: CGFloat = 156

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .contentTransition(.numericText(value: value))

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(.white)
                    .frame(height: height * value)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(value > 0.2 ? Color.black.opacity(0.75) : .white)
                    .frame(height: 24)
                    .padding(.bottom, 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: width, height: height, alignment: .bottom)
            .levelBarBackground()
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12)
        }
        .animation(.smooth(duration: 0.12), value: value)
    }

    private var symbol: String {
        switch kind {
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if value == 0 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

private extension View {
    @ViewBuilder
    func levelBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - System volume

/// Keeps the system volume control in the player, out of sight. While it is
/// there, iOS hides its own volume indicator, and its slider is how the app
/// sets the volume.
struct SystemVolumeHost: UIViewRepresentable {
    let levels: SwipeLevels

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        container.addSubview(volumeView)
        levels.volumeView = volumeView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
