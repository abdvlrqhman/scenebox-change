//
//  SubtitleSources.swift
//  SceneBox
//

import Foundation

/// Where subtitles come from. Every source returns the same `SubtitleTrack`,
/// and the provider merges them, so one weak catalogue (OpenSubtitles has very
/// few Arabic entries for most episodes) no longer decides what's available.
nonisolated protocol SubtitleSource: Sendable {
    /// Shown on the version row.
    var name: String { get }
    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack]
}

/// Keys the viewer entered (or that shipped with the build).
nonisolated struct SubtitleKeys: Sendable, Equatable {
    var wyzie = ""
    var subdl = ""
    var subsource = ""

    @MainActor
    static var current: SubtitleKeys {
        let settings = AppSettings.shared
        return SubtitleKeys(wyzie: settings.wyzieAPIKey,
                            subdl: settings.subdlAPIKey,
                            subsource: settings.subsourceAPIKey)
    }

    var sources: [SubtitleSource] {
        var list: [SubtitleSource] = [StremioSubtitleSource()]
        if !wyzie.isEmpty { list.append(WyzieSubtitleSource(key: wyzie)) }
        if !subdl.isEmpty { list.append(SubDLSubtitleSource(key: subdl)) }
        if !subsource.isEmpty { list.append(SubSourceSubtitleSource(key: subsource)) }
        return list
    }
}

// MARK: - Shared helpers

nonisolated enum SubtitleFetch {
    static func json(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 12,
                     attempts: Int = 2) async -> Any? {
        for attempt in 0..<attempts {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            if Task.isCancelled { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue(TorrentSearch.userAgent, forHTTPHeaderField: "User-Agent")
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            return json
        }
        return nil
    }

    /// "tt0903747:1:3" for an episode, "tt1375666" for a film.
    static func stremioID(_ context: SubtitleContext) -> String {
        guard context.type == .series || context.type == .anime,
              let season = context.season, let episode = context.episode else { return context.imdbID }
        return "\(context.imdbID):\(season):\(episode)"
    }
}

// MARK: - Stremio addon (OpenSubtitles v3)

nonisolated struct StremioSubtitleSource: SubtitleSource {
    var base = "https://opensubtitles-v3.strem.io"
    var name: String { "OpenSubtitles" }

    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack] {
        let type = context.type == .movie ? "movie" : "series"
        guard let url = URL(string: "\(base)/subtitles/\(type)/\(SubtitleFetch.stremioID(context)).json"),
              let json = await SubtitleFetch.json(url) as? [String: Any],
              let raw = json["subtitles"] as? [[String: Any]] else { return [] }

        return raw.compactMap { item in
            guard let urlString = item["url"] as? String, let url = URL(string: urlString),
                  let lang = item["lang"] as? String else { return nil }
            return SubtitleTrack(
                id: (item["id"] as? String) ?? urlString,      // unprefixed: saved choices keep matching
                languageCode: SubtitleLanguage.canonical(lang),
                url: url,
                fileName: (item["subtitleFileName"] as? String) ?? (item["movieReleaseName"] as? String),
                encoding: item["SubEncoding"] as? String,
                fps: frameRate(item),
                provider: name)
        }
    }

    private func frameRate(_ item: [String: Any]) -> Double? {
        let milli = (item["fpsMilli"] as? Int) ?? (item["fpsMilli"] as? String).flatMap(Int.init)
        if let milli, milli > 1000 { return Double(milli) / 1000 }
        if let fps = (item["fps"] as? Double) ?? (item["fps"] as? String).flatMap(Double.init), fps > 1 { return fps }
        return nil
    }
}

// MARK: - Wyzie (aggregates several catalogues, always UTF-8)

nonisolated struct WyzieSubtitleSource: SubtitleSource {
    let key: String
    var name: String { "Wyzie" }

    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack] {
        var components = URLComponents(string: "https://sub.wyzie.io/search")
        var items = [URLQueryItem(name: "id", value: context.imdbID),
                     URLQueryItem(name: "key", value: key),
                     URLQueryItem(name: "encoding", value: "UTF-8"),
                     URLQueryItem(name: "format", value: "srt")]
        if let season = context.season, let episode = context.episode {
            items.append(URLQueryItem(name: "season", value: String(season)))
            items.append(URLQueryItem(name: "episode", value: String(episode)))
        }
        components?.queryItems = items
        guard let url = components?.url,
              let raw = await SubtitleFetch.json(url) as? [[String: Any]] else { return [] }

        return raw.compactMap { item in
            guard let urlString = item["url"] as? String, let url = URL(string: urlString),
                  let lang = item["language"] as? String else { return nil }
            let id = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? urlString
            return SubtitleTrack(
                id: "wz-" + id,
                languageCode: SubtitleLanguage.canonical(lang),
                url: url,
                fileName: (item["release"] as? String) ?? (item["fileName"] as? String) ?? (item["media"] as? String),
                encoding: item["encoding"] as? String,
                provider: name,
                downloads: (item["downloadCount"] as? Int) ?? 0,
                isHearingImpaired: (item["isHearingImpaired"] as? Bool) ?? false,
                isMachineTranslated: (item["ai"] as? Bool) ?? false)
        }
    }
}

// MARK: - SubDL (needs a free key; serves zipped subtitles)

nonisolated struct SubDLSubtitleSource: SubtitleSource {
    let key: String
    var name: String { "SubDL" }

    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack] {
        var components = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")
        var items = [URLQueryItem(name: "api_key", value: key),
                     URLQueryItem(name: "imdb_id", value: context.imdbID),
                     URLQueryItem(name: "subs_per_page", value: "30")]
        if let season = context.season, let episode = context.episode {
            items.append(URLQueryItem(name: "season_number", value: String(season)))
            items.append(URLQueryItem(name: "episode_number", value: String(episode)))
            items.append(URLQueryItem(name: "type", value: "tv"))
        } else {
            items.append(URLQueryItem(name: "type", value: "movie"))
        }
        components?.queryItems = items
        guard let url = components?.url,
              let json = await SubtitleFetch.json(url) as? [String: Any],
              let raw = json["subtitles"] as? [[String: Any]] else { return [] }

        return raw.compactMap { item in
            guard let path = item["url"] as? String else { return nil }
            // A season pack's zip starts with episode 1, whatever was asked for.
            if context.episode != nil, (item["full_season"] as? Bool) == true { return nil }
            let absolute = path.hasPrefix("http") ? path : "https://dl.subdl.com" + path
            guard let url = URL(string: absolute) else { return nil }
            let language = (item["lang"] as? String) ?? (item["language"] as? String) ?? ""
            return SubtitleTrack(
                id: "sd-" + absolute,
                languageCode: SubtitleLanguage.canonical(language),
                url: url,
                fileName: (item["release_name"] as? String) ?? (item["name"] as? String),
                provider: name,
                isHearingImpaired: (item["hi"] as? Bool) ?? false)
        }
    }
}

// MARK: - SubSource (needs a free key; serves zipped subtitles)

nonisolated struct SubSourceSubtitleSource: SubtitleSource {
    let key: String
    var name: String { "SubSource" }
    private var headers: [String: String] { ["X-API-Key": key, "Accept": "application/json"] }

    func subtitles(for context: SubtitleContext) async -> [SubtitleTrack] {
        var components = URLComponents(string: "https://api.subsource.net/api/v1/subtitles")
        var items = [URLQueryItem(name: "imdb_id", value: context.imdbID),
                     URLQueryItem(name: "per_page", value: "30")]
        if let season = context.season, let episode = context.episode {
            items.append(URLQueryItem(name: "season", value: String(season)))
            items.append(URLQueryItem(name: "episode", value: String(episode)))
        }
        components?.queryItems = items
        guard let url = components?.url,
              let json = await SubtitleFetch.json(url, headers: headers) else { return [] }
        // The shape isn't documented in full; accept the usual wrappers.
        let raw: [[String: Any]]
        if let list = json as? [[String: Any]] {
            raw = list
        } else if let object = json as? [String: Any] {
            raw = (object["subtitles"] as? [[String: Any]]) ?? (object["data"] as? [[String: Any]])
                ?? (object["results"] as? [[String: Any]]) ?? []
        } else {
            raw = []
        }

        return raw.compactMap { item in
            let id = (item["id"] as? Int).map(String.init) ?? (item["id"] as? String)
            guard let id else { return nil }
            let language = (item["language"] as? String) ?? (item["lang"] as? String)
                ?? ((item["language"] as? [String: Any])?["code"] as? String) ?? ""
            let download = (item["download_url"] as? String)
                ?? "https://api.subsource.net/api/v1/subtitles/\(id)/download"
            guard let url = URL(string: download) else { return nil }
            return SubtitleTrack(
                id: "ss-" + id,
                languageCode: SubtitleLanguage.canonical(language),
                url: url,
                fileName: (item["release_info"] as? String) ?? (item["release"] as? String)
                    ?? (item["name"] as? String),
                provider: name,
                downloads: (item["downloads"] as? Int) ?? (item["download_count"] as? Int) ?? 0,
                isHearingImpaired: (item["hearing_impaired"] as? Bool) ?? (item["hi"] as? Bool) ?? false,
                requestHeaders: headers)
        }
    }
}

// MARK: - Key check

/// Tries a key once against its service, for the Save button in Settings.
nonisolated enum SubtitleKeyCheck {
    enum Provider: Hashable, Sendable {
        case wyzie, subdl, subsource

        var title: String {
            switch self {
            case .wyzie: "Wyzie"
            case .subdl: "SubDL"
            case .subsource: "SubSource"
            }
        }
    }

    enum Result: Sendable {
        case works, rejected, unreachable
    }

    static func check(_ provider: Provider, key: String) async -> Result {
        var request: URLRequest
        switch provider {
        case .wyzie:
            var components = URLComponents(string: "https://sub.wyzie.io/search")
            components?.queryItems = [URLQueryItem(name: "id", value: "tt1375666"),
                                      URLQueryItem(name: "key", value: key)]
            guard let url = components?.url else { return .unreachable }
            request = URLRequest(url: url)
        case .subdl:
            var components = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")
            components?.queryItems = [URLQueryItem(name: "api_key", value: key),
                                      URLQueryItem(name: "imdb_id", value: "tt1375666"),
                                      URLQueryItem(name: "type", value: "movie")]
            guard let url = components?.url else { return .unreachable }
            request = URLRequest(url: url)
        case .subsource:
            var components = URLComponents(string: "https://api.subsource.net/api/v1/movies/search")
            components?.queryItems = [URLQueryItem(name: "query", value: "inception")]
            guard let url = components?.url else { return .unreachable }
            request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        request.timeoutInterval = 15
        request.setValue(TorrentSearch.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .unreachable }
        if status == 401 || status == 403 { return .rejected }
        if provider == .subdl,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["status"] as? Bool) == false {
            return .rejected                       // SubDL answers 200 with status:false
        }
        return (200..<500).contains(status) ? .works : .unreachable
    }
}
