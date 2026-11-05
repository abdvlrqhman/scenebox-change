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
    /// Season downloads and "Select Episodes…" live in the page's download menu.
    @Binding var isSelecting: Bool
    var watchedEpisodes: Set<String> = []
    var episodeFraction: (Episode) -> Double? = { _ in nil }
    let onWatch: (Episode) -> Void
    let onDownload: (Episode) -> Void
    var onDownloadEpisodes: ([Episode]) -> Void = { _ in }
    var onSetWatched: (Episode, Bool) -> Void = { _, _ in }
    /// The show's usual episode length, for "33m left" and "48m Watched".
    var runtimeMinutes: Int? = nil
    /// What the Resume button says, so the episode row says the same.
    var resumeTimeLeft: String? = nil
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Set<String> = []

    private var usesCards: Bool { Platform.isMac || sizeClass == .regular }
    private var cardWidth: CGFloat { Platform.isMac ? 300 : 280 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            let episodes = detail.episodes(inSeason: selectedSeason)
            if isSelecting, !episodes.isEmpty {
                selectionBar(for: episodes)
                    .padding(.horizontal, 16)
            }

            if episodes.isEmpty {
                Text("No episodes listed for this season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else if usesCards {
                HorizontalShelfScroller {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { episode in
                            let watched = watchedEpisodes.contains(episode.label)
                            let state = downloadState(for: episode)
                            EpisodeCard(episode: episode, width: cardWidth,
                                        downloadState: state,
                                        download: downloads.download(mediaID: detail.id, episodeLabel: episode.label),
                                        isWatched: watched,
                                        watchFraction: episodeFraction(episode),
                                        selection: selectionState(for: episode, state: state),
                                        onWatch: { isSelecting ? toggle(episode, state: state) : onWatch(episode) },
                                        onDownload: { onDownload(episode) })
                            .contextMenu {
                                Button { onSetWatched(episode, !watched) } label: {
                                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                          systemImage: watched ? "eye.slash" : "checkmark.circle")
                                }
                                if state == .idle, !episode.isUnaired {
                                    Button { onDownload(episode) } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        let watched = watchedEpisodes.contains(episode.label)
                        let state = downloadState(for: episode)
                        EpisodeRow(episode: episode,
                                   downloadState: state,
                                   download: downloads.download(mediaID: detail.id, episodeLabel: episode.label),
                                   isWatched: watched,
                                   watchFraction: episodeFraction(episode),
                                   selection: selectionState(for: episode, state: state),
                                   runtimeMinutes: runtimeMinutes,
                                   resumeTimeLeft: resumeTimeLeft,
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
                        } preview: {
                            EpisodePeek(episode: episode)   // the synopsis the compact row leaves out
                        }
                    }
                }
            }
        }
        .onChange(of: selectedSeason) { _, _ in selection.removeAll() }
    }

    /// "Season  1 2 3 4 5": the numerals switch seasons; then download choices (or Cancel).
    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(detail.seasons.count > 1 ? "Season" : seasonName(selectedSeason))
                .sectionTitleStyle()
                .lineLimit(1)
            if detail.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(detail.seasons, id: \.self) { season in
                            let on = season == selectedSeason
                            Button { selectedSeason = season } label: {
                                Text(season == 0 ? "Specials" : "\(season)")
                                    .font(.display(24, weight: on ? .medium : .light, relativeTo: .title2))
                                    .foregroundStyle(on ? Color.white : Theme.textTertiary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel(seasonName(season))
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
            if isSelecting {
                Button("Cancel") {
                    isSelecting = false
                    selection.removeAll()
                }
                .font(.subheadline.weight(.semibold))
                .tint(.white)
                .frame(minHeight: 44)
                .padding(.trailing, 20)
            }
        }
        .padding(.leading, 20)
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
        if download.phase.isPending { return .pending }
        return .idle                                  // paused / failed: can be re-requested
    }

    /// Released episodes that aren't downloaded or already on their way.
    private func downloadable(in episodes: [Episode]) -> [Episode] {
        episodes.filter { downloadState(for: $0) == .idle && !$0.isUnaired }
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

private extension Episode {
    var isUnaired: Bool { (released ?? .distantPast) > Date() }
}

enum EpisodeDownloadState: Equatable {
    case idle
    case pending        // progress is read by the ring itself, so only it redraws
    case completed

    var isDownloaded: Bool { self == .completed }
}

/// The download button's icon: arrow, progress ring, or check.
private struct EpisodeDownloadGlyph: View {
    let state: EpisodeDownloadState
    let size: CGFloat
    var idleColor: Color = .white.opacity(0.7)
    var download: Download? = nil

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size))
                .foregroundStyle(idleColor)
        case .completed:
            // The download badge's look; the check on the still already means "watched".
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: size))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
        case .pending:
            PendingRing(progress: download?.progress ?? 0, size: size)
        }
    }
}

/// Download progress ring. Its own view, so twice-a-second progress updates
/// redraw the ring and not the whole episode list.
private struct PendingRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
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
    var download: Download? = nil
    var isWatched = false
    var watchFraction: Double? = nil
    /// nil when not selecting; otherwise whether this row is ticked.
    var selection: Bool? = nil
    var runtimeMinutes: Int? = nil
    var resumeTimeLeft: String? = nil
    let onWatch: () -> Void
    let onDownload: () -> Void
    var onToggleSelection: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(episode.episode)")
                .font(.display(28, weight: .light, relativeTo: .title1))
                .foregroundStyle(isCurrent ? Color.white : Theme.textTertiary)
                .frame(minWidth: 28, alignment: .leading)
                .accessibilityHidden(true)

            // The still is the play button, like the row around it; at the largest
            // text sizes it steps aside for the title.
            if !typeSize.isAccessibilitySize {
                Button(action: selection != nil ? onToggleSelection : onWatch) { thumbnail }
                    .buttonStyle(.pressable)
                    .disabled(selection == nil && episode.isUnaired)
                    .accessibilityLabel("Play episode \(episode.episode)")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let selected = selection {
                Group {
                    if downloadState == .idle {
                        SelectionMark(isSelected: selected)
                    } else {
                        EpisodeDownloadGlyph(state: downloadState, size: 24, download: download)
                    }
                }
                .frame(width: 44, height: 44)
            } else if downloadState != .completed {
                // Downloaded episodes say so in their line; no badge needed.
                Button(action: onDownload) {
                    EpisodeDownloadGlyph(state: downloadState, size: 24, download: download)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A running download keeps full contrast; it just doesn't take a second tap.
                .allowsHitTesting(downloadState == .idle && !episode.isUnaired)
                .opacity(episode.isUnaired ? 0.4 : 1)
                .accessibilityLabel(downloadState == .pending ? "Downloading" : "Download")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5).padding(.leading, 20) }
        .contentShape(Rectangle())
        .opacity(selection != nil && downloadState != .idle ? 0.55 : 1)
        .onTapGesture {
            if selection != nil { onToggleSelection() } else if !episode.isUnaired { onWatch() }
        }
    }

    /// The episode you're part-way through gets the white numeral.
    private var isCurrent: Bool { watchFraction != nil && !isWatched }

    /// "48m   Watched", "33m left", "48m   Downloaded", "Airs Oct 21": state in words, not badges.
    private var statusLine: String {
        if let released = episode.released, episode.isUnaired {
            return "Airs \(released.formatted(date: .abbreviated, time: .omitted))"
        }
        let estimate = runtimeMinutes.flatMap { minutes in
            watchFraction.map { "\(max(1, Int((Double(minutes) * (1 - $0)).rounded()))) min left" }
        }
        let time = watchFraction != nil && !isWatched ? (resumeTimeLeft ?? estimate) : runtimeMinutes.map { "\($0) min" }
        let download: String? = downloadState == .completed ? "Downloaded" : downloadState == .pending ? "Downloading" : nil
        let parts = [time, isWatched ? "Watched" : nil, download].compactMap { $0 }
        if parts.isEmpty, let released = episode.released {
            return released.formatted(date: .abbreviated, time: .omitted)
        }
        return parts.joined(separator: "   ")
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: Theme.stillCorner, style: .continuous)
            .fill(Theme.surface)
            .frame(width: 104, height: 58)
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
                    .opacity(isWatched ? 0.5 : 1)
            }
            .overlay(alignment: .bottom) {
                if let watchFraction, !isWatched {
                    ArtworkProgress(fraction: watchFraction).padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.stillCorner, style: .continuous))
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let width: CGFloat
    var downloadState: EpisodeDownloadState = .idle
    var download: Download? = nil
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
            .disabled(episode.isUnaired)

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
                let date = released.formatted(date: .abbreviated, time: .omitted)
                Text(episode.isUnaired ? "Airs \(date)" : date)
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
                if selection == nil, !episode.isUnaired {
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
                        EpisodeDownloadGlyph(state: downloadState, size: 22, idleColor: .white, download: download)
                            .frame(width: 26, height: 26)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .frame(width: 44, height: 44)       // tap target; the circle stays 38
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadState != .idle || selection != nil || episode.isUnaired)
                    .padding(5)
                    .accessibilityLabel(downloadState.isDownloaded ? "Downloaded" : "Download")
                }
            }
            .opacity(selection != nil && downloadState != .idle ? 0.55 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Long-press preview of an episode: the still and the synopsis the row leaves out.
private struct EpisodePeek: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KFImage(episode.thumbnailURL)
                .resizable()
                .placeholder { Theme.surface }
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: 320, height: 180)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text("\(episode.episode). \(episode.name)")
                    .font(.headline)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding([.horizontal, .bottom], 14)
        }
        .frame(width: 320, alignment: .leading)
        .background(Theme.surface)
    }
}
