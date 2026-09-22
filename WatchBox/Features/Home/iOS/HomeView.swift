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
    @State private var search = SearchModel()
    @Environment(AppSettings.self) private var settings
    @Environment(WatchProgressStore.self) private var progress
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        NavigationStack {
            Group {
                if search.isSearching {
                    SearchResults(model: search)
                } else if let message = model.errorMessage, model.shelves.isEmpty, !model.isLoading {
                    EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn’t load titles",
                                   message: message, actionTitle: "Try again") { model.reload() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    feed
                }
            }
            .background(Theme.background)
            .navigationTitle(Platform.isMac ? "" : "Home")
            .toolbar {
                if search.isSearching, search.isLoading {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .toolbar(Platform.isMac ? .hidden : .automatic, for: .navigationBar)
            .modifier(HomeSearchField(query: $search.query))
            .onChange(of: search.query) { _, query in
                if query.trimmingCharacters(in: .whitespaces).isEmpty { return }
                search.run()
            }
            .onSubmit(of: .search) { search.run(immediate: true) }
            .mediaNavigationDestinations()
            .navigationDestination(for: CatalogDestination.self) { dest in
                CatalogListView(type: dest.type, feed: dest.feed)
            }
        }
        .task { model.loadIfNeeded() }
        .onAppear { progress.refresh() }
        .onChange(of: settings.streamSourceBases) { _, _ in
            model.applySettings(settings)
            search.applySettings(settings)
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Platform.isMac ? 34 : 28) {
                if !featured.isEmpty {
                    FeaturedMarquee(items: featured)
                }
                if !progress.continueItems.isEmpty {
                    ContinueWatchingShelf(items: progress.continueItems)
                }
                if !unwatchedWatchlist.isEmpty {
                    PosterShelf(title: "Your Watchlist", items: unwatchedWatchlist)
                }
                if model.shelves.isEmpty {
                    // Placeholders keep the layout still while the catalog loads.
                    ForEach(0..<3, id: \.self) { _ in PlaceholderShelf() }
                } else {
                    ForEach(model.shelves) { shelf in
                        PosterShelf(title: shelf.title, items: shelf.items,
                                    seeAll: CatalogDestination(type: shelf.type, feed: shelf.feed))
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable {
            progress.refresh()
            async let catalog: () = model.refresh()
            async let saved: () = watchlist.refresh()
            _ = await (catalog, saved)
        }
    }

    /// A few popular movies and shows, alternating, for the marquee.
    private var featured: [MediaResult] {
        let pools = model.shelves.prefix(2).map { shelf in
            Array(shelf.items.filter { $0.backdropURL != nil }.prefix(3))
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

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        PosterLink(item: item) {
                            FeaturedCard(item: item)
                        }
                        .overlay(alignment: .topTrailing) { FeaturedWatchlistButton(item: item) }
                        .containerRelativeFrame(.horizontal) { width, _ in
                            sizeClass == .regular ? min(width * 0.62, 760) : width - 32
                        }
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()

            if items.count > 1 {
                PageDots(count: items.count,
                         index: items.firstIndex { $0.id == (current ?? items.first?.id) } ?? 0)
            }
        }
    }
}

private struct FeaturedCard: View {
    let item: MediaResult

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .background {
                KFImage(item.backdropURL)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1200, height: 900)))
                    .cacheOriginalImage()
                    .cancelOnDisappear(true)
                    .fade(duration: 0.25)
                    .placeholder { Theme.surface }
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.55), location: 0.7),
                    .init(color: .black.opacity(0.88), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(Theme.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.name)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let logo = item.logoURL {
                KFImage(logo)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 600, height: 240)))
                    .cancelOnDisappear(true)
                    .placeholder { titleText }
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 76, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.5), radius: 8)
            } else {
                titleText
            }
            HStack(spacing: 10) {
                if let year = item.year { Text(year) }
                if let rating = item.imdbRating, !rating.isEmpty {
                    Label(rating, systemImage: "star.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.yellow)
                }
                if !item.genres.isEmpty {
                    Text(item.genres.prefix(2).joined(separator: ", "))
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
    }

    private var titleText: some View {
        Text(item.name)
            .font(.display(34))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

}

/// Sits over the card (not inside its link) so the tap reaches it.
private struct FeaturedWatchlistButton: View {
    let item: MediaResult
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        let saved = watchlist.contains(item.id)
        Button {
            withAnimation(Theme.snappy) {
                watchlist.toggle(id: item.id, mediaType: item.type, title: item.name, posterURL: item.posterURL)
            }
        } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(saved ? Theme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: saved)
        .padding(12)
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 12) {
            SectionHeader(title: title) {
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        PosterLink(item: item) {
                            PosterCard(item: item).frame(width: PosterMetrics.shelfWidth(sizeClass))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct PlaceholderShelf: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 170, height: 22)
                .padding(.horizontal, 16)
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.posterCorner, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: PosterMetrics.shelfWidth(sizeClass))
                        .aspectRatio(Theme.posterAspect, contentMode: .fit)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct HomeSearchField: ViewModifier {
    @Binding var query: String

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
        } else {
            content.searchable(text: $query, prompt: "Movies, shows and anime")
        }
    }
}
#endif
