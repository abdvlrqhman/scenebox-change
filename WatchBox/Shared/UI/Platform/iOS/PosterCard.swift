//
//  PosterCard.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

#if os(iOS)
import SwiftUI

struct PosterCard: View {
    let item: MediaResult
    @Environment(WatchlistStore.self) private var watchlist: WatchlistStore?
    @Environment(WatchProgressStore.self) private var progress: WatchProgressStore?

    var body: some View {
        let saved = progress?.progress(for: item.id)
        let watchedMovie = item.type == .movie && saved?.isFinished == true
        PosterImage(url: item.posterURL)
            .overlay(alignment: .topTrailing) {
                if watchedMovie {
                    WatchedBadge()
                        .padding(6)
                } else if watchlist?.contains(item.id) == true {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if let saved, !saved.isFinished, saved.fraction > 0.02 {
                    ArtworkProgress(fraction: saved.fraction)
                        .padding(6)
                }
            }
            .accessibilityLabel(item.name)
    }
}
#endif
