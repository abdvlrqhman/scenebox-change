//
//  SourceMemory.swift
//  SceneBox
//

import Foundation

/// Identity of a source (a release) for one episode: the torrent's info-hash
/// plus the file inside it, so episodes of a season pack stay apart. Debrid
/// links of the same torrent share the key, which is right: same release, same
/// subtitle timing.
nonisolated enum SourceKey {
    static func make(streamID: String, fileIndex: Int?) -> String {
        "\(streamID.lowercased())#\(fileIndex ?? -1)"
    }

    static func make(_ stream: TorrentStream) -> String {
        make(streamID: stream.id, fileIndex: stream.fileIndex)
    }
}

/// The source each episode (or movie) last played successfully, so the source
/// list can put it first and auto-pick can reuse it.
enum SourceMemory {
    struct Entry: Codable {
        var sourceKey: String
        var name: String
        var lastUsed: Double
    }

    private static let key = "sourceMemory"
    private static let limit = 500

    static func last(mediaID: String, season: Int?, episode: Int?) -> Entry? {
        load()[id(mediaID, season, episode)]
    }

    static func remember(_ stream: TorrentStream, mediaID: String, season: Int?, episode: Int?) {
        remember(sourceKey: SourceKey.make(stream), name: stream.displayName,
                 mediaID: mediaID, season: season, episode: episode)
    }

    static func remember(sourceKey: String, name: String, mediaID: String, season: Int?, episode: Int?) {
        var all = load()
        all[id(mediaID, season, episode)] = Entry(sourceKey: sourceKey, name: name,
                                                  lastUsed: Date().timeIntervalSince1970)
        if all.count > limit {
            for (key, _) in all.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }).prefix(all.count - limit) {
                all[key] = nil
            }
        }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all
    }

    private static func id(_ mediaID: String, _ season: Int?, _ episode: Int?) -> String {
        guard let season, let episode else { return mediaID }
        return "\(mediaID):\(season):\(episode)"
    }
}
