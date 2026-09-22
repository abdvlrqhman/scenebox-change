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
        var id: String { rawValue }
    }

    @State private var section: Section = .downloads
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
                    RootHeader("Library")
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
                        .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.accent)
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
        }
    }

    #if os(tvOS)
    private var controlInset: CGFloat { TVHomeView.edge }
    #else
    private var controlInset: CGFloat { 16 }
    #endif
}

private struct WatchlistSection: View {
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        if watchlist.items.isEmpty {
            EmptyStateView(
                systemImage: "bookmark",
                title: "No saved titles",
                message: "Add movies and shows to your Watchlist from their detail pages.")
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
    private var posterWidth: CGFloat { 58 }
    private var rowSpacing: CGFloat { 14 }
    private var titleFont: Font { .subheadline.weight(.semibold) }
    private var subtitleFont: Font { .caption }
    #endif
}
