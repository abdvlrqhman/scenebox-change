//
//  NextEpisodeButton.swift
//  SceneBox
//

#if os(iOS)
import SwiftUI

/// A quiet "Next Episode" pill for the end of an episode: it fades in during
/// the credits, fills slowly over the last seconds before playing on, and goes
/// away with the × or a swipe to the right (which also cancels auto-play).
struct NextEpisodeButton: View {
    let episode: Episode
    let isNewSeason: Bool
    /// 0…1 across the last seconds before auto-play; nil before that.
    let autoplayProgress: Double?
    let onPlay: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    Image(systemName: "forward.end.fill")
                        .font(.footnote.weight(.bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isNewSeason ? "Start Season \(episode.season)" : "Next Episode")
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: 260, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isNewSeason ? "Start season \(episode.season)"
                                            : "Play next episode, season \(episode.season) episode \(episode.episode)")

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 22)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keep watching this episode")
        }
        .foregroundStyle(.white)
        .background(alignment: .leading) {
            // Auto-play is coming: a soft fill, no ticking numbers.
            GeometryReader { proxy in
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: proxy.size.width * (autoplayProgress ?? 0))
                    .animation(.linear(duration: 0.5), value: autoplayProgress)
            }
        }
        .nextEpisodeBackground()
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .offset(x: dragOffset)
        .opacity(1 - Double(min(dragOffset, 160) / 240))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in dragOffset = max(0, value.translation.width) }
                .onEnded { value in
                    if value.translation.width > 70 || value.predictedEndTranslation.width > 160 {
                        onDismiss()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        let number = "S\(episode.season) · E\(episode.episode)"
        let name = episode.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.lowercased().hasPrefix("episode") ? number : "\(number) · \(name)"
    }
}

private extension View {
    @ViewBuilder
    func nextEpisodeBackground() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
        }
    }
}
#endif
