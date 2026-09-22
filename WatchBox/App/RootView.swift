//
//  RootView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

struct RootView: View {
    @State private var profiles = ProfileStore.shared
    @State private var externalStreamer: StreamCoordinator?
    @State private var links = DeepLinkRouter.shared

    var body: some View {
        Group {
            if profiles.selected != nil {
                RootTabView()
            } else {
                ProfilePickerView()
            }
        }
        #if DEBUG
        .task {
            startAutoStreamIfRequested()
            // `-SBOpenDetail series/tt0903747` opens a title (screenshots, debugging).
            if let path = UserDefaults.standard.string(forKey: "SBOpenDetail"),
               let url = URL(string: "scenebox://detail/\(path)") {
                try? await Task.sleep(for: .seconds(1.5))
                links.handle(url)
            }
        }
        #endif
        .onChange(of: links.pendingMagnet) { _, magnet in
            guard let magnet else { return }
            links.pendingMagnet = nil
            play(magnet: magnet, fileIndex: nil, title: magnet.displayName ?? "Magnet link")
        }
        .fullScreenCover(isPresented: Binding(
            get: { externalStreamer?.isPresenting ?? false },
            set: { presented in if !presented { externalStreamer?.stop() } }
        )) {
            if let externalStreamer {
                StreamPlayerContainer(streamer: externalStreamer)
                    .environment(AppSettings.shared)
            }
        }
        .environment(profiles)
        .onChange(of: profiles.selected?.id, initial: true) { _, profileID in
            guard let profileID else { return }
            WatchProgressStore.shared.use(LocalWatchProgressBackend(profileID: profileID))
            WatchlistStore.shared.use(LocalWatchlistBackend(profileID: profileID))
        }
    }

    private func play(magnet: MagnetLink, fileIndex: Int?, title: String) {
        let stream = TorrentStream(
            id: magnet.infoHash.hexString,
            title: title,
            displayName: title,
            infoHash: magnet.infoHash,
            fileIndex: fileIndex,
            trackers: magnet.trackers,
            seeders: nil, sizeText: nil, resolution: nil, url: nil)
        let streamer = externalStreamer ?? StreamCoordinator()
        externalStreamer = streamer
        streamer.play(stream, title: stream.title, backdropURL: nil)
    }

    #if DEBUG
    private func startAutoStreamIfRequested() {
        guard externalStreamer == nil,
              let magnetString = UserDefaults.standard.string(forKey: "WBAutoStreamMagnet"),
              let magnet = MagnetLink(string: magnetString) else { return }
        let fileIndex = UserDefaults.standard.object(forKey: "WBAutoStreamFileIndex") != nil
            ? UserDefaults.standard.integer(forKey: "WBAutoStreamFileIndex") : nil
        play(magnet: magnet, fileIndex: fileIndex, title: magnet.displayName ?? "Auto-stream test")
    }
    #endif
}
