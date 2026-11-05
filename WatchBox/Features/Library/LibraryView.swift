//
//  LibraryView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import SwiftUI

struct LibraryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case downloads = "Downloads"
        case watchlist = "Watchlist"
        case history = "History"
        var id: String { rawValue }
    }

    // Nothing downloaded but titles saved: open on those instead of an empty page.
    @State private var section: Section =
        DownloadStore.shared.downloads.isEmpty && !WatchlistStore.shared.items.isEmpty ? .watchlist : .downloads
    @Namespace private var switcher

    var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        PageTitleRow("Library")
                        sectionPicker
                        content
                    }
                    .padding(.horizontal, controlInset)
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                }
                #else
                VStack(spacing: 0) {
                    RootHeader(title: "My Stuff") { ProfileButton() }
                    sectionPicker
                        .padding(.horizontal, controlInset)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                    content
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            #if os(tvOS)
            .pageTitle("Library")
            #else
            .toolbar(.hidden, for: .navigationBar)
            .statusBarScrim()
            #endif
            .mediaNavigationDestinations()
        }
    }

    @ViewBuilder
    private var sectionPicker: some View {
        #if os(tvOS)
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        #else
        // A sliding pill instead of the stock segmented control.
        HStack(spacing: 4) {
            ForEach(Section.allCases) { option in
                let selected = section == option
                Button {
                    withAnimation(Theme.snappy) { section = option }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.elevated)
                                    .matchedGeometryEffect(id: "pill", in: switcher)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .sensoryFeedback(.selection, trigger: section)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .downloads: DownloadsView()
        case .watchlist: WatchlistSection()
        case .history: HistorySection()
        }
    }

    #if os(tvOS)
    private var controlInset: CGFloat { TVHomeView.edge }
    #else
    private var controlInset: CGFloat { Theme.gutter }
    #endif
}

private struct WatchlistSection: View {
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        if watchlist.items.isEmpty {
            EmptyStateView(
                systemImage: "bookmark",
                title: "No saved titles",
                message: "Add movies and shows to your Watchlist from their detail pages.",
                actionTitle: "Find something to watch") { TabRouter.shared.openSearch() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(tvOS)
                .frame(minHeight: 500)   // hosted in a ScrollView: give it room
                #endif
        } else {
            #if os(tvOS)
            LazyVStack(spacing: 8) {
                ForEach(watchlist.items) { item in
                    NavigationLink(value: item.mediaResult) {
                        WatchlistRow(item: item)
                    }
                    .buttonStyle(TVListRowButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove from Watchlist", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .focusSection()
            #else
            List {
                ForEach(watchlist.items) { item in
                    NavigationLink(value: item.mediaResult) {
                        WatchlistRow(item: item)
                    }
                    .listRowBackground(Theme.background)
                    .swipeActions {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove from Watchlist", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .hideScrollBackground()
            .refreshable { await watchlist.refresh() }
            #endif
        }
    }
}

private struct WatchlistRow: View {
    let item: WatchlistItem
    @Environment(WatchProgressStore.self) private var progress
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        HStack(spacing: rowSpacing) {
            PosterImage(url: item.posterURL, cornerRadius: 8)
                .frame(width: posterWidth)
                .overlay(alignment: .topTrailing) {
                    if isWatchedMovie { WatchedBadge(size: 18).padding(4) }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(titleFont)
                    .lineLimit(2)
                Text(statusLine)
                    .font(subtitleFont)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
                if let fraction = inProgressFraction {
                    ProgressView(value: fraction)
                        .tint(Theme.accent)
                        .frame(maxWidth: 160)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, rowSpacing / 2)
        .foregroundStyle(isFocused ? Color.black : Color.white)
    }

    private var saved: WatchProgress? { progress.progress(for: item.id) }

    private var isWatchedMovie: Bool { item.mediaType == .movie && saved?.isFinished == true }

    private var inProgressFraction: Double? {
        guard let saved, !saved.isFinished, saved.fraction > 0.01 else { return nil }
        return saved.fraction
    }

    /// Type plus where the viewer is: "Movie, watched", "TV Show, 3 episodes watched".
    private var statusLine: String {
        if isWatchedMovie { return "\(typeLabel), watched" }
        let watched = progress.watchedEpisodes(for: item.id).count
        if item.mediaType != .movie, watched > 0 {
            return "\(typeLabel), \(watched) episode\(watched == 1 ? "" : "s") watched"
        }
        if let label = saved?.episodeLabel, inProgressFraction != nil { return "\(typeLabel), \(label)" }
        return typeLabel
    }

    private var typeLabel: String {
        switch item.mediaType {
        case .movie: "Movie"
        case .series: "TV Show"
        case .anime: "Anime"
        }
    }

    #if os(tvOS)
    private var posterWidth: CGFloat { 130 }
    private var rowSpacing: CGFloat { 28 }
    private var titleFont: Font { .title3.weight(.semibold) }
    private var subtitleFont: Font { .callout }
    #else
    private var posterWidth: CGFloat { 56 }
    private var rowSpacing: CGFloat { 14 }
    private var titleFont: Font { .display(19, weight: .medium, relativeTo: .headline) }
    private var subtitleFont: Font { .subheadline }
    #endif
}

/// Everything watched or started, newest first: a way back to anything.
private struct HistorySection: View {
    @Environment(WatchProgressStore.self) private var progress

    var body: some View {
        let items = progress.items.sorted { $0.updatedAt > $1.updatedAt }
        if items.isEmpty {
            EmptyStateView(systemImage: "clock.arrow.circlepath", title: "Nothing watched yet",
                           message: "What you watch shows up here, newest first.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        NavigationLink(value: item.mediaResult) { row(item) }
                            #if os(tvOS)
                            .buttonStyle(TVListRowButtonStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private func row(_ item: WatchProgress) -> some View {
        HStack(spacing: 14) {
            PosterImage(url: item.posterURL, cornerRadius: Theme.posterCorner)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.display(19, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
        .contentShape(Rectangle())
    }

    /// "Season 1, episode 3   Watched   Yesterday"
    private func detail(_ item: WatchProgress) -> String {
        var parts: [String] = []
        if let season = item.season, let episode = item.episode { parts.append("Season \(season), episode \(episode)") }
        parts.append(item.isFinished ? "Watched" : "\(Int(item.fraction * 100))% watched")
        parts.append(item.updatedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: "   ")
    }
}
