//
//  EpisodeSection.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import Kingfisher

struct EpisodeSection: View {
    let detail: MediaDetail
    @Binding var selectedSeason: Int
    var watchedEpisodes: Set<String> = []
    var episodeFraction: (Episode) -> Double? = { _ in nil }
    let onWatch: (Episode) -> Void
    let onDownload: (Episode) -> Void
    var onDownloadEpisodes: ([Episode]) -> Void = { _ in }
    var onSetWatched: (Episode, Bool) -> Void = { _, _ in }
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isSelecting = false
    @State private var selection: Set<String> = []

    private var usesCards: Bool { Platform.isMac || sizeClass == .regular }
    private var cardWidth: CGFloat { Platform.isMac ? 300 : 280 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, 20)

            let episodes = detail.episodes(inSeason: selectedSeason)
            if isSelecting, !episodes.isEmpty {
                selectionBar(for: episodes)
                    .padding(.horizontal, 20)
            }

            if episodes.isEmpty {
                Text("No episodes listed for this season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else if usesCards {
                HorizontalShelfScroller {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { episode in
                            let watched = watchedEpisodes.contains(episode.label)
                            let state = downloadState(for: episode)
                            EpisodeCard(episode: episode, width: cardWidth,
                                        downloadState: state, isWatched: watched,
                                        watchFraction: episodeFraction(episode),
                                        selection: selectionState(for: episode, state: state),
                                        onWatch: { isSelecting ? toggle(episode, state: state) : onWatch(episode) },
                                        onDownload: { onDownload(episode) })
                            .contextMenu {
                                Button { onSetWatched(episode, !watched) } label: {
                                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                          systemImage: watched ? "eye.slash" : "checkmark.circle")
                                }
                                if state == .idle {
                                    Button { onDownload(episode) } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        let watched = watchedEpisodes.contains(episode.label)
                        let state = downloadState(for: episode)
                        EpisodeRow(episode: episode,
                                   downloadState: state,
                                   isWatched: watched,
                                   watchFraction: episodeFraction(episode),
                                   selection: selectionState(for: episode, state: state),
                                   onWatch: { onWatch(episode) },
                                   onDownload: { onDownload(episode) },
                                   onToggleSelection: { toggle(episode, state: state) })
                        .contextMenu {
                            Button {
                                onSetWatched(episode, !watched)
                            } label: {
                                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                      systemImage: watched ? "eye.slash" : "checkmark.circle")
                            }
                        }
                        if episode.id != episodes.last?.id {
                            Divider().overlay(.white.opacity(0.08)).padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .onChange(of: selectedSeason) { _, _ in selection.removeAll() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Episodes")
                .font(.headline)
            Spacer()
            if isSelecting {
                Button("Cancel") {
                    isSelecting = false
                    selection.removeAll()
                }
                .font(.subheadline.weight(.semibold))
                .tint(.white)
            } else {
                Menu {
                    let available = downloadable(in: detail.episodes(inSeason: selectedSeason))
                    Button {
                        onDownloadEpisodes(available)
                    } label: {
                        Label("Download \(seasonName(selectedSeason)) (\(available.count))",
                              systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(available.isEmpty)
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select Episodes…", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Download episodes")
            }
            Picker("Season", selection: $selectedSeason) {
                ForEach(detail.seasons, id: \.self) { season in
                    Text(seasonName(season)).tag(season)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
    }

    private func selectionBar(for episodes: [Episode]) -> some View {
        let available = downloadable(in: episodes)
        let allSelected = !available.isEmpty && available.allSatisfy { selection.contains($0.id) }
        let chosen = episodes.filter { selection.contains($0.id) }
        return HStack(spacing: 12) {
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    selection.subtract(available.map(\.id))
                } else {
                    selection.formUnion(available.map(\.id))
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(available.isEmpty)

            Spacer(minLength: 0)

            Button {
                onDownloadEpisodes(chosen)
                selection.removeAll()
                isSelecting = false
            } label: {
                Label(chosen.isEmpty ? "Download" : "Download \(chosen.count)",
                      systemImage: "arrow.down.circle.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
            .disabled(chosen.isEmpty)
        }
        .font(.subheadline)
    }

    private func seasonName(_ season: Int) -> String {
        season == 0 ? "Specials" : "Season \(season)"
    }

    private func downloadState(for episode: Episode) -> EpisodeDownloadState {
        guard let download = downloads.download(mediaID: detail.id, episodeLabel: episode.label) else {
            return .idle
        }
        if download.phase == .completed || download.record.isComplete { return .completed }
        if download.phase.isPending { return .pending(download.progress) }
        return .idle                                  // paused / failed: can be re-requested
    }

    /// Released episodes that aren't downloaded or already on their way.
    private func downloadable(in episodes: [Episode]) -> [Episode] {
        let now = Date()
        return episodes.filter { episode in
            guard downloadState(for: episode) == .idle else { return false }
            if let released = episode.released, released > now { return false }
            return true
        }
    }

    private func selectionState(for episode: Episode, state: EpisodeDownloadState) -> Bool? {
        guard isSelecting else { return nil }
        return state == .idle && selection.contains(episode.id)
    }

    private func toggle(_ episode: Episode, state: EpisodeDownloadState) {
        guard isSelecting, state == .idle else { return }
        if selection.contains(episode.id) { selection.remove(episode.id) } else { selection.insert(episode.id) }
    }
}

enum EpisodeDownloadState: Equatable {
    case idle
    case pending(Double)
    case completed

    var isDownloaded: Bool { self == .completed }
}

/// The download button's icon: arrow, progress ring, or check.
private struct EpisodeDownloadGlyph: View {
    let state: EpisodeDownloadState
    let size: CGFloat
    var idleColor: Color = .white.opacity(0.6)

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(idleColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.green)
        case .pending(let progress):
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, progress)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: size * 0.85, height: size * 0.85)
            .accessibilityLabel("Downloading \(Int(progress * 100)) percent")
        }
    }
}

/// Checkbox shown on each episode while selecting.
private struct SelectionMark: View {
    let isSelected: Bool
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.6))
            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    var downloadState: EpisodeDownloadState = .idle
    var isWatched = false
    var watchFraction: Double? = nil
    /// nil when not selecting; otherwise whether this row is ticked.
    var selection: Bool? = nil
    let onWatch: () -> Void
    let onDownload: () -> Void
    var onToggleSelection: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(episode.episode). \(episode.name)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                }

                if let overview = episode.overview, !overview.isEmpty {
                    ExpandableText(text: overview, lineLimit: 3,
                                   font: .caption, color: .secondary)
                }

                if let released = episode.released {
                    Text(released.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if let selected = selection {
                Group {
                    if downloadState == .idle {
                        SelectionMark(isSelected: selected)
                    } else {
                        EpisodeDownloadGlyph(state: downloadState, size: 28)
                    }
                }
                .frame(width: 44, height: 44)
            } else {
                VStack(spacing: 8) {
                    Button(action: onWatch) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Button(action: onDownload) {
                        EpisodeDownloadGlyph(state: downloadState, size: 30)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(downloadState != .idle)
                    .accessibilityLabel(downloadState.isDownloaded ? "Downloaded" : "Download")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(selection != nil && downloadState != .idle ? 0.55 : 1)
        .onTapGesture {
            if selection != nil { onToggleSelection() }
        }
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.surface)
            .frame(width: 112, height: 63)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 204)))
                    .cancelOnDisappear(true)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo")
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
                    .opacity(isWatched ? 0.45 : 1)
            }
            .overlay(alignment: .bottom) {
                if let watchFraction, !isWatched {
                    ArtworkProgress(fraction: watchFraction).padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isWatched { WatchedBadge(size: 18).padding(4) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let width: CGFloat
    var downloadState: EpisodeDownloadState = .idle
    var isWatched = false
    var watchFraction: Double? = nil
    var selection: Bool? = nil
    let onWatch: () -> Void
    let onDownload: () -> Void
    @State private var hovering = false

    private var stillHeight: CGFloat { width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onWatch) {
                still
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(episode.episode). \(episode.name)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

            }
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            if let released = episode.released {
                Text(released.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, alignment: .leading)
        #if os(iOS)
        .onHover { hovering = $0 }
        #endif
    }

    private var still: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.surface)
            .frame(width: width, height: stillHeight)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 900, height: 506)))
                    .cancelOnDisappear(true)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
                    .opacity(isWatched ? 0.5 : 1)
            }
            .overlay(alignment: .bottom) {
                if let watchFraction, !isWatched {
                    ArtworkProgress(fraction: watchFraction).padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                if isWatched { WatchedBadge(size: 22).padding(8) }
            }
            .overlay {
                if selection == nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(.black.opacity(0.5), in: Circle())
                        .opacity(Platform.isMac ? (hovering ? 1 : 0) : 0.9)
                        .animation(.easeOut(duration: 0.15), value: hovering)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selected = selection, downloadState == .idle {
                    SelectionMark(isSelected: selected)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(8)
                } else {
                    Button(action: onDownload) {
                        EpisodeDownloadGlyph(state: downloadState, size: 22, idleColor: .white)
                            .frame(width: 26, height: 26)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadState != .idle || selection != nil)
                    .padding(8)
                    .accessibilityLabel(downloadState.isDownloaded ? "Downloaded" : "Download")
                }
            }
            .opacity(selection != nil && downloadState != .idle ? 0.55 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
