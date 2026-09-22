//
//  EpisodePickerSheet.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

#if os(iOS)
import SwiftUI
import Kingfisher

struct EpisodePickerSheet: View {
    let episodes: EpisodePlaylist
    let onSelect: (Episode) -> Void

    @State private var season: Int
    @State private var progress = WatchProgressStore.shared
    @Environment(\.dismiss) private var dismiss

    private var watched: Set<String> { progress.watchedEpisodes(for: episodes.mediaID) }

    init(episodes: EpisodePlaylist, onSelect: @escaping (Episode) -> Void) {
        self.episodes = episodes
        self.onSelect = onSelect
        _season = State(initialValue: episodes.current.season)
    }

    var body: some View {
        NavigationStack {
            List(episodes.episodes(inSeason: season)) { episode in
                Button { onSelect(episode) } label: {
                    EpisodeSheetRow(episode: episode,
                                    isCurrent: episode.id == episodes.current.id,
                                    isWatched: watched.contains(episode.label),
                                    watchFraction: progress.episodeFraction(mediaID: episodes.mediaID,
                                                                            episodeID: episode.id))
                }
                .listRowBackground(Theme.background)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
            .background(Theme.background)
            .navigationTitle("Episodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if episodes.seasons.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Menu {
                            Picker("Season", selection: $season) {
                                ForEach(episodes.seasons, id: \.self) { s in
                                    Text(s == 0 ? "Specials" : "Season \(s)").tag(s)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(season == 0 ? "Specials" : "Season \(season)").font(.headline)
                                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct EpisodeSheetRow: View {
    let episode: Episode
    let isCurrent: Bool
    var isWatched = false
    var watchFraction: Double? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.episode). \(episode.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let released = episode.released {
                    Text(released.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.surface)
            .frame(width: 104, height: 59)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo")
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
                    .opacity(isWatched && !isCurrent ? 0.45 : 1)
            }
            .overlay(alignment: .bottom) {
                if let watchFraction, !isWatched { ArtworkProgress(fraction: watchFraction).padding(4) }
            }
            .overlay(alignment: .topTrailing) {
                if isWatched { WatchedBadge(size: 18).padding(4) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
#endif
