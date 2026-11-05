//
//  SearchView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            SearchScreen()
                .mediaNavigationDestinations()
                .navigationDestination(for: CatalogDestination.self) { dest in
                    CatalogListView(type: dest.type, feed: dest.feed)
                }
        }
    }
}

struct SearchScreen: View {
    @State private var model = SearchModel()
    @State private var router = TabRouter.shared
    /// While typing, which kind of result to show (nil: all).
    @State private var resultType: MediaType?

    var body: some View {
        VStack(spacing: 0) {
            if Platform.isMac {
                macSearchHeader
            } else {
                phoneHeader
            }
            SearchResults(model: model, filter: resultType)
        }
            .toolbar(.hidden, for: .navigationBar)
            .background(Theme.background)
            .statusBarScrim()
            .onAppear {
                focusIfAsked()
                // The tab is for typing: the field is ready (screenshot runs keep the grid visible).
                if !Platform.isMac, model.query.isEmpty, !UserDefaults.standard.bool(forKey: "SBScreenshots") {
                    macFieldFocused = true
                }
            }
            .onChange(of: router.focusSearch) { _, _ in focusIfAsked() }
            .onChange(of: model.query) { _, _ in model.run() }
            .onSubmit(of: .search) { model.run(immediate: true) }
            .task {
                #if DEBUG
                if let query = UserDefaults.standard.string(forKey: "SBSearchQuery") { model.query = query }   // screenshots
                #endif
                if model.results.isEmpty { model.run() }
            }
    }

    // MARK: - Phone header

    private var phoneHeader: some View {
        VStack(spacing: 10) {
            RootHeader(title: "Search") { ProfileButton() }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Movies, shows and anime", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($macFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { model.run(immediate: true) }
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.vertical, -12)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(macFieldFocused ? Theme.accent.opacity(0.6) : Theme.hairline))
            .animation(Theme.snappy, value: macFieldFocused)
            .padding(.horizontal, Theme.gutter)

            chips

            if !model.isSearching {
                // What the grid shows is its title, and tapping it changes the filters.
                filterMenu {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(browseTitle)
                            .sectionTitleStyle()
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(filtersActive ? Theme.accent : Theme.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(browseTitle), change filters")
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 6)
            }
        }
        .padding(.bottom, 12)
    }

    /// Kinds of title, and genres while browsing: neutral until chosen.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.isSearching {
                    chip("All", on: resultType == nil) { resultType = nil }
                    chip("Movies", on: resultType == .movie) { resultType = .movie }
                    chip("TV shows", on: resultType == .series) { resultType = .series }
                    chip("Anime", on: resultType == .anime) { resultType = .anime }
                } else {
                    ForEach(SearchModel.Scope.browseScopes) { scope in
                        chip(scope.title, on: model.scope == scope) { model.scope = scope }
                    }
                    Theme.hairline.frame(width: 1, height: 22).padding(.horizontal, 4)
                    ForEach(MediaGenre.shared, id: \.self) { genre in
                        // Tapping the chosen genre again clears it.
                        chip(genre, on: model.genre == genre) { model.genre = model.genre == genre ? nil : genre }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.top, 4)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Theme.onAccent : .white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(on ? Theme.accent : Color.white.opacity(0.10), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "Popular Movies", "New Drama TV Shows".
    private var browseTitle: String {
        // The chips already say the kind; the title is the feed and the genre.
        [model.feed.title, model.genre].compactMap { $0 }.joined(separator: " ")
    }

    /// Home's search button lands here with the keyboard up.
    private func focusIfAsked() {
        guard router.focusSearch else { return }
        router.focusSearch = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))   // after the tab switch settles
            macFieldFocused = true
        }
    }

    // MARK: - Mac header

    @FocusState private var macFieldFocused: Bool

    private var macSearchHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search movies, shows & anime", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($macFieldFocused)
                    .onSubmit { model.run(immediate: true) }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 520)

            if !model.isSearching {
                filterMenu {
                    Label("Filters", systemImage: filtersActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
            Spacer(minLength: 0)
            if model.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .onAppear { macFieldFocused = true }
    }

    // MARK: - Filters

    private func filterMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            if filtersActive {
                Button { resetFilters() } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }

            // On iPhone the chips pick kind and genre; the menu is for the feed.
            if Platform.isMac {
                Picker("Type", selection: $model.scope) {
                    ForEach(SearchModel.Scope.browseScopes) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }
            Picker("Feed", selection: $model.feed) {
                ForEach(CatalogFeed.allCases) { feed in
                    Text(feed.title).tag(feed)
                }
            }
            if Platform.isMac {
                Picker("Genre", selection: $model.genre) {
                    Text("All Genres").tag(String?.none)
                    ForEach(MediaGenre.shared, id: \.self) { genre in
                        Text(genre).tag(String?.some(genre))
                    }
                }
            }
        } label: {
            label()
        }
        .tint(filtersActive ? Theme.accent : .white)
        .onChange(of: model.scope) { _, _ in model.run() }
        .onChange(of: model.feed) { _, _ in model.run() }
        .onChange(of: model.genre) { _, _ in model.run() }
    }

    private var filtersActive: Bool {
        model.feed != .popular || model.genre != nil
    }

    private func resetFilters() {
        model.feed = .popular
        model.genre = nil
        model.run()
    }
}

struct SearchResults: View {
    let model: SearchModel
    var filter: MediaType? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var shown: [MediaResult] {
        guard let filter else { return model.results }
        return model.results.filter { $0.type == filter }
    }

    @ViewBuilder
    var body: some View {
        if model.isLoading && model.results.isEmpty {
            placeholderGrid
        } else if model.results.isEmpty, let message = model.errorMessage {
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn’t load", message: message,
                           actionTitle: "Try again") { model.run(immediate: true) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty {
            if model.isSearching {
                EmptyStateView(systemImage: "magnifyingglass", title: "Nothing found for “\(model.query)”",
                               message: "Check the spelling, or try the original title.",
                               actionTitle: "Browse instead") { model.query = "" }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(systemImage: "magnifyingglass", title: "Nothing here yet",
                               message: "Try another type, feed or genre.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.isSearching, !Platform.isMac {
            list
        } else {
            grid
        }
    }

    /// Search results as hairline rows: poster, title, year and kind.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.missingKinds.isEmpty {
                    missingRow
                }
                ForEach(shown) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 14) {
                            PosterImage(url: item.posterURL, cornerRadius: Theme.posterCorner)
                                .frame(width: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.display(19, weight: .medium, relativeTo: .headline))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text(details(item))
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
                    .buttonStyle(.pressable)
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// One kind didn't answer: say so instead of quietly showing less.
    private var missingRow: some View {
        let names = model.missingKinds.map { kind in
            switch kind {
            case .movie: "Movies"
            case .series: "TV shows"
            case .anime: "Anime"
            }
        }
        return HStack(spacing: 12) {
            Text("\(names.joined(separator: " and ")) didn’t load.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Button("Try again") { model.run(immediate: true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minHeight: 44)
        }
        .padding(.vertical, 4)
    }

    /// "2008   TV show   ★ 9.5"
    private func details(_ item: MediaResult) -> String {
        let kind = switch item.type {
        case .movie: "Movie"
        case .series: "TV show"
        case .anime: "Anime"
        }
        let rating = item.imdbRating.flatMap { $0.isEmpty ? nil : "★ \($0)" }
        return [item.year, kind, rating].compactMap { $0 }.joined(separator: "   ")
    }

    /// Poster-shaped placeholders while the first page loads.
    private var placeholderGrid: some View {
        ScrollView {
            LazyVGrid(columns: PosterMetrics.gridColumns(sizeClass), spacing: 12) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.posterCorner, style: .continuous)
                        .fill(Theme.surface)
                        .aspectRatio(Theme.posterAspect, contentMode: .fit)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollDisabled(true)
        .accessibilityLabel("Loading")
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: PosterMetrics.gridColumns(sizeClass), spacing: 12) {
                ForEach(model.results) { item in
                    PosterLink(item: item) {
                        PosterCard(item: item)
                    }
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)

            if model.isLoadingMore {
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if model.isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isLoading)
    }
}
#endif
