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
                                      includesTracks: false,
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

/// Close and the title (serif, with the episode under it), then the three
/// tools in one glass group: subtitles, TV, settings.
private struct TopBar: View {
    let title: String
    let onSubtitles: () -> Void
    let onSettings: () -> Void
    var onCast: (() -> Void)? = nil
    let onClose: () -> Void

    /// "Breaking Bad · S1E3" arrives as one label; the episode goes on its own line.
    private var parts: (show: String, episode: String?) {
        let pieces = title.components(separatedBy: " · ")
        guard pieces.count > 1 else { return (title, nil) }
        return (pieces.dropLast().joined(separator: " · "), pieces.last)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassChrome(in: Circle())
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                Text(parts.show)
                    .font(.display(20, weight: .medium, relativeTo: .title3))
                    .lineLimit(1)
                if let episode = parts.episode {
                    Text(spoken(episode))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .truncationMode(.middle)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button(action: onSubtitles) { icon("captions.bubble") }
                    .accessibilityLabel("Audio and subtitles")
                if let onCast, !Platform.isMac {
                    Button(action: onCast) { icon("tv") }
                        .accessibilityLabel("Play on TV or computer")
                }
                Button(action: onSettings) { icon("slider.horizontal.3") }
                    .accessibilityLabel("Playback settings")
            }
            .padding(.horizontal, 4)
            .glassChrome(in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -40)
        )
    }

    /// "S1E3" reads as "Season 1, episode 3".
    private func spoken(_ code: String) -> String {
        guard let match = code.wholeMatch(of: /S(\d+)E(\d+)/) else { return code }
        return "Season \(match.1), episode \(match.2)"
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

private struct TransportRow: View {
    let player: Player
    let isBuffering: Bool

    var body: some View {
        let glyph: CGFloat = Platform.isMac ? 34 : 28
        let playSize: CGFloat = Platform.isMac ? 84 : 72
        HStack(spacing: Platform.isMac ? 64 : 48) {
            Button {
                try? player.seek(by: .seconds(-10), fast: true)
            } label: {
                Image(systemName: "gobackward.10").font(.system(size: glyph))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: glyph, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: playSize, height: playSize)
                            .glassChrome(in: Circle())
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
            }
            .frame(width: playSize, height: playSize)

            Button {
                try? player.seek(by: .seconds(10), fast: true)
            } label: {
                Image(systemName: "goforward.10").font(.system(size: glyph))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
            // Dark enough that a subtitle running under the scrubber can't fight it.
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .padding(.top, -40)
                .ignoresSafeArea()
        )
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .glassChrome(in: Capsule())
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

            HairlineScrubber(
                value: Binding(get: { sliderValue }, set: { scrub = $0 }),
                onEditingChanged: { editing in
                    guard !editing, let target = scrub else { return }
                    seek(to: target)
                    pendingTarget = target
                    scrub = nil
                }
            )
            .disabled(!player.isSeekable)

            // Time left, the number a viewer actually wants.
            Text("-" + timecode(max(.zero, knownDuration - elapsed)))
                .font(Platform.isMac ? .subheadline.monospacedDigit() : .caption.monospacedDigit())
                .accessibilityLabel("\(timecode(max(.zero, knownDuration - elapsed))) left")
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
