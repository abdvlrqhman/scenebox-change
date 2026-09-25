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

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
