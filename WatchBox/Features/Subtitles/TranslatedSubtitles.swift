//
//  TranslatedSubtitles.swift
//  SceneBox
//

import Foundation
import CryptoKit

/// Translations made on this device, kept so an episode translates once.
/// Each is saved as an SRT plus a small description of the version it
/// represents, so it can be offered (and remembered) like any other.
nonisolated enum TranslatedSubtitles {
    static let idPrefix = "tr-"

    static func id(englishID: String, target: String) -> String {
        "\(idPrefix)\(target)-\(englishID)"
    }

    static func track(from english: SubtitleTrack, target: String, url: URL) -> SubtitleTrack {
        SubtitleTrack(
            id: id(englishID: english.id, target: target),
            languageCode: target,
            url: url,
            fileName: (english.fileName ?? "English") + " (translated on this device)",
            encoding: "UTF-8",
            fps: english.fps,
            provider: "Translated on device",
            downloads: 0,
            isHearingImpaired: english.isHearingImpaired,
            isMachineTranslated: true)
    }

    static func write(_ cues: [SubtitleCue], track: SubtitleTrack) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appendingPathComponent(digest(track.id))
        let srt = base.appendingPathExtension("srt")
        try Data(SubtitleCues.srt(cues).utf8).write(to: srt, options: .atomic)
        let described = SubtitleTrack(id: track.id, languageCode: track.languageCode, url: srt,
                                  fileName: track.fileName, encoding: track.encoding, fps: track.fps,
                                  provider: track.provider, downloads: 0,
                                  isHearingImpaired: track.isHearingImpaired, isMachineTranslated: true)
        try JSONEncoder().encode(described).write(to: base.appendingPathExtension("json"), options: .atomic)
        return srt
    }

    /// What's translated so far (the rest still in English), shown while the
    /// translation finishes. Not kept.
    static func writePartial(_ cues: [SubtitleCue], id: String) throws -> URL {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        removePartials(id: id)
        // A fresh name per write: the player attaches files, and a changed file
        // under the same name wouldn't be re-read.
        let url = workDirectory.appendingPathComponent("\(digest(id))-\(Int(Date().timeIntervalSince1970 * 1000))")
            .appendingPathExtension("srt")
        try Data(SubtitleCues.srt(cues).utf8).write(to: url, options: .atomic)
        return url
    }

    /// The player reads a subtitle file whole when it attaches it, so older
    /// partial files can go.
    static func removePartials(id: String) {
        let prefix = digest(id) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "srt" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Unfinished work and partial files.
    static var workDirectory: URL { directory.appendingPathComponent("InProgress", isDirectory: true) }

    /// Everything subtitle-related that can be fetched or made again.
    static var cacheDirectories: [URL] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [caches.appendingPathComponent("Subtitles", isDirectory: true), directory]
    }

    static func totalCacheBytes() -> Int64 {
        var total: Int64 = 0
        for root in cacheDirectories {
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { continue }
            for case let url as URL in files {
                total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
            }
        }
        return total
    }

    static func clearCaches() {
        for root in cacheDirectories { try? FileManager.default.removeItem(at: root) }
    }

    /// A translation made earlier, by its version id.
    static func cached(id: String) -> (track: SubtitleTrack, file: URL)? {
        let base = directory.appendingPathComponent(digest(id))
        let srt = base.appendingPathExtension("srt")
        guard FileManager.default.fileExists(atPath: srt.path),
              let data = try? Data(contentsOf: base.appendingPathExtension("json")),
              var track = try? JSONDecoder().decode(SubtitleTrack.self, from: data) else { return nil }
        // The app container can move between installs; point at today's path.
        track = SubtitleTrack(id: track.id, languageCode: track.languageCode, url: srt,
                              fileName: track.fileName, encoding: track.encoding, fps: track.fps,
                              provider: track.provider, downloads: 0,
                              isHearingImpaired: track.isHearingImpaired, isMachineTranslated: true)
        return (track, srt)
    }

    private static var directory: URL {
        // Application Support, not Caches: a translation takes a while to redo.
        AppDirectories.support.appendingPathComponent("Subtitles/Translated", isDirectory: true)
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
