//
//  SubtitleOverlay.swift
//  SceneBox
//

import SwiftUI
import SwiftVLC

/// Downloaded subtitles drawn over the video from the player's own clock: no second
/// reader inside VLC to drift after a pause, a seek or leaving the app, and nothing that
/// can flash lines ahead to catch up. They rise above the controls while those show.
struct SubtitleOverlay: View {
    let cues: [DrawnCue]
    let player: Player
    let scale: Double
    let raised: Bool

    /// Where the clock was last reported, and when: VLC reports a few times a second,
    /// so the time in between is counted on, for lines that change on cue.
    @State private var anchor: (time: Duration, at: Date) = (.zero, .now)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let lines = DrawnCue.showing(at: milliseconds(at: context.date), in: cues)
                VStack(spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                    }
                }
                .font(.system(size: max(15, min(geo.size.width, geo.size.height) * 0.045) * scale, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 0)
                .shadow(color: .black.opacity(0.9), radius: 1, x: 1, y: 1)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .frame(maxWidth: geo.size.width * 0.86)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, raised ? 92 : 24)
                .animation(.easeOut(duration: 0.2), value: raised)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: player.currentTime, initial: true) { _, time in anchor = (time, .now) }
    }

    private func milliseconds(at date: Date) -> Int {
        var time = anchor.time
        if player.isPlaying {
            // Count on from the last report, never more than a second ahead of it.
            time += .milliseconds(Int(min(1, max(0, date.timeIntervalSince(anchor.at))) * 1000 * Double(player.rate)))
        }
        let parts = time.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}
