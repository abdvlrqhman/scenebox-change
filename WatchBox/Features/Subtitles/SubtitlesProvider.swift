//
//  SubtitlesProvider.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation
import CryptoKit

/// OpenSubtitles (via the Stremio addon) lookups and downloads.
///
/// One shared instance, so the list fetched while a torrent buffers is the one
/// the player uses a moment later instead of a second slow request.
actor SubtitlesProvider {
    static let shared = SubtitlesProvider()

    private let base = "https://opensubtitles-v3.strem.io"
    private var lists: [String: (tracks: [SubtitleTrack], fetched: Date)] = [:]
    private var inflightLists: [String: Task<[SubtitleTrack], Never>] = [:]
    private var inflightFiles: [String: Task<URL, Error>] = [:]

    enum Failure: Error { case badResponse, notSubtitles }

    // MARK: Lists

    func subtitles(imdbID: String, type: MediaType, season: Int?, episode: Int?) async -> [SubtitleTrack] {
        var id = imdbID
        if type == .series, let season, let episode { id += ":\(season):\(episode)" }

        if let cached = lists[id], Date().timeIntervalSince(cached.fetched) < 6 * 3600, !cached.tracks.isEmpty {
            return cached.tracks
        }
        if let running = inflightLists[id] { return await running.value }

        let task = Task { await Self.fetchList(id: id, type: type, base: base) }
        inflightLists[id] = task
        let tracks = await task.value
        inflightLists[id] = nil
        if !tracks.isEmpty { lists[id] = (tracks, Date()) }
        return tracks
    }

    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack] {
        await subtitles(imdbID: context.imdbID, type: context.type,
                        season: context.season, episode: context.episode)
    }

    /// Tries the network a few times (the addon is often slow to answer), then
    /// falls back to the last list saved on disk.
    private static func fetchList(id: String, type: MediaType, base: String) async -> [SubtitleTrack] {
        guard let url = URL(string: "\(base)/subtitles/\(type.rawValue)/\(id).json") else { return [] }
        let listCache = directory.appendingPathComponent("list-\(digest(id)).json")

        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            if Task.isCancelled { break }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let tracks = parse(data)
            else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: listCache, options: .atomic)
            return tracks
        }
        if let cached = try? Data(contentsOf: listCache), let tracks = parse(cached) {
            return tracks
        }
        return []
    }

    private static func parse(_ data: Data) -> [SubtitleTrack]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["subtitles"] as? [[String: Any]]
        else { return nil }

        var seen = Set<String>()
        var out: [SubtitleTrack] = []
        for item in raw {
            guard let urlString = item["url"] as? String, let url = URL(string: urlString),
                  let lang = item["lang"] as? String else { continue }
            let identifier = (item["id"] as? String) ?? urlString
            guard seen.insert(identifier).inserted else { continue }
            out.append(SubtitleTrack(
                id: identifier,
                languageCode: SubtitleLanguage.canonical(lang),
                url: url,
                fileName: (item["subtitleFileName"] as? String) ?? (item["movieReleaseName"] as? String),
                encoding: item["SubEncoding"] as? String,
                fps: frameRate(item)))
        }
        // Stable sort: common languages first, the addon's own order within one.
        return out.enumerated()
            .sorted { (rank($0.element.languageCode), $0.offset) < (rank($1.element.languageCode), $1.offset) }
            .map(\.element)
    }

    /// "fpsMilli": 23976 → 23.976. Zero or missing means unknown.
    private static func frameRate(_ item: [String: Any]) -> Double? {
        let milli = (item["fpsMilli"] as? Int) ?? (item["fpsMilli"] as? String).flatMap(Int.init)
        if let milli, milli > 1000 { return Double(milli) / 1000 }
        if let fps = (item["fps"] as? Double) ?? (item["fps"] as? String).flatMap(Double.init), fps > 1 { return fps }
        return nil
    }

    // MARK: Picking a file

    /// Tracks in `language`, best match first: timed for the same frame rate
    /// (a 25 fps subtitle on a 23.976 fps video drifts further off every
    /// minute), then the closest release name, then the addon's own order.
    static func candidates(in tracks: [SubtitleTrack], language: String, release: String?,
                           videoFPS: Double? = nil) -> [SubtitleTrack] {
        let wanted = SubtitleLanguage.canonical(language)
        let matching = tracks.enumerated().filter { $0.element.languageCode == wanted }
        let releaseTokens = ReleaseName.tokens(release)
        let group = ReleaseName.group(release)
        return matching
            .map { entry -> (track: SubtitleTrack, offset: Int, score: Int) in
                var score = releaseTokens.isEmpty ? 0
                    : ReleaseName.score(ReleaseName.tokens(entry.element.fileName), against: releaseTokens, group: group)
                if let video = videoFPS, let sub = entry.element.fps {
                    score += abs(video - sub) < 0.05 ? 8 : (abs(video - sub) > 0.3 ? -8 : 0)
                }
                return (entry.element, entry.offset, score)
            }
            .sorted { ($0.score, -$0.offset) > ($1.score, -$1.offset) }
            .map(\.track)
    }

    /// Downloads the best subtitle in `language`, moving on to the next
    /// candidate when one is missing or broken.
    func bestFile(for context: SubtitleContext, language: String,
                  tracks: [SubtitleTrack]? = nil, videoFPS: Double? = nil,
                  preferredID: String? = nil) async -> (track: SubtitleTrack, file: URL)? {
        guard !language.isEmpty else { return nil }
        let all: [SubtitleTrack]
        if let tracks { all = tracks } else { all = await subtitles(for: context) }
        var ordered = Self.candidates(in: all, language: language, release: context.releaseName, videoFPS: videoFPS)
        // The file this episode used last time comes first, so a saved sync
        // offset keeps matching it.
        if let preferredID, let index = ordered.firstIndex(where: { $0.id == preferredID }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        for track in ordered.prefix(4) {
            if Task.isCancelled { return nil }
            if let file = try? await download(track) { return (track, file) }
        }
        return nil
    }

    /// Warms the list and the preferred-language file while a stream buffers.
    func prefetch(context: SubtitleContext, preferredLanguage: String, preferredID: String? = nil) async {
        _ = await bestFile(for: context, language: preferredLanguage, preferredID: preferredID)
    }

    // MARK: Files

    func download(_ track: SubtitleTrack) async throws -> URL {
        if let running = inflightFiles[track.id] { return try await running.value }
        let task = Task { try await Self.fetchFile(track) }
        inflightFiles[track.id] = task
        defer { inflightFiles[track.id] = nil }
        return try await task.value
    }

    private static func fetchFile(_ track: SubtitleTrack) async throws -> URL {
        let dir = directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pruneOnce(dir)

        let file = dir.appendingPathComponent(
            "\(track.languageCode)-\(digest(track.id)).\(fileExtension(for: track))")
        if let cached = try? Data(contentsOf: file), looksLikeSubtitles(cached) { return file }
        try? FileManager.default.removeItem(at: file)   // an old broken download

        var lastError: Error = Failure.badResponse
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            do {
                var request = URLRequest(url: track.url)
                request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw Failure.badResponse
                }
                let text = utf8(data, declared: track.encoding, language: track.languageCode)
                guard looksLikeSubtitles(text) else { throw Failure.notSubtitles }
                try text.write(to: file, options: .atomic)
                return file
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The addon normally converts to UTF-8, but not always. Undecodable text
    /// makes VLC show nothing (or garbage), so re-encode from the declared or
    /// most likely code page. Arabic files are usually Windows-1256.
    private static func utf8(_ data: Data, declared: String?, language: String) -> Data {
        if String(data: data, encoding: .utf8) != nil { return data }
        var guesses: [String.Encoding] = []
        if let declared {
            let cf = CFStringConvertIANACharSetNameToEncoding(declared as CFString)
            if cf != kCFStringEncodingInvalidId {
                guesses.append(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
            }
        }
        let codePage: CFStringEncodings? = switch language {
        case "ara", "per": .windowsArabic
        case "heb": .windowsHebrew
        case "rus", "ukr", "bul", "srp", "mac": .windowsCyrillic
        case "gre", "ell": .windowsGreek
        case "tur": .windowsLatin5
        case "pol", "cze", "hun", "hrv", "slv", "rum", "slo": .windowsLatin2
        default: nil
        }
        if let codePage {
            let cf = CFStringEncoding(codePage.rawValue)
            guesses.append(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
        }
        guesses.append(.windowsCP1252)
        for encoding in guesses {
            if let text = String(data: data, encoding: encoding), let converted = text.data(using: .utf8) {
                return converted
            }
        }
        return data
    }

    /// Rejects empty files and HTML error pages served with a 200.
    private static func looksLikeSubtitles(_ data: Data) -> Bool {
        guard data.count > 20 else { return false }
        let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
        return !head.contains("<html") && !head.contains("<!doctype")
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Subtitles", isDirectory: true)
    }

    private static func fileExtension(for track: SubtitleTrack) -> String {
        let known = ["srt", "vtt", "ass", "ssa", "sub"]
        let fromURL = track.url.pathExtension.lowercased()
        if known.contains(fromURL) { return fromURL }
        let fromName = ((track.fileName ?? "") as NSString).pathExtension.lowercased()
        if known.contains(fromName) { return fromName }
        return "srt"
    }

    private static let pruneLock = NSLock()
    nonisolated(unsafe) private static var pruned = false

    private static func pruneOnce(_ dir: URL) {
        pruneLock.lock()
        defer { pruneLock.unlock() }
        guard !pruned else { return }
        pruned = true
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    private static func rank(_ code: String) -> Int {
        SubtitleLanguage.common.firstIndex { $0.code == code } ?? Int.max
    }
}

/// Scores how well a subtitle's file name matches the playing release, so the
/// chosen file is timed for the same cut (BluRay vs WEB, group, resolution).
nonisolated enum ReleaseName {
    private static let noise: Set<String> = ["the", "and", "of", "a", "srt", "sub", "subs", "eng", "english"]

    static func tokens(_ name: String?) -> Set<String> {
        guard let name else { return [] }
        let firstLine = name.split(whereSeparator: \.isNewline).first.map(String.init) ?? name
        let parts = firstLine.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { $0.count > 1 && !noise.contains($0) })
    }

    /// Release group: the part after the last "-" (e.g. "x264-REWARD" → "reward").
    static func group(_ name: String?) -> String? {
        guard let name else { return nil }
        let firstLine = name.split(whereSeparator: \.isNewline).first.map(String.init) ?? name
        guard let dash = firstLine.lastIndex(of: "-") else { return nil }
        let tail = firstLine[firstLine.index(after: dash)...]
            .prefix { $0.isLetter || $0.isNumber }
            .lowercased()
        return tail.count > 1 ? tail : nil
    }

    static func score(_ candidate: Set<String>, against release: Set<String>, group: String?) -> Int {
        var score = candidate.intersection(release).count
        if let group, candidate.contains(group) { score += 5 }
        let sources: [Set<String>] = [["bluray", "bdrip", "brrip", "bdremux", "remux"],
                                      ["web", "webrip", "webdl", "dl", "amzn", "nf", "dsnp", "hmax", "atvp"],
                                      ["hdtv", "pdtv"], ["dvdrip", "dvd"]]
        for family in sources where !family.isDisjoint(with: release) && !family.isDisjoint(with: candidate) {
            score += 3
        }
        return score
    }
}
