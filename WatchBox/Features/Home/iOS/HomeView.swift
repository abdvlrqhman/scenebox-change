//
//  HomeView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI
import Kingfisher

struct HomeView: View {
    @State private var model = HomeModel()
    @Environment(WatchProgressStore.self) private var progress
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        NavigationStack {
            // What's on the device always shows; only the catalog rows need the network.
            feed
            .background(Theme.background)
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .mediaNavigationDestinations()
            .navigationDestination(for: CatalogDestination.self) { dest in
                CatalogListView(type: dest.type, feed: dest.feed, genre: dest.genre)
            }
        }
        .task { model.loadIfNeeded() }
        .onAppear { progress.refresh() }
        .onChange(of: progress.items.first?.id, initial: true) { _, _ in
            model.loadBecauseYouWatched(progress.items.first)
        }
        .onChange(of: progress.continueItems.first, initial: true) { _, item in
            model.loadUpNext(item, watched: item.map { progress.watchedEpisodes(for: $0.id) } ?? [],
                             downloaded: item.map { downloads.completedEpisodeLabels(mediaID: $0.id) } ?? [])
        }
    }

    /// The serif wordmark and who's watching.
    private var header: some View {
        HStack {
            Text("SceneBox")
                .font(.display(30, weight: .medium, relativeTo: .title1))
                .italic()
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ProfileButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    /// The top of Home: what to play next for a returning viewer, the marquee for a new one.
    @ViewBuilder
    private var top: some View {
        if let upNext = model.upNext {
            UpNextHero(upNext: upNext)
        } else if !featured.isEmpty {
            FeaturedMarquee(items: featured)
        }
    }

    private var heroImage: URL? {
        if let upNext = model.upNext {
            return upNext.episode?.thumbnailURL ?? upNext.detail?.backdropURL ?? upNext.progress.posterURL
        }
        return featured.first?.backdropURL
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Platform.isMac ? 34 : 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        top
                    }
                    // Light from the artwork on top falls onto the black.
                    .background(alignment: .top) { AmbientBackdrop(url: heroImage, height: 640).padding(.top, -80) }
                    let others = Array(progress.continueItems.dropFirst(model.upNext == nil ? 0 : 1))
                    if !others.isEmpty {
                        KeepWatchingList(items: others)
                    }
                    if !unwatchedWatchlist.isEmpty {
                        PosterShelf(title: "Your watchlist", items: unwatchedWatchlist, showsSavedBadge: false)
                    }
                    if let because = model.becauseYouWatched {
                        PosterShelf(title: because.title, items: because.items, seeAll: because.destination)
                    }
                    if model.shelves.isEmpty, let message = model.errorMessage, !model.isLoading {
                        OfflineRow(message: message) { model.reload() }
                    } else if model.shelves.isEmpty {
                        // Placeholders keep the layout still while the catalog loads.
                        ForEach(0..<3, id: \.self) { _ in PlaceholderShelf() }
                    } else {
                        ForEach(model.shelves) { shelf in
                            PosterShelf(title: shelf.title, items: shelf.shown,
                                        seeAll: shelf.destination, ranked: shelf.isRanked)
                                .id(shelf.id)
                        }
                        ForEach(model.genreShelves) { shelf in
                            if shelf.items.isEmpty {
                                PlaceholderShelf().task { model.loadGenreShelf(shelf.id) }
                            } else {
                                PosterShelf(title: shelf.title, items: shelf.items, seeAll: shelf.destination)
                            }
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .refreshable {
                progress.refresh()
                async let catalog: () = model.refresh()
                async let saved: () = watchlist.refresh()
                _ = await (catalog, saved)
            }
            .onChange(of: model.shelves.isEmpty) { _, empty in
                // `-SBHomeRow series-top` opens Home at that row (screenshots, debugging).
                if !empty, let row = UserDefaults.standard.string(forKey: "SBHomeRow") {
                    proxy.scrollTo(row, anchor: .top)
                }
            }
        }
    }

    /// A few popular movies and shows, alternating, for the marquee.
    private var featured: [MediaResult] {
        // Ranks 4-6: the Top 10 rows right below already show 1-3.
        let pools = model.shelves.filter(\.isRanked).map { shelf in
            Array(shelf.items.filter { $0.backdropURL != nil }.dropFirst(3).prefix(3))
        }
        var picks: [MediaResult] = []
        for index in 0..<3 {
            for pool in pools where index < pool.count {
                picks.append(pool[index])
            }
        }
        return picks
    }

    private var unwatchedWatchlist: [MediaResult] {
        watchlist.items
            .filter { progress.progress(for: $0.id) == nil }
            .map(\.mediaResult)
    }
}

// MARK: - Marquee

/// The featured strip at the top of Home: wide backdrops with the title's logo,
/// swiped one page at a time. Neighbouring cards peek in to show there's more.
private struct FeaturedMarquee: View {
    let items: [MediaResult]
    @State private var current: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        FeaturedPage(item: item)
                            .containerRelativeFrame(.horizontal)
                            // A page leaving under the finger dims; nothing moves on its own.
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content.opacity(phase.isIdentity || reduceMotion ? 1 : 0.4)
                            }
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .sensoryFeedback(.selection, trigger: current)

            if items.count > 1 {
                PageDots(count: items.count,
                         index: items.firstIndex { $0.id == (current ?? items.first?.id) } ?? 0)
            }
        }
    }
}

/// One featured title, CinemaScope like Up next: the frame, the serif title,
/// one line of facts, Play (straight to video) and Save.
private struct FeaturedPage: View {
    let item: MediaResult

    private var facts: String {
        var parts: [String] = []
        if let year = item.year { parts.append(year) }
        if !item.genres.isEmpty { parts.append(item.genres.prefix(2).joined(separator: ", ")) }
        if let rating = item.imdbRating, !rating.isEmpty { parts.append("★ \(rating)") }
        if let place = HomeModel.topTenPlaces[item.id] { parts.append(place) }
        return parts.joined(separator: "   ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: item) {
                Color.clear
                    .aspectRatio(Theme.scopeAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        KFImage(item.backdropURL ?? item.posterURL)
                            .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1200, height: 600)))
                            .cancelOnDisappear(true)
                            .resizable()
                            .fade(duration: 0.25)
                            .placeholder { Theme.surface }
                            .scaledToFill()
                    }
                    .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), details")

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.display(40, relativeTo: .title1))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    NavigationLink(value: PlayTitle(item: item)) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Theme.accent, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    SaveCircleButton(item: item)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
        }
    }
}

/// The round Save next to Play: outlined on black, a check once saved.
private struct SaveCircleButton: View {
    let item: MediaResult
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        let saved = watchlist.contains(item.id)
        Button {
            watchlist.toggle(id: item.id, mediaType: item.type, title: item.name, posterURL: item.posterURL)
        } label: {
            Image(systemName: saved ? "checkmark" : "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: saved)
        .accessibilityLabel(saved ? "Remove from Watchlist" : "Add to Watchlist")
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Color.white.opacity(0.25))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.snappy, value: index)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Shelves

private struct PosterShelf: View {
    let title: String
    let items: [MediaResult]
    var seeAll: CatalogDestination?
    var ranked = false
    /// Off in the Watchlist row, where every poster is saved.
    var showsSavedBadge = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 12) {
            Group {
                if let seeAll {
                    // The title itself opens the full list; no extra link to compete with the posters.
                    NavigationLink(value: seeAll) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(title)
                                .sectionTitleStyle()
                                .lineLimit(2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.textTertiary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Shows the full list")
                } else {
                    SectionHeader(title)
                }
            }
            .padding(.horizontal, Theme.gutter)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PosterLink(item: item) {
                            if ranked {
                                RankedCard(rank: index + 1, item: item, width: PosterMetrics.shelfWidth(sizeClass))
                            } else {
                                PosterCard(item: item, showsSavedBadge: showsSavedBadge)
                                    .frame(width: PosterMetrics.shelfWidth(sizeClass))
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

/// A "Top 10" entry: the rank in tall condensed type with the poster
/// overlapping its right edge.
private struct RankedCard: View {
    let rank: Int
    let item: MediaResult
    let width: CGFloat

    var body: some View {
        let size = width * 1.25
        let serif = UIFont.systemFont(ofSize: size, weight: .light).fontDescriptor.withDesign(.serif)
        let metrics = serif.map { UIFont(descriptor: $0, size: size) } ?? UIFont.systemFont(ofSize: size, weight: .light)
        HStack(alignment: .bottom, spacing: -width * 0.08) {
            Text(String(rank))   // Western digits in every locale, like the posters
                .font(.system(size: size, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                // Trim the line box to the digits so they stand on the poster's bottom edge.
                .padding(.top, metrics.capHeight - metrics.ascender)
                .padding(.bottom, metrics.descender)
            PosterCard(item: item)
                .frame(width: width)
                .shadow(color: .black.opacity(0.6), radius: 8, x: -3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(item.name)")
    }
}

private struct PlaceholderShelf: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 170, height: 22)
                .padding(.horizontal, Theme.gutter)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.posterCorner, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: PosterMetrics.shelfWidth(sizeClass))
                        .aspectRatio(Theme.posterAspect, contentMode: .fit)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}


// MARK: - Up next

/// The next thing to watch: a CinemaScope frame, the serif title, the episode
/// in words, and one Play that goes straight to video.
private struct UpNextHero: View {
    let upNext: HomeModel.UpNext
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(DownloadStore.self) private var downloads

    private var item: MediaResult {
        let p = upNext.progress
        return MediaResult(id: p.id, type: p.mediaType, name: upNext.detail?.name ?? p.title,
                           year: nil, posterURL: p.posterURL, description: nil)
    }

    /// Resuming this exact episode (or the movie), not starting the next one.
    private var isResuming: Bool {
        let p = upNext.progress
        guard !p.isFinished else { return false }
        return p.mediaType == .movie || p.episodeID == upNext.episode?.id
    }

    private var minutesLeft: Int? {
        let p = upNext.progress
        guard isResuming, p.durationSeconds > 0 else { return nil }
        let minutes = Int(((p.durationSeconds - p.positionSeconds) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    private var playTitle: String {
        isResuming ? "Resume" : "Play"     // the line above already names the episode
    }

    private var isDownloaded: Bool {
        downloads.isDownloaded(mediaID: upNext.progress.id, episodeLabel: upNext.episode?.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(Theme.scopeAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    KFImage(upNext.episode?.thumbnailURL ?? upNext.detail?.backdropURL ?? upNext.progress.posterURL)
                        .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1200, height: 600)))
                        .resizable()
                        .fade(duration: 0.25)
                        .placeholder { Theme.surface }
                        .scaledToFill()
                }
                .clipped()
                .overlay {
                    // The frame opens the show, like every other picture on Home.
                    NavigationLink(value: item) { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name), details")
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("Up next")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(item.name)
                    .font(.display(40, relativeTo: .title1))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                meta
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    NavigationLink(value: PlayTitle(item: item)) {
                        VStack(spacing: 1) {
                            Label(playTitle, systemImage: "play.fill")
                                .font(.headline)
                            if let minutesLeft {
                                Text(minutesLeft >= 60 ? "\(minutesLeft / 60)h \(minutesLeft % 60)m left" : "\(minutesLeft) min left")
                                    .font(.caption.weight(.semibold))
                                    .opacity(0.6)
                            }
                        }
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: minutesLeft == nil ? 52 : 60)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    SaveCircleButton(item: item)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    /// "Season 1, episode 4  Cancer Man  46 min  Ready offline": the episode in words.
    private var meta: Text {
        var parts: [Text] = []
        if let episode = upNext.episode {
            parts.append(Text("Season \(episode.season), episode \(episode.episode)"))
            if !episode.name.isEmpty {
                parts.append(Text(episode.name).font(.system(.subheadline, design: .serif)).italic().foregroundStyle(.white))
            }
        }
        if let runtime = upNext.detail?.runtime, !isResuming { parts.append(Text(runtime)) }
        if isDownloaded { parts.append(Text("Ready offline")) }
        guard var line = parts.first else { return Text(" ") }
        for part in parts.dropFirst() { line = line + Text("   ") + part }
        return line
    }
}

// MARK: - Keep watching

/// Everything else in progress, as a hairline list; a row plays where you left off.
private struct KeepWatchingList: View {
    let items: [WatchProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keep watching")
                .sectionTitleStyle()
                .padding(.bottom, 8)
            ForEach(items) { item in
                NavigationLink(value: PlayTitle(item: item.mediaResult)) { row(item) }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        NavigationLink(value: item.mediaResult) {
                            Label("Go to Title", systemImage: "info.circle")
                        }
                        Button(role: .destructive) {
                            WatchProgressStore.shared.remove(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "xmark.circle")
                        }
                    }
            }
        }
        .padding(.horizontal, 20)
    }

    private func row(_ item: WatchProgress) -> some View {
        HStack(spacing: 14) {
            // Cinemeta keeps a wide backdrop per IMDb title; other ids fall back to the poster.
            let wide = item.id.hasPrefix("tt") ? URL(string: "https://images.metahub.space/background/medium/\(item.id)/img") : nil
            KFImage(wide ?? item.posterURL)
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 150)))
                .resizable()
                .placeholder { Theme.surface }
                .scaledToFill()
                .frame(width: 116, height: 116 / Theme.scopeAspect)
                .clipShape(RoundedRectangle(cornerRadius: Theme.stillCorner, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.display(19, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(line(for: item))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Theme.accent).frame(width: geo.size.width * item.fraction)
                        }
                    }
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func line(for item: WatchProgress) -> String {
        let left = max(0, item.durationSeconds - item.positionSeconds)
        let minutes = Int((left / 60).rounded())
        let time = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes) min left"
        guard let season = item.season, let episode = item.episode else { return time }
        return "Season \(season), episode \(episode)   \(time)"
    }
}

// MARK: - Offline

/// The catalog didn't load: one line, not a page. Everything above it still works.
private struct OfflineRow: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.body.weight(.semibold))
                Text("Downloads still play. \(message)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous))
        .padding(.horizontal, 20)
    }
}
#endif
