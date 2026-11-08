//
//  RootTabView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

enum AppTab: String, Hashable {
    case home, search, library, profile

    /// `-SBInitialTab library` (screenshots and debugging) picks the first tab.
    static var initial: AppTab {
        let asked = UserDefaults.standard.string(forKey: "SBInitialTab").flatMap(AppTab.init(rawValue:)) ?? .home
        #if os(tvOS)
        return asked
        #else
        return asked == .profile ? .home : asked     // a sheet there, not a tab
        #endif
    }
}

struct RootTabView: View {
    @State private var router = TabRouter.shared
    @State private var settings = AppSettings.shared
    @State private var downloads = DownloadStore.shared
    @State private var watchProgress = WatchProgressStore.shared
    @State private var watchlist = WatchlistStore.shared
    @Environment(ProfileStore.self) private var profiles
    @State private var detailItem: MediaResult?
    @State private var links = DeepLinkRouter.shared
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        TabView(selection: $router.tab) {
            #if os(tvOS)
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                TVHomeView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                TVSearchView()
            }
            #else
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView()
            }
            #endif

            #if os(tvOS)
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
            #else
            Tab("My Stuff", systemImage: "play.square.stack.fill", value: AppTab.library) {
                LibraryView()
            }
            // Red means "needs you": only downloads that failed.
            .badge(downloads.downloads.filter { $0.phase == .failed }.count)
            #endif
        }
        .tint(settings.accentColor)
        .environment(settings)
        .environment(downloads)
        .environment(watchProgress)
        .environment(watchlist)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: router.tab)
        // `initial` picks up a link that arrived while the profile picker was up.
        .onChange(of: links.pendingDetail, initial: true) { _, item in
            guard let item else { return }
            links.pendingDetail = nil
            detailItem = item
        }
        #if os(iOS)
        .sheet(isPresented: $router.showProfile) {
            ProfileView()
                .environment(settings)
                .environment(downloads)
                .environment(watchProgress)
                .environment(watchlist)
                .environment(profiles)
                .preferredColorScheme(.dark)
        }
        // Every title pushes the same way on iPad too (posters used to open a sheet while every
        // other way in pushed); a sheet also blocked Settings from opening over it.
        .environment(\.openMediaDetail, nil)
        .sheet(item: $detailItem) { item in
            NavigationStack {
                MediaDetailView(mediaID: item.id, type: item.type, fallbackTitle: item.name)
                    .mediaNavigationDestinations()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { detailItem = nil }
                        }
                    }
            }
            .environment(settings)
            .environment(downloads)
            .environment(watchProgress)
            .environment(watchlist)
            .environment(\.openMediaDetail, nil)
            .preferredColorScheme(.dark)
        }
        #else
        // Full screen like a pushed detail page; Menu closes it.
        .fullScreenCover(item: $detailItem) { item in
            NavigationStack {
                MediaDetailView(mediaID: item.id, type: item.type, fallbackTitle: item.name)
                    .mediaNavigationDestinations()
            }
            .environment(settings)
            .environment(downloads)
            .environment(watchProgress)
            .environment(watchlist)
            .preferredColorScheme(.dark)
        }
        #endif
    }
}
