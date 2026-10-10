//
//  HomeModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        let title: String
        let type: MediaType
        let feed: CatalogFeed
        var genre: String? = nil
        /// Netflix-style "Top 10": the first ten, numbered.
        var isRanked = false
        /// Only titles rated at least this on IMDb, best first. Cinemeta's own
        /// "imdbRating" feed isn't sorted by rating, so quality rows filter the popular one.
        var minRating: Double? = nil
        var items: [MediaResult] = []

        var id: String {
            [type.rawValue, feed.rawValue, genre, minRating.map { "\($0)+" }].compactMap { $0 }.joined(separator: "-")
        }
        var shown: [MediaResult] { isRanked ? Array(items.prefix(10)) : items }
        /// "See all" opens the plain feed, which wouldn't match a rating-filtered row.
        var destination: CatalogDestination? {
            minRating == nil ? CatalogDestination(type: type, feed: feed, genre: genre) : nil
        }

        func filled(with feedItems: [MediaResult]) -> Shelf {
            var shelf = self
            shelf.items = feedItems
            if let minRating {
                shelf.items = feedItems
                    .compactMap { item in Double(item.imdbRating ?? "").map { (item, $0) } }
                    .filter { $0.1 >= minRating }
                    .sorted { $0.1 > $1.1 }
                    .map { $0.0 }
            }
            return shelf
        }
    }

    /// Loaded with the screen. The Top 10s also feed the marquee.
    private static let specs: [Shelf] = [
        Shelf(title: "Top 10 Shows", type: .series, feed: .popular, isRanked: true),
        Shelf(title: "New Movies", type: .movie, feed: .new),
        Shelf(title: "Top 10 Movies", type: .movie, feed: .popular, isRanked: true),
        Shelf(title: "Popular Anime", type: .anime, feed: .popular),
        Shelf(title: "Top Rated Movies", type: .movie, feed: .popular, minRating: 7.5),
    ]

    /// Further down; each loads when it scrolls into view (a feed is 100–600 KB).
    private static let genreSpecs: [Shelf] = [
        Shelf(title: "Crime TV Shows", type: .series, feed: .popular, genre: "Crime"),
        Shelf(title: "Action Movies", type: .movie, feed: .popular, genre: "Action"),
        Shelf(title: "Comedies", type: .movie, feed: .popular, genre: "Comedy"),
        Shelf(title: "Sci-Fi Shows", type: .series, feed: .popular, genre: "Sci-Fi"),
        Shelf(title: "Horror Movies", type: .movie, feed: .popular, genre: "Horror"),
        Shelf(title: "Critically Acclaimed TV", type: .series, feed: .popular, minRating: 8),
        Shelf(title: "Thriller Movies", type: .movie, feed: .popular, genre: "Thriller"),
        Shelf(title: "Animated Movies", type: .movie, feed: .popular, genre: "Animation"),
        Shelf(title: "Documentaries", type: .movie, feed: .popular, genre: "Documentary"),
        Shelf(title: "Romantic Movies", type: .movie, feed: .popular, genre: "Romance"),
    ]

    private(set) var shelves: [Shelf] = []
    private(set) var genreShelves: [Shelf] = HomeModel.genreSpecs
    private(set) var becauseYouWatched: Shelf?
    private(set) var featured: MediaResult?
    private(set) var featuredDetail: MediaDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var requestedGenres: Set<String> = []
    @ObservationIgnored private var becauseSourceID: String?

    init(settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        load()
    }

    func reload() {
        loaded = true
        load()
    }

    func refresh() async {
        reload()
        await loadTask?.value
    }

    func applySettings(_ settings: AppSettings) {
        search = TorrentSearch(sourceBases: settings.streamSourceBases)
        if loaded { load() }
    }

    /// Fills a genre row the first time it scrolls into view; an empty or
    /// failed one drops out until the next refresh.
    func loadGenreShelf(_ id: String) {
        guard requestedGenres.insert(id).inserted,
              let spec = genreShelves.first(where: { $0.id == id }) else { return }
        Task { [search] in
            let items = (try? await search.catalog(type: spec.type, feed: spec.feed, genre: spec.genre)) ?? []
            let shelf = spec.filled(with: items)
            guard let index = genreShelves.firstIndex(where: { $0.id == id }) else { return }
            if shelf.items.isEmpty { genreShelves.remove(at: index) } else { genreShelves[index] = shelf }
        }
    }

    /// Well-rated titles sharing a genre with the last thing watched, best first.
    func loadBecauseYouWatched(_ recent: WatchProgress?) {
        guard let recent, recent.id.hasPrefix("tt"), recent.mediaType != .anime,
              recent.id != becauseSourceID else { return }
        becauseSourceID = recent.id
        Task { [search] in
            guard let detail = try? await search.detail(id: recent.id, type: recent.mediaType) else { return }
            let known = detail.genres.filter { MediaGenre.shared.contains($0) }
            // Drama is on almost everything; a sharper genre makes a better match.
            guard let genre = known.first(where: { $0 != "Drama" }) ?? known.first,
                  let items = try? await search.catalog(type: recent.mediaType, feed: .popular, genre: genre),
                  becauseSourceID == recent.id else { return }
            let shelf = Shelf(title: "Because you watched \(recent.title)", type: recent.mediaType,
                              feed: .popular, genre: genre, minRating: 7)
                .filled(with: items.filter { $0.id != recent.id })
            becauseYouWatched = shelf.items.isEmpty ? nil : shelf
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        genreShelves = Self.genreSpecs
        requestedGenres = []
        loadTask?.cancel()
        loadTask = Task { [search] in
            let specs = Self.specs
            let rows = await withTaskGroup(of: (Int, [MediaResult]).self) { group in
                for (i, spec) in specs.enumerated() {
                    let (type, feed) = (spec.type, spec.feed)   // plain values into the child task
                    group.addTask {
                        let items = (try? await search.catalog(type: type, feed: feed)) ?? []
                        return (i, items)
                    }
                }
                var results = [[MediaResult]](repeating: [], count: specs.count)
                for await (i, items) in group { results[i] = items }
                return results
            }
            guard !Task.isCancelled else { return }

            var built: [Shelf] = []
            for (i, spec) in specs.enumerated() {
                let shelf = spec.filled(with: rows[i])
                if !shelf.items.isEmpty { built.append(shelf) }
            }
            shelves = built
            errorMessage = built.isEmpty ? "Couldn’t load the catalog." : nil
            isLoading = false

            if let top = built.first?.items.first {
                featured = top
                let detail = try? await search.detail(id: top.id, type: top.type)
                guard !Task.isCancelled else { return }
                featuredDetail = detail
            }
        }
    }
}
