//
//  ReleasePickerView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct ReleasePickerView: View {
    let model: MediaDetailModel
    let request: MediaDetailModel.ReleaseRequest
    let onSelect: (TorrentStream) -> Void

    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    /// The source that played last time for this episode, pinned first so the
    /// one that worked is easy to find again.
    private var lastWatchedKey: String? {
        SourceMemory.last(mediaID: model.mediaID, season: request.episode?.season,
                          episode: request.episode?.episode)?.sourceKey
    }

    private var orderedReleases: [TorrentStream] {
        guard let key = lastWatchedKey,
              let index = model.releases.firstIndex(where: { SourceKey.make($0) == key }) else {
            return model.releases
        }
        var list = model.releases
        list.insert(list.remove(at: index), at: 0)
        return list
    }

    private var sourcesWithSubtitles: Set<String> {
        SubtitleMemory.sourcesWithChoice(for: SubtitleContext(
            imdbID: model.mediaID, type: model.type,
            season: request.episode?.season, episode: request.episode?.episode))
    }

    private var navigationTitle: String {
        let action = request.intent == .watch ? "Watch" : "Download"
        if let episode = request.episode {
            return "\(action) · \(episode.label)"
        }
        return "\(action) · Sources"
    }

    #if os(tvOS)
    private var rowSpacing: CGFloat { 10 }
    private var rowEdge: CGFloat { 48 }
    #else
    private var rowSpacing: CGFloat { 8 }
    private var rowEdge: CGFloat { 16 }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingReleases {
                    ProgressView("Finding sources…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.releaseError {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: "No sources", message: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        let lastKey = lastWatchedKey
                        let withSubtitles = sourcesWithSubtitles
                        LazyVStack(spacing: rowSpacing) {
                            ForEach(orderedReleases) { stream in
                                let isLast = SourceKey.make(stream) == lastKey
                                Button { onSelect(stream) } label: {
                                    ReleaseRow(
                                        stream: stream,
                                        isDownloaded: downloads.contains(infoHash: stream.id,
                                                                   episodeLabel: request.episode?.label),
                                        isLastWatched: isLast,
                                        hasSavedSubtitles: withSubtitles.contains(SourceKey.make(stream)))
                                        #if os(iOS)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay {
                                            if isLast {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1.5)
                                            }
                                        }
                                        #endif
                                        .contentShape(Rectangle())
                                }
                                #if os(tvOS)
                                .buttonStyle(TVListRowButtonStyle())
                                #else
                                .buttonStyle(.plain)
                                #endif
                            }
                        }
                        .padding(.horizontal, rowEdge)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(navigationTitle)
            .inlineNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .preferredColorScheme(.dark)
    }
}

private struct ReleaseRow: View {
    let stream: TorrentStream
    let isDownloaded: Bool
    var isLastWatched = false
    var hasSavedSubtitles = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(stream.displayName)
                    #if os(tvOS)
                    .font(.title3.weight(.semibold))
                    #else
                    .font(.subheadline.weight(.semibold))
                    #endif
                    .lineLimit(2)
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(spacing: 8) {
                if isLastWatched {
                    Chip(text: "Last watched", systemImage: "clock.arrow.circlepath", tint: Theme.accent)
                }
                if hasSavedSubtitles {
                    Chip(text: "Subtitles saved", systemImage: "captions.bubble.fill")
                }
                if stream.isDebrid {
                    Chip(text: "Debrid", systemImage: "bolt.fill", tint: .green)
                }
                if let resolution = stream.resolution {
                    Chip(text: resolution.uppercased())
                }
                if let size = stream.sizeText {
                    Chip(text: size)
                }
                if let seeders = stream.seeders {
                    Chip(text: "\(seeders)", systemImage: "person.2.fill",
                         tint: seeders > 20 ? .green : .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .foregroundStyle(isFocused ? .black : .white)
    }
}
