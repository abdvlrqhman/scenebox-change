//
//  PlaybackControls.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI
import SwiftVLC

struct PlaybackControls: View {
    let player: Player
    let title: String
    var isBuffering: Bool = false
    let subs: SubtitlesController
    /// Lives with the screen, so Esc can close the panel before the player.
    @Binding var showSettings: Bool
    var onSettingsOpenChanged: (Bool) -> Void = { _ in }
    var isLandscape = false
    var onToggleOrientation: () -> Void = {}
    var onAudioSelected: (Track) -> Void = { _ in }
    var episodes: EpisodePlaylist? = nil
    var onCast: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var showEpisodes = false
    /// The panel opened from the CC button starts on subtitles.
    @State private var panelOnSubtitles = false

    private var canRotate: Bool { UIDevice.current.userInterfaceIdiom != .pad && !Platform.isMac }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(title: title,
                       onSubtitles: { panelOnSubtitles = true; showSettings = true },
                       onSettings: { panelOnSubtitles = false; showSettings = true },
                       onCast: onCast,
                       onClose: onClose)
                Spacer(minLength: 0)
                TransportRow(player: player, isBuffering: isBuffering)
                Spacer(minLength: 0)
                BottomBar(player: player, isBuffering: isBuffering,
                          episodes: episodes, onShowEpisodes: { showEpisodes = true })
            }
            .foregroundStyle(.white)

            if showSettings {
                PlaybackSettingsPanel(player: player, subs: subs,
                                      onAudioSelected: onAudioSelected,
                                      opensOnSubtitles: panelOnSubtitles,
                                      onRotate: canRotate ? onToggleOrientation : nil) { showSettings = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showSettings)
        .onChange(of: showSettings) { _, open in onSettingsOpenChanged(open) }
        .sheet(isPresented: $showEpisodes) {
            if let episodes {
                EpisodePickerSheet(episodes: episodes) { episode in
                    showEpisodes = false
                    episodes.onPlay(episode)
                }
            }
        }
        .onChange(of: showEpisodes) { _, open in onSettingsOpenChanged(open) }
    }
}

/// Close and the title, then at most three tools: subtitles, TV, settings.
private struct TopBar: View {
    let title: String
    let onSubtitles: () -> Void
    let onSettings: () -> Void
    var onCast: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { icon("xmark") }
                .accessibilityLabel("Close")

            Text(title)
                .font(Platform.isMac ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 2)

            Spacer(minLength: 0)

            Button(action: onSubtitles) { icon("captions.bubble") }
                .accessibilityLabel("Subtitles")
            if let onCast, !Platform.isMac {
                Button(action: onCast) { icon("tv") }
                    .accessibilityLabel("Play on TV or computer")
            }
            Button(action: onSettings) { icon("slider.horizontal.3") }
                .accessibilityLabel("Playback settings")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(Platform.isMac ? .headline.weight(.bold) : .subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }
}

private struct TransportRow: View {
    let player: Player
    let isBuffering: Bool

    var body: some View {
        let glyph: CGFloat = Platform.isMac ? 36 : 30
        let playSize: CGFloat = Platform.isMac ? 88 : 74
        HStack(spacing: Platform.isMac ? 64 : 48) {
            Button {
                try? player.seek(by: .seconds(-10), fast: true)
            } label: {
                Image(systemName: "gobackward.10").font(.system(size: glyph))
            }
            .disabled(!player.isSeekable)
            .accessibilityLabel("Back 10 seconds")

            ZStack {
                if isBuffering, player.currentTime == .zero {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Button {
                        player.togglePlaybackReasserting()
                    } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: glyph, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: playSize, height: playSize)
                                .glassEffect(.regular.interactive(), in: Circle())
                                .contentShape(Rectangle())
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: glyph, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: playSize, height: playSize)
                                .background(.white.opacity(0.18), in: Circle())
                                .contentShape(Rectangle())
                        }
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
            }
            .frame(width: playSize, height: playSize)

            Button {
                try? player.seek(by: .seconds(10), fast: true)
            } label: {
                Image(systemName: "goforward.10").font(.system(size: glyph))
            }
            .disabled(!player.isSeekable)
            .accessibilityLabel("Forward 10 seconds")
        }
        .buttonStyle(.plain)
        .shadow(radius: 8)
    }
}

private struct BottomBar: View {
    let player: Player
    let isBuffering: Bool
    var episodes: EpisodePlaylist? = nil
    var onShowEpisodes: () -> Void = {}

    var body: some View {
        VStack(spacing: Platform.isMac ? 14 : 10) {
            if episodes != nil || isBuffering {
                HStack(spacing: 10) {
                    if let episodes {
                        pill("Episodes", systemImage: "rectangle.stack", action: onShowEpisodes)
                    }
                    if isBuffering {
                        Text("Loading…")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                    if let next = episodes?.next {
                        pill("Next episode", systemImage: "forward.end.fill") { episodes?.onPlay(next) }
                    }
                }
            }
            SeekRow(player: player)
        }
        .padding(.horizontal, Platform.isMac ? 32 : 20)
        .padding(.top, Platform.isMac ? 28 : 16)
        .padding(.bottom, Platform.isMac ? 24 : 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SeekRow: View {
    let player: Player

    @State private var scrub: Double?
    @State private var pendingTarget: Double?
    @State private var knownDuration: Duration = .zero

    private var sliderValue: Double { scrub ?? pendingTarget ?? player.position }

    var body: some View {
        HStack(spacing: Platform.isMac ? 18 : 12) {
            Text(timecode(elapsed))
                .font(Platform.isMac ? .subheadline.monospacedDigit() : .caption.monospacedDigit())

            Slider(
                value: Binding(get: { sliderValue }, set: { scrub = $0 }),
                in: 0...1,
                onEditingChanged: { editing in
                    guard !editing, let target = scrub else { return }
                    seek(to: target)
                    pendingTarget = target
                    scrub = nil
                }
            )
            .tint(Theme.accent)
            .controlSize(Platform.isMac ? .large : .regular)
            .disabled(!player.isSeekable)

            // Time left, the number a viewer actually wants.
            Text("-" + timecode(max(.zero, knownDuration - elapsed)))
                .font(Platform.isMac ? .subheadline.monospacedDigit() : .caption.monospacedDigit())
                .accessibilityLabel("Time left")
        }
        .onChange(of: player.duration, initial: true) { _, new in
            if let new, new > .zero { knownDuration = new }
        }
        .onChange(of: player.position) { _, position in
            if let target = pendingTarget, abs(position - target) < 0.01 {
                pendingTarget = nil
            }
        }
        .task(id: pendingTarget) {
            // A seek that lands off target (keyframes) or late lets go after a moment.
            guard pendingTarget != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { pendingTarget = nil }
        }
    }

    private var elapsed: Duration {
        guard knownDuration > .zero else { return player.currentTime }
        if let fraction = scrub ?? pendingTarget {
            return .seconds(Double(knownDuration.components.seconds) * fraction)
        }
        return player.currentTime
    }

    private func seek(to position: Double) {
        if !player.seek(toPosition: PlaybackPosition(position), fast: true) {
            try? player.seek(to: PlaybackPosition(position))
        }
    }
}

// MARK: - Preview

private struct PlaybackControlsPreview: View {
    @State private var player = Player()
    let buffering: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.20), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            PlaybackControls(
                player: player,
                title: "Masters of the Universe",
                isBuffering: buffering,
                subs: SubtitlesController(),
                showSettings: .constant(false),
                isLandscape: true,
                onToggleOrientation: {},
                onClose: {}
            )
        }
    }
}

#Preview("iOS Player") {
    PlaybackControlsPreview(buffering: false)
}

#Preview("iOS Player · Buffering") {
    PlaybackControlsPreview(buffering: true)
}
#endif
