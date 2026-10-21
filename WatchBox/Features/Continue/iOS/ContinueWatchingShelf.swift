//
//  ContinueWatchingShelf.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct ContinueWatchingShelf: View {
    let items: [WatchProgress]
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.horizontalSizeClass) private var sizeClass

    private func isDownloaded(_ item: WatchProgress) -> Bool {
        downloads.isDownloaded(mediaID: item.id, episodeLabel: item.downloadEpisodeLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 12) {
            SectionHeader("Continue Watching")
                .padding(.horizontal, 16)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        PosterLink(item: item.mediaResult) {
                            ContinueWatchingCard(item: item, isDownloaded: isDownloaded(item))
                                .frame(width: PosterMetrics.shelfWidth(sizeClass))
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                WatchProgressStore.shared.remove(id: item.id)
                            } label: {
                                Label("Remove", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct ContinueWatchingCard: View {
    let item: WatchProgress
    var isDownloaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PosterImage(url: item.posterURL)
                .overlay(alignment: .bottom) {
                    if item.fraction > 0, !item.isFinished {
                        ArtworkProgress(fraction: item.fraction).padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Platform.isMac ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                HStack(spacing: 4) {
                    // Off the artwork: a badge there sits on the title art.
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.success)
                    }
                    secondaryLine
                        .monospacedDigit()
                        .lineLimit(1, reservesSpace: true)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Platform.isMac ? .footnote : .caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    private var minutesLeft: Int? {
        let left = max(0, item.durationSeconds - item.positionSeconds)
        guard item.durationSeconds > 0, left > 30 else { return nil }
        return Int((left / 60).rounded())
    }

    /// "S1 E3  33m left": the episode in white, the time in grey, set apart by
    /// weight rather than punctuation. Movies get just the time left; a finished
    /// episode says "Watched" (the detail page names the next one).
    private var secondaryLine: Text {
        var time: String?
        if item.mediaType != .movie, item.isFinished {
            time = "Watched"
        } else if let minutes = minutesLeft {
            time = (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m") + " left"
        }
        guard let season = item.season, let episode = item.episode else { return Text(time ?? " ") }
        let code = Text("S\(season) E\(episode)").fontWeight(.semibold).foregroundStyle(.white.opacity(0.85))
        guard let time else { return code }
        return code + Text("  ") + Text(time)
    }

    private var spokenLabel: String {
        var parts: [String] = [item.title]
        if let season = item.season, let episode = item.episode { parts.append("Season \(season), episode \(episode)") }
        if item.mediaType != .movie, item.isFinished {
            parts.append("Watched")
        } else if let minutes = minutesLeft {
            let time: String = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
            parts.append("\(time) left")
        }
        if isDownloaded { parts.append("Downloaded") }
        return parts.joined(separator: ", ")
    }
}
#endif
