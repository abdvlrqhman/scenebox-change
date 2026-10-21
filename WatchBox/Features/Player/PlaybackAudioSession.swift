//
//  PlaybackAudioSession.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import AVFoundation

enum PlaybackAudioSession {
    private static let queue = DispatchQueue(label: "playback.audiosession")

    /// True while a player owns the audio session; the background-download
    /// keep-alive then leaves the session's category alone.
    private(set) static var isActive = false
    /// Players holding the session: the next episode's player opens before the old one lets go.
    private static var holders = 0

    static func activate() async {
        holders += 1
        isActive = true
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback)
                try? session.setActive(true)
                done.resume()
            }
        }
    }

    static func deactivate() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        isActive = false
        queue.async {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
