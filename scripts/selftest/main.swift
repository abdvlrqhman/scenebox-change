// Checks the subtitle helpers on real bytes (compiled with swiftc in CI):
// zip extraction, timestamp shifting both ways, frame-rate stretching and
// cue parsing. Exits non-zero on the first failure.
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { print("FAIL \(message)"); failures += 1 }
}

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
let work = FileManager.default.temporaryDirectory.appendingPathComponent("sb-selftest-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// Zip: deflated and stored entries, with a folder and a non-subtitle file first.
for name in ["deflated.zip", "stored.zip"] {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    check(ZipReader.isZip(data), "\(name) is recognised as a zip")
    let entry = ZipReader.firstSubtitle(in: data)
    check(entry?.name.hasSuffix(".srt") == true, "\(name) → first subtitle entry found (\(entry?.name ?? "nil"))")
    let text = entry.map { String(decoding: $0.contents, as: UTF8.self) } ?? ""
    check(text.contains("مرحبا") && text.contains("00:00:01,000 --> 00:00:03,500"), "\(name) → contents intact")
}
check(!ZipReader.isZip(Data("1\n00:00:01,000 --> 00:00:02,000\nhi\n".utf8)), "plain SRT is not a zip")

// Retiming SRT: negative offset clamps at zero, positive shifts, commas kept.
func retimed(_ file: String, offset: Int, scale: Double) throws -> String {
    let source = work.appendingPathComponent(file)
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent(file), to: source)
    let out = try SubtitleRetimer.retime(source, offsetMilliseconds: offset, scale: scale)
    try? FileManager.default.removeItem(at: source)
    return try String(contentsOf: out, encoding: .utf8)
}

var srt = try retimed("sample.srt", offset: -1500, scale: 1)
check(srt.contains("00:00:00,000 --> 00:00:02,000"), "SRT −1.5 s: 1.000→0 (clamped), 3.500→2.000")
check(srt.contains("00:01:00,500 --> 00:01:02,500"), "SRT −1.5 s: 62.000→60.500")
check(srt.contains("مرحبا"), "SRT text untouched")

srt = try retimed("sample.srt", offset: 2250, scale: 1)
check(srt.contains("00:00:03,250 --> 00:00:05,750"), "SRT +2.25 s")

srt = try retimed("sample.srt", offset: 0, scale: 25.0 / 23.976)
check(srt.contains("00:01:04,648"), "SRT 25→23.976 fps stretch: 62.000 s → 64.648 s")

let vtt = try retimed("sample.vtt", offset: -500, scale: 1)
check(vtt.hasPrefix("WEBVTT"), "VTT header kept")
check(vtt.contains("00:00:00.500 --> 00:00:03.000 line:90%"), "VTT −0.5 s with cue settings kept")

let ass = try retimed("sample.ass", offset: 1000, scale: 1)
check(ass.contains("Dialogue: 0,0:00:02.00,0:00:04.50,Default,,0,0,0,,مرحبا, كيف الحال"), "ASS +1 s, commas in text kept")

// Cue parsing for translation.
let cues = SubtitleCues.parse(try String(contentsOf: fixtures.appendingPathComponent("sample.vtt"), encoding: .utf8))
check(cues.count == 2, "VTT parsed into 2 cues")
check(cues.first?.start == "00:00:01,000", "VTT time normalised to SRT form")
check(cues.last?.plainText == "Second line", "formatting tags stripped for translation")

let advert = "1\r\n00:00:00,000 --> 00:00:06,000\r\nYou're on the free plan. Unlock every source → store.wyzie.io\r\n\r\n2\r\n00:00:00,130 --> 00:00:05,320\r\nمرحبا\r\n"
let cleaned = SubtitleCues.removingCues(containing: "wyzie", from: advert)
check(!cleaned.contains("free plan") && cleaned.contains("00:00:00,130 --> 00:00:05,320"), "advert cue removed, real cue kept")

// Sentences split across cues are joined for translation, then spread back.
let dialogue = SubtitleCues.parse("""
1
00:00:01,000 --> 00:00:02,000
I think we

2
00:00:02,100 --> 00:00:03,500
should leave now.

3
00:00:03,600 --> 00:00:05,000
Hello.

4
00:00:05,100 --> 00:00:06,000
- Who's there?
- Me.

5
00:00:20,000 --> 00:00:21,000
Later
""")
let units = TranslationUnits.build(dialogue)
check(units.count == 4, "4 translation units (got \(units.count))")
check(units.first?.cues == [0, 1] && units.first?.text == "I think we should leave now.", "split sentence joined")
check(units.count > 2 && units[2].cues == [3], "dialogue cue stands alone")
check(units.last?.cues == [4], "long pause starts a new unit")
let parts = TranslationUnits.split("a b c d e f", weights: [10, 10])
check(parts == ["a b c", "d e f"], "translation spread by length (got \(parts))")
let uneven = TranslationUnits.split("one two three four", weights: [3, 30])
check(uneven.count == 2 && uneven[0] == "one" && uneven[1] == "two three four", "short first piece gets fewer words (got \(uneven))")
check(TranslationUnits.split("كلمة", weights: [5, 5]) == ["كلمة", "كلمة"], "too few words: whole line on each")

// Tracker scrape packets (BEP 15), byte for byte.
let hello = TrackerScrape.connectRequest(transaction: 0x0102_0304)
check([UInt8](hello) == [0x00, 0x00, 0x04, 0x17, 0x27, 0x10, 0x19, 0x80, 0, 0, 0, 0, 1, 2, 3, 4],
      "scrape connect packet")
let accepted = Data([0, 0, 0, 0, 1, 2, 3, 4, 0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44])
check(TrackerScrape.parseConnect(accepted, transaction: 0x0102_0304) == 0xAABB_CCDD_1122_3344, "connect answer → connection id")
check(TrackerScrape.parseConnect(accepted, transaction: 9) == nil, "connect answer for another request is ignored")
let hashA = Data(repeating: 0xA1, count: 20), hashB = Data(repeating: 0xB2, count: 20)
let ask = TrackerScrape.scrapeRequest(connectionID: 0xAABB_CCDD_1122_3344, transaction: 7, hashes: [hashA, hashB])
check(ask.count == 16 + 40 && [UInt8](ask)[8..<16] == [0, 0, 0, 2, 0, 0, 0, 7], "scrape request layout")
var answer = Data([0, 0, 0, 2, 0, 0, 0, 7])
answer += Data([0, 0, 1, 44, 0, 0, 0, 9, 0, 0, 0, 30])     // 300 seeding, 9 done, 30 downloading
answer += Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
let swarms = TrackerScrape.parseScrape(answer, transaction: 7, count: 2)
check(swarms?.first == TrackerScrape.Swarm(seeders: 300, leechers: 30, completed: 9), "scrape answer parsed (got \(String(describing: swarms?.first)))")
check(swarms?.last?.seeders == 0 && swarms?.last?.leechers == 1, "second torrent parsed")
check(TrackerScrape.parseScrape(Data([0, 0, 0, 3, 0, 0, 0, 7]) + Data("denied".utf8), transaction: 7, count: 2) == nil,
      "tracker error answer → nil")
check(TrackerScrape.Endpoint(URL(string: "udp://tracker.opentrackr.org:1337/announce")!)?.port == 1337, "udp tracker URL → endpoint")
check(TrackerScrape.Endpoint(URL(string: "http://tracker.opentrackr.org:1337/announce")!) == nil, "http tracker isn't scraped over UDP")

// Live: a well-seeded torrent on real trackers. Informational only, since CI
// networks may block UDP.
let liveHash = Data((0..<20).map { i -> UInt8 in
    let hex = Array("6bbad06245a0d631b0a5e47c8cd6e5abc9a70211")
    return UInt8(String(hex[i * 2...i * 2 + 1]), radix: 16)!
})
let liveTrackers = ["udp://tracker.opentrackr.org:1337/announce", "udp://open.stealth.si:80/announce",
                    "udp://tracker.torrent.eu.org:451/announce"].compactMap { URL(string: $0).flatMap(TrackerScrape.Endpoint.init) }
let started = Date()
if let live = await TrackerScrape.scrape([liveHash], trackers: liveTrackers), let swarm = live[liveHash] {
    print("info live scrape: \(swarm.seeders) seeding, \(swarm.leechers) downloading, \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    check(swarm.seeders + swarm.leechers > 0, "live scrape sees the swarm")
} else {
    print("info live scrape: no tracker answered (UDP blocked here?)")
}

// Source ranking.
func assess(_ facts: SourceRanking.Facts, runtime: Double = 45) -> SourceRanking.Assessment {
    SourceRanking.assess(facts, preferredResolution: "1080p", runtimeMinutes: runtime, debridEnabled: false)
}
let gb: Int64 = 1_073_741_824
let good1080 = assess(.init(listedSeeders: 40, liveSeeders: 60, liveLeechers: 10, resolution: "1080p", sizeBytes: 2 * gb))
let huge720 = assess(.init(listedSeeders: 900, liveSeeders: 500, liveLeechers: 50, resolution: "720p", sizeBytes: gb))
let weak1080 = assess(.init(listedSeeders: 120, liveSeeders: 2, liveLeechers: 0, resolution: "1080p", sizeBytes: 2 * gb))
let dead = assess(.init(listedSeeders: 979, liveSeeders: 0, liveLeechers: 0, resolution: "1080p", sizeBytes: 2 * gb))
let remux = assess(.init(listedSeeders: 300, liveSeeders: 300, liveLeechers: 20, resolution: "1080p", sizeBytes: 60 * gb), runtime: 120)
let movie1080 = assess(.init(listedSeeders: 100, liveSeeders: 100, liveLeechers: 5, resolution: "1080p", sizeBytes: 3 * gb), runtime: 120)
check(good1080.score > huge720.score, "healthy 1080p beats a bigger 720p swarm")
check(huge720.score > weak1080.score, "a big 720p swarm beats a near-dead 1080p")
check(dead.health == .dead && dead.score < weak1080.score && !dead.isPlayable, "listed 979 but 0 live → dead, last")
check(remux.isHeavy && movie1080.score > remux.score, "60 GB remux ranks below a 3 GB 1080p (\(Int(remux.megabitsPerSecond ?? 0)) Mb/s)")
let failed = assess(.init(listedSeeders: 40, liveSeeders: 60, liveLeechers: 10, resolution: "1080p", sizeBytes: 2 * gb, failedBefore: true))
check(failed.score < huge720.score, "a source that didn't start sinks")
let unknown = assess(.init(listedSeeders: 50, resolution: "1080p", sizeBytes: 2 * gb))
check(unknown.health == .unknown && unknown.isPlayable, "no live answer → unknown, still playable")
check(SourceRanking.sizeBytes("1.4 GB") == Int64(1.4 * 1_073_741_824) && SourceRanking.sizeBytes("700 MB") == 700 * 1_048_576,
      "size text parsed")
check(SourceRanking.runtimeMinutes("2h 10min", isSeries: false) == 130 && SourceRanking.runtimeMinutes("58 min", isSeries: true) == 58
      && SourceRanking.runtimeMinutes(nil, isSeries: true) == 45, "runtime text parsed")

// Casting: finding TVs, their description, commands, and the server.
let ssdpAnswer = Data("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.50:9197/dmr\r\nSERVER: SHP, UPnP/1.0, Samsung UPnP SDK/1.0\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n".utf8)
check(SSDP.parseResponse(ssdpAnswer)?.location.absoluteString == "http://192.168.1.50:9197/dmr", "SSDP answer → description address")
check(SSDP.parseResponse(Data("NOTIFY * HTTP/1.1\r\nLOCATION: http://x/\r\n\r\n".utf8)) == nil, "SSDP notify isn't a search answer")
let search = String(decoding: SSDP.searchMessage(host: "192.168.1.50"), as: UTF8.self)
check(search.hasPrefix("M-SEARCH * HTTP/1.1\r\n") && search.contains("HOST: 192.168.1.50:1900") && search.hasSuffix("\r\n\r\n"),
      "direct M-SEARCH layout")

let samsungXML = """
<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:sec="http://www.sec.co.kr/dlna">
<specVersion><major>1</major><minor>0</minor></specVersion>
<device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>[TV] Samsung 5 Series (43)</friendlyName><manufacturer>Samsung Electronics</manufacturer>
<modelName>UE43T5300</modelName><UDN>uuid:0bd1f3a4-1234</UDN>
<serviceList>
<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>/upnp/control/RenderingControl1</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><controlURL>/upnp/control/ConnectionManager1</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/upnp/control/AVTransport1</controlURL></service>
</serviceList></device></root>
"""
let samsung = UPnPDescription.parse(Data(samsungXML.utf8), location: URL(string: "http://192.168.1.50:9197/dmr")!)
check(samsung?.name == "[TV] Samsung 5 Series (43)" && samsung?.avTransport.absoluteString == "http://192.168.1.50:9197/upnp/control/AVTransport1",
      "Samsung description → AVTransport address (got \(samsung?.avTransport.absoluteString ?? "nil"))")
check(samsung?.renderingControl?.absoluteString == "http://192.168.1.50:9197/upnp/control/RenderingControl1" && samsung?.isComputer == false,
      "Samsung rendering control; not a computer")
let kodiXML = """
<root xmlns="urn:schemas-upnp-org:device-1-0"><URLBase>http://192.168.1.60:1186/</URLBase>
<device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType><friendlyName>Kodi (server)</friendlyName><UDN>uuid:server</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType><controlURL>cd/control</controlURL></service></serviceList>
<deviceList><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType><friendlyName>Kodi (LAPTOP)</friendlyName>
<manufacturer>XBMC Foundation</manufacturer><modelName>Kodi</modelName><UDN>uuid:renderer</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>AVTransport/control.xml</controlURL></service></serviceList>
</device></deviceList></device></root>
"""
let kodi = UPnPDescription.parse(Data(kodiXML.utf8), location: URL(string: "http://192.168.1.60:1186/desc.xml")!)
check(kodi?.name == "Kodi (LAPTOP)" && kodi?.avTransport.absoluteString == "http://192.168.1.60:1186/AVTransport/control.xml" && kodi?.isComputer == true,
      "nested Kodi renderer with URLBase (got \(kodi?.avTransport.absoluteString ?? "nil"))")

let didl = DLNA.didl(title: "Breaking Bad · S1E1", videoURL: URL(string: "http://192.168.1.5:5000/abcde/video.mkv")!,
                     mimeType: "video/x-matroska", size: 1_234, durationSeconds: 3_487,
                     subtitleURL: URL(string: "http://192.168.1.5:5000/abcde/subtitles.srt")!)
check(didl.contains("sec:CaptionInfoEx sec:type=\"srt\">http://192.168.1.5:5000/abcde/subtitles.srt<")
      && didl.contains("http-get:*:text/srt:*") && didl.contains("pv:subtitleFileUri=")
      && didl.contains("duration=\"0:58:07.000\"") && didl.contains("<dc:title>Breaking Bad · S1E1.</dc:title>"),
      "DIDL carries the subtitles for Samsung, LG and Kodi")
let envelope = String(decoding: DLNA.soapEnvelope(action: "SetAVTransportURI", arguments: [("InstanceID", "0"), ("CurrentURIMetaData", didl)]), as: UTF8.self)
check(envelope.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">")
      && envelope.contains("&lt;DIDL-Lite") && !envelope.contains("<DIDL-Lite"), "SOAP envelope escapes the metadata")
check(DLNA.timeString(3725) == "1:02:05" && DLNA.parseTime("01:02:05.500") == 3725.5 && DLNA.parseTime("NOT_IMPLEMENTED") == nil,
      "DLNA time strings")
let positionAnswer = "<s:Envelope><s:Body><u:GetPositionInfoResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><Track>1</Track><TrackDuration>0:44:10</TrackDuration><RelTime>0:12:34</RelTime></u:GetPositionInfoResponse></s:Body></s:Envelope>"
check(DLNA.value(of: "RelTime", in: positionAnswer).flatMap(DLNA.parseTime) == 754, "position read from the TV's answer")
check(DLNA.fault(in: "<s:Fault><detail><UPnPError><errorCode>714</errorCode><errorDescription>Illegal MIME-type</errorDescription></UPnPError></detail></s:Fault>") == "Illegal MIME-type",
      "SOAP fault text")
let neighbours = LocalNetwork.neighbours(of: "192.168.1.37", prefixLength: 24)
check(neighbours.count == 253 && !neighbours.contains("192.168.1.37") && neighbours.first == "192.168.1.1" && neighbours.last == "192.168.1.254",
      "the /24 around the phone")
check(LocalNetwork.neighbours(of: "10.0.5.9", prefixLength: 16).count == 253, "big networks: just our /24")
check(CastServer.parseRange("bytes=10-19", length: 100)! == (10, 19) && CastServer.parseRange("bytes=90-", length: 100)! == (90, 99)
      && CastServer.parseRange("bytes=-5", length: 100)! == (95, 99) && CastServer.parseRange("bytes=100-", length: 100) == nil,
      "HTTP ranges")

let assFile = work.appendingPathComponent("cast.ass")
try "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\\i1}مرحبا{\\i0}\\Nيا صديقي, كيف\n".write(to: assFile, atomically: true, encoding: .utf8)
let castSubs = CastSubtitles.make(from: assFile)
let castSRT = castSubs.map { String(decoding: $0.srt, as: UTF8.self) } ?? ""
check(castSubs?.srt.prefix(3) == Data([0xEF, 0xBB, 0xBF]) && castSRT.contains("00:00:01,500 --> 00:00:03,000\r\nمرحبا\r\nيا صديقي, كيف"),
      "ASS → SRT for TVs, with the UTF-8 mark and CRLF")
check(castSubs.map { String(decoding: $0.vtt, as: UTF8.self) }?.contains("WEBVTT\n\n00:00:01.500 --> 00:00:03.000") == true, "and WebVTT for browsers")

// The server itself, on this machine: a file source, then a relay through a second server.
let videoFile = work.appendingPathComponent("video.mkv")
let videoBytes = Data((0..<300_000).map { UInt8($0 % 251) })
try videoBytes.write(to: videoFile)
let fileServer = CastServer()
do {
try await fileServer.start(host: "127.0.0.1")
await fileServer.update(.init(source: .file(videoFile), fileExtension: "mkv", title: "Test & Co", subtitles: castSubs))
if let url = await fileServer.videoURL {
    var request = URLRequest(url: url)
    request.setValue("bytes=1000-1999", forHTTPHeaderField: "Range")
    let (body, response) = try await URLSession.shared.data(for: request)
    let http = response as? HTTPURLResponse
    check(http?.statusCode == 206 && body == videoBytes[1000..<2000], "cast server: range from the file")
    check(http?.value(forHTTPHeaderField: "contentFeatures.dlna.org") == DLNA.contentFeatures
          && http?.value(forHTTPHeaderField: "CaptionInfo.sec")?.hasSuffix("/subtitles.srt") == true
          && http?.value(forHTTPHeaderField: "Content-Type") == "video/x-matroska", "cast server: DLNA and caption headers")
    let base = await fileServer.baseURL!
    let (page, _) = try await URLSession.shared.data(from: base)
    check(String(decoding: page, as: UTF8.self).contains("Test &amp; Co") && String(decoding: page, as: UTF8.self).contains("subtitles.vtt"),
          "cast server: page for computers")
    let (srtBody, _) = try await URLSession.shared.data(from: base.appendingPathComponent("subtitles.srt"))
    check(srtBody == castSubs?.srt, "cast server: subtitles")
    let port = await fileServer.port
    var wrong = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/nope/video.mkv")!)
    wrong.timeoutInterval = 5
    let (_, refused) = try await URLSession.shared.data(for: wrong)
    check((refused as? HTTPURLResponse)?.statusCode == 404, "cast server: wrong code refused")

    let relayServer = CastServer()
    try await relayServer.start(host: "127.0.0.1")
    await relayServer.update(.init(source: .upstream(url), fileExtension: "mkv", title: "Relay", subtitles: nil))
    if let relayed = await relayServer.videoURL {
        var ranged = URLRequest(url: relayed)
        ranged.setValue("bytes=250000-", forHTTPHeaderField: "Range")
        let (tail, tailResponse) = try await URLSession.shared.data(for: ranged)
        check((tailResponse as? HTTPURLResponse)?.statusCode == 206 && tail == videoBytes[250_000...],
              "cast server: relays the stream with ranges (\(tail.count) bytes)")
        let (whole, _) = try await URLSession.shared.data(from: relayed)
        check(whole == videoBytes, "cast server: relays the whole stream")
    }
    await relayServer.stop()
}
} catch {
    check(false, "cast server test threw: \(error)")
}
await fileServer.stop()

try? FileManager.default.removeItem(at: work)
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
