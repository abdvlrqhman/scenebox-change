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
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 10) {
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
                .overlay(alignment: .topLeading) {
                    if isDownloaded { DownloadedBadge().padding(6) }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryLine)
                    .font(Platform.isMac ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(secondaryLine)
                    .font(Platform.isMac ? .footnote : .caption2)
                    .monospacedDigit()
                    .lineLimit(1, reservesSpace: true)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var primaryLine: String {
        guard let season = item.season, let episode = item.episode else { return item.title }
        return "S\(season) E\(episode)"
    }

    /// "Up next" once an episode is finished, otherwise the time left.
    private var secondaryLine: String {
        if item.mediaType != .movie, item.isFinished { return "Up next" }
        let left = max(0, item.durationSeconds - item.positionSeconds)
        guard item.durationSeconds > 0, left > 30 else { return item.season == nil ? " " : item.title }
        let minutes = Int((left / 60).rounded())
        let time = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return "\(time) left"
    }
}
#endif
