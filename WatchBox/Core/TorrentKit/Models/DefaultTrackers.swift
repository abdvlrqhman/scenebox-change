//
//  DefaultTrackers.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

/// Trackers added to every torrent, so peers are found even when a source
/// lists few or dead ones. Public trackers come and go, so the list is also
/// refreshed daily from the community-maintained "best" list.
nonisolated public enum DefaultTrackers {
    /// Checked answering in September 2026. The HTTP ones still work on
    /// networks that block UDP, where every UDP tracker and the DHT go quiet.
    public static let list: [URL] = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.stealth.si:80/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://tracker.qu.ax:6969/announce",
        "udp://tracker-udp.gbitt.info:80/announce",
        "udp://tracker.dler.org:6969/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://explodie.org:6969/announce",
        "udp://tracker.tryhackx.org:6969/announce",
        "udp://tracker2.dler.org:80/announce",
        "http://tracker.opentrackr.org:1337/announce",
        "http://tracker.dler.com:6969/announce",
        "http://tracker.renfei.net:8080/announce",
    ].compactMap(URL.init(string:))

    /// Scrape answers come from these first: the largest public trackers.
    static let scrapeFirst: [String] = [
        "tracker.opentrackr.org", "open.stealth.si", "tracker.torrent.eu.org",
        "open.demonii.com", "tracker.qu.ax", "tracker-udp.gbitt.info",
    ]

    private static let refreshedList = "SBTrackerList"
    private static let refreshedAt = "SBTrackerListDate"
    /// github.com/ngosang/trackerslist, tried directly and through a mirror.
    private static let sources = [
        "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt",
        "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best.txt",
    ].compactMap(URL.init(string:))

    /// The refreshed list (when there is one) plus the built-in one.
    public static var current: [URL] {
        let fetched = (UserDefaults.standard.stringArray(forKey: refreshedList) ?? [])
            .compactMap(URL.init(string:))
        var seen = Set<String>()
        return (fetched + list).filter { seen.insert($0.absoluteString.lowercased()).inserted }
    }

    /// UDP trackers to scrape, the biggest first.
    static var scrapeEndpoints: [TrackerScrape.Endpoint] {
        let endpoints = current.compactMap(TrackerScrape.Endpoint.init)
        let first = endpoints.filter { scrapeFirst.contains($0.host) }
        let rest = endpoints.filter { !scrapeFirst.contains($0.host) }
        var seen = Set<String>()
        return Array((first + rest).filter { seen.insert($0.host).inserted }.prefix(8))
    }

    /// Fetches the community list at most once a day. A failure keeps what
    /// was there.
    public static func refreshIfStale() async {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: refreshedAt) as? Date,
           Date().timeIntervalSince(last) < 24 * 3600 { return }
        var text: String?
        for source in sources where text == nil {
            var request = URLRequest(url: source)
            request.timeoutInterval = 10
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                text = String(data: data, encoding: .utf8)
            }
        }
        guard let text else { return }
        let trackers = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard let url = URL(string: line), let scheme = url.scheme?.lowercased(),
                      url.host?.isEmpty == false else { return false }
                return ["udp", "http", "https"].contains(scheme)
            }
            .prefix(30)
        guard trackers.count >= 5 else { return }
        defaults.set(Array(trackers), forKey: refreshedList)
        defaults.set(Date(), forKey: refreshedAt)
    }
}
