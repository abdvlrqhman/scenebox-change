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

    var body: some View {
        VStack(spacing: 0) {
            if Platform.isMac {
                macSearchHeader
            } else {
                phoneHeader
            }
            SearchResults(model: model)
        }
            .toolbar(.hidden, for: .navigationBar)
            .background(Theme.background)
            .statusBarScrim()
            .onAppear { focusIfAsked() }
            .onChange(of: router.focusSearch) { _, _ in focusIfAsked() }
            .onChange(of: model.query) { _, _ in model.run() }
            .onSubmit(of: .search) { model.run(immediate: true) }
            .task { if model.results.isEmpty { model.run() } }
    }

    // MARK: - Phone header

    private var phoneHeader: some View {
        VStack(spacing: 10) {
            RootHeader("Search")
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(macFieldFocused ? Theme.accent.opacity(0.6) : Theme.hairline))
            .animation(Theme.snappy, value: macFieldFocused)
            .padding(.horizontal, 16)

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
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
        .padding(.bottom, 12)
    }

    /// "Popular Movies", "New Drama TV Shows".
    private var browseTitle: String {
        [model.feed.title, model.genre, model.scope.title].compactMap { $0 }.joined(separator: " ")
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

            Picker("Type", selection: $model.scope) {
                ForEach(SearchModel.Scope.browseScopes) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            Picker("Feed", selection: $model.feed) {
                ForEach(CatalogFeed.allCases) { feed in
                    Text(feed.title).tag(feed)
                }
            }
            Picker("Genre", selection: $model.genre) {
                Text("All Genres").tag(String?.none)
                ForEach(MediaGenre.shared, id: \.self) { genre in
                    Text(genre).tag(String?.some(genre))
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    var body: some View {
        if model.isLoading && model.results.isEmpty {
            placeholderGrid
        } else if model.results.isEmpty, let message = model.errorMessage {
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn’t load", message: message,
                           actionTitle: "Try again") { model.run(immediate: true) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: model.isSearching ? "Nothing found" : "Nothing here yet",
                           message: model.isSearching
                               ? "Check the spelling, or try the original title."
                               : "Try another type, feed or genre.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
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
            .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
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
