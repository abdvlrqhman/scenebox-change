//
//  WatchBoxApp.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import SwiftVLC
import Kingfisher

@main
struct WatchBoxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        Self.configureImageCache()

        _ = VLCInstance.prewarmShared()

        StreamCoordinator.pruneCacheAtLaunch()

        // Resume downloads that were running when the app last closed, and keep
        // them going when the app leaves the screen.
        _ = DownloadStore.shared
        BackgroundDownloads.shared.start()
    }

    private static func configureImageCache() {
        let storage = ImageCache.default.memoryStorage
        storage.config.totalCostLimit = 80 * 1024 * 1024
        storage.config.countLimit = 200
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
    }
}
