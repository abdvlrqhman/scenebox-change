//
//  WatchlistStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class WatchlistStore {
    static let shared = WatchlistStore()

    private(set) var items: [WatchlistItem] = []

    @ObservationIgnored private var backend: WatchlistBackend
    /// Bumped on every backend switch so a slower, older load can't land last.
    @ObservationIgnored private var generation = 0

    init(backend: WatchlistBackend = LocalWatchlistBackend()) {
        self.backend = backend
        Task { await reload() }
    }

    func use(_ backend: WatchlistBackend) {
        self.backend = backend
        items = []
        generation += 1
        Task { await reload() }
    }

    private func reload() async {
        let current = generation
        let loaded = await backend.load()
        guard current == generation else { return }
        items = loaded.sorted { $0.addedAt > $1.addedAt }
    }

    func refresh() async { await reload() }

    func contains(_ mediaID: String) -> Bool {
        items.contains { $0.id == mediaID }
    }

    func toggle(id: String, mediaType: MediaType, title: String, posterURL: URL?) {
        if contains(id) {
            remove(id: id)
        } else {
            let item = WatchlistItem(id: id, mediaType: mediaType, title: title,
                                     posterURLString: posterURL?.absoluteString,
                                     addedAt: Date())
            items.insert(item, at: 0)
            Task { [backend] in await backend.upsert(item) }
        }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        Task { [backend] in await backend.remove(id: id) }
    }
}
