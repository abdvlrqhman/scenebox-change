//
//  CastServer.swift
//  SceneBox
//

import Foundation
import Network

/// Subtitles in the forms TVs and browsers read: SRT with a UTF-8 mark (some
/// Samsung TVs need it for Arabic) and WebVTT. The sync chosen in the player is
/// already written into the file it's made from.
nonisolated enum CastSubtitles {
    static func make(from file: URL) -> (srt: Data, vtt: Data)? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let ext = file.pathExtension.lowercased()
        let cues = ["ass", "ssa"].contains(ext) ? parseASS(text) : SubtitleCues.parse(text)
        guard !cues.isEmpty else { return nil }
        let clean = cues.map { SubtitleCue(start: $0.start, end: $0.end, text: $0.plainText) }
            .filter { !$0.text.isEmpty }
        let srt = SubtitleCues.srt(clean).replacingOccurrences(of: "\n", with: "\r\n")
        let vtt = "WEBVTT\n\n" + clean.map { cue in
            "\(vttTime(cue.startMilliseconds)) --> \(vttTime(cue.endMilliseconds))\n\(cue.text)\n"
        }.joined(separator: "\n")
        return (Data([0xEF, 0xBB, 0xBF]) + Data(srt.utf8), Data(vtt.utf8))
    }

    /// ASS/SSA "Dialogue:" lines → cues, styling dropped.
    static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("Dialogue:") {
            let fields = line.dropFirst("Dialogue:".count).split(separator: ",", maxSplits: 9,
                                                                 omittingEmptySubsequences: false)
            guard fields.count == 10, let start = assTime(String(fields[1])),
                  let end = assTime(String(fields[2])) else { continue }
            let body = String(fields[9])
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(SubtitleCue(start: srtTime(start), end: srtTime(end), text: body))
        }
        return cues.sorted { $0.startMilliseconds < $1.startMilliseconds }
    }

    /// "0:01:02.34" → milliseconds.
    private static func assTime(_ raw: String) -> Int? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 3, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return (hours * 3600 + minutes * 60) * 1000 + Int((seconds * 1000).rounded())
    }

    private static func srtTime(_ ms: Int) -> String {
        String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    private static func vttTime(_ ms: Int) -> String {
        String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}

/// Serves what's playing to TVs and computers on the same Wi-Fi, only while
/// casting: the video (from the torrent stream or the file on disk), its
/// subtitles, a VLC playlist and a small page for computers. Every address
/// carries a random code, so nothing else on the network can be fetched.
actor CastServer {
    enum Source: Sendable {
        case upstream(URL)      // the local torrent stream, http://127.0.0.1:…
        case file(URL)
        case remote(URL)        // a debrid link, fetched directly
    }

    struct Content: Sendable {
        var source: Source
        var fileExtension: String
        var title: String
        var subtitles: (srt: Data, vtt: Data)?
    }

    let code: String = {
        let letters = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<5).map { _ in letters.randomElement()! })
    }()

    private var listener: NWListener?
    private var acceptTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "watchbox.cast.http")
    private var content: Content?
    private var onVideoRequest: (@Sendable () -> Void)?
    private(set) var host = ""
    private(set) var port: UInt16 = 0

    // MARK: Addresses

    var baseURL: URL? { port == 0 ? nil : URL(string: "http://\(host):\(port)/\(code)/") }
    var videoURL: URL? {
        guard let content else { return nil }
        if case .remote(let url) = content.source { return url }
        return baseURL?.appendingPathComponent("video.\(content.fileExtension)")
    }
    var subtitleURL: URL? { content?.subtitles == nil ? nil : baseURL?.appendingPathComponent("subtitles.srt") }
    var videoMimeType: String { Self.mimeType(content?.fileExtension ?? "") }

    // MARK: Lifetime

    /// Listens on every interface (TVs reach it at `host`, the phone's Wi-Fi
    /// address); a free port is picked.
    func start(host: String) async throws {
        self.host = host
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let incoming = AsyncStream<NWConnection> { continuation in
            listener.newConnectionHandler = { continuation.yield($0) }
            continuation.onTermination = { _ in listener.cancel() }
        }
        let ready: Bool = await withCheckedContinuation { continuation in
            let gate = CastOnce(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.resume(true)
                case .failed, .cancelled: gate.resume(false)
                default: break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 4) { gate.resume(false) }
        }
        guard ready, let port = listener.port?.rawValue else {
            listener.cancel()
            throw CastError.noNetwork
        }
        self.listener = listener
        self.port = port
        acceptTask = Task { await self.acceptLoop(incoming) }
    }

    private func acceptLoop(_ incoming: AsyncStream<NWConnection>) async {
        await withDiscardingTaskGroup { group in
            for await connection in incoming {
                group.addTask { await self.serve(connection) }
            }
        }
    }

    func update(_ content: Content) { self.content = content }

    /// Told whenever something starts fetching the video (a TV or a computer).
    func setOnVideoRequest(_ handler: @escaping @Sendable () -> Void) { onVideoRequest = handler }

    func stop() {
        acceptTask?.cancel()
        acceptTask = nil
        listener?.cancel()
        listener = nil
        port = 0
        content = nil
    }

    // MARK: Requests

    private func serve(_ connection: NWConnection) async {
        defer { connection.cancel() }
        do {
            try await NetworkIO.start(connection, on: queue)
            let request = try await Self.readHead(connection)
            let lines = request.components(separatedBy: "\r\n")
            let parts = (lines.first ?? "").components(separatedBy: " ")
            let method = parts.first ?? "GET"
            let path = parts.count > 1 ? String(parts[1].prefix { $0 != "?" }) : ""
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
            }
            let prefix = "/\(code)"
            guard let content, path == prefix || path.hasPrefix(prefix + "/") else {
                try await Self.sendHead(connection, "404 Not Found", ["Content-Length": "0"])
                return
            }
            let route = String(path.dropFirst(prefix.count))
            switch route {
            case "", "/":
                try await Self.sendBody(connection, method: method, type: "text/html; charset=utf-8",
                                        data: Data(page(for: content).utf8))
            case "/play.m3u":
                try await Self.sendBody(connection, method: method, type: "audio/x-mpegurl",
                                        data: Data(playlist(for: content).utf8),
                                        extra: ["Content-Disposition": "attachment; filename=\"SceneBox.m3u\""])
            case "/subtitles.srt":
                guard let subtitles = content.subtitles else { throw NetworkIO.Failure.closed }
                try await Self.sendBody(connection, method: method, type: "text/srt; charset=utf-8",
                                        data: subtitles.srt,
                                        extra: ["transferMode.dlna.org": "Interactive"])
            case "/subtitles.vtt":
                guard let subtitles = content.subtitles else { throw NetworkIO.Failure.closed }
                try await Self.sendBody(connection, method: method, type: "text/vtt; charset=utf-8",
                                        data: subtitles.vtt)
            case "/video.\(content.fileExtension)":
                if method == "GET" { onVideoRequest?() }
                var extra: [String: String] = [
                    "transferMode.dlna.org": "Streaming",
                    "contentFeatures.dlna.org": DLNA.contentFeatures,
                ]
                if let subtitleURL { extra["CaptionInfo.sec"] = subtitleURL.absoluteString }
                let type = Self.mimeType(content.fileExtension)
                switch content.source {
                case .file(let file):
                    try await Self.sendFile(connection, method: method, file: file, type: type,
                                            range: headers["range"], extra: extra)
                case .upstream(let url):
                    try await Self.relay(connection, method: method, from: url, type: type,
                                         range: headers["range"], extra: extra, queue: queue)
                case .remote(let url):
                    try await Self.sendHead(connection, "302 Found",
                                            ["Location": url.absoluteString, "Content-Length": "0"])
                }
            default:
                try await Self.sendHead(connection, "404 Not Found", ["Content-Length": "0"])
            }
        } catch {
        }
    }

    // MARK: Video

    /// Serves the file on disk, honouring ranges (TVs seek with them).
    private nonisolated static func sendFile(_ connection: NWConnection, method: String, file: URL,
                                             type: String, range: String?, extra: [String: String]) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let length = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard length > 0 else { throw NetworkIO.Failure.closed }
        var start: Int64 = 0, end = length - 1
        if let range, let parsed = parseRange(range, length: length) { (start, end) = parsed }
        var headers = extra
        headers["Content-Type"] = type
        headers["Accept-Ranges"] = "bytes"
        headers["Content-Length"] = "\(end - start + 1)"
        if range != nil { headers["Content-Range"] = "bytes \(start)-\(end)/\(length)" }
        try await sendHead(connection, range != nil ? "206 Partial Content" : "200 OK", headers)
        guard method != "HEAD" else { return }
        try handle.seek(toOffset: UInt64(start))
        var position = start
        while position <= end {
            try Task.checkCancellation()
            let count = Int(min(256 * 1024, end - position + 1))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
            try await NetworkIO.send(connection, chunk)
            position += Int64(chunk.count)
        }
    }

    /// Passes the request on to the local torrent stream (which fetches the
    /// pieces the TV asks for first) and the answer back, with DLNA headers.
    private nonisolated static func relay(_ client: NWConnection, method: String, from url: URL, type: String,
                                          range: String?, extra: [String: String],
                                          queue: DispatchQueue) async throws {
        guard let host = url.host, let port = url.port.flatMap({ NWEndpoint.Port(rawValue: UInt16($0)) }) else {
            throw NetworkIO.Failure.closed
        }
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        defer { upstream.cancel() }
        try await NetworkIO.start(upstream, on: queue)
        var request = "\(method) \(url.path) HTTP/1.1\r\nHost: \(host):\(port.rawValue)\r\nConnection: close\r\n"
        if let range { request += "Range: \(range)\r\n" }
        request += "\r\n"
        try await NetworkIO.send(upstream, Data(request.utf8))

        // The answer's head: keep status and sizes, add ours.
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        var headEnd: Range<Data.Index>?
        while headEnd == nil {
            guard buffer.count < 64 * 1024 else { throw NetworkIO.Failure.closed }
            buffer.append(try await NetworkIO.receive(upstream, atMost: 64 * 1024))
            headEnd = buffer.range(of: terminator)
        }
        guard let headEnd else { throw NetworkIO.Failure.closed }
        let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self)
        var body = Data(buffer[headEnd.upperBound...])
        let lines = head.components(separatedBy: "\r\n")
        let status = lines.first.map { String($0.split(separator: " ", maxSplits: 1).last ?? "200 OK") } ?? "200 OK"
        var headers = extra
        var contentLength: Int64?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key.lowercased() {
            case "content-length": headers["Content-Length"] = value; contentLength = Int64(value)
            case "content-range": headers["Content-Range"] = value
            case "accept-ranges": headers["Accept-Ranges"] = value
            default: break
            }
        }
        headers["Content-Type"] = type
        try await sendHead(client, status, headers)
        guard method != "HEAD" else { return }

        var sent: Int64 = 0
        while true {
            try Task.checkCancellation()
            if !body.isEmpty {
                if let contentLength, sent + Int64(body.count) > contentLength {
                    body = body.prefix(Int(contentLength - sent))
                }
                try await NetworkIO.send(client, body)
                sent += Int64(body.count)
            }
            if let contentLength, sent >= contentLength { return }
            do {
                body = try await NetworkIO.receive(upstream, atMost: 256 * 1024)
            } catch {
                return                                  // the stream closed: done
            }
        }
    }

    // MARK: Pages

    private func page(for content: Content) -> String {
        let title = DLNA.escape(content.title)
        let video = DLNA.escape(videoURL?.absoluteString ?? "video.\(content.fileExtension)")
        let hasSubtitles = content.subtitles != nil
        let track = hasSubtitles
            ? "<track default kind=\"subtitles\" src=\"subtitles.vtt\" srclang=\"und\" label=\"Subtitles\">" : ""
        let subtitleButton = hasSubtitles
            ? "<a class=\"button\" href=\"subtitles.srt\" download=\"\(title).srt\">Subtitles (.srt)</a>" : ""
        let subtitleHelp = hasSubtitles
            ? "<li>In VLC, drag the downloaded subtitles file onto the video.</li>" : ""
        let videoAddress = DLNA.escape(videoURL?.absoluteString ?? "")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title) · SceneBox</title>
        <style>
        :root { color-scheme: dark; --bg: #0d0f14; --card: #171a22; --text: #eef0f5; --muted: #9aa1b2; --accent: #7c8cff; }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
        main { max-width: 860px; margin: 0 auto; padding: 32px 16px 48px; }
        h1 { font-size: 24px; margin: 0 0 4px; }
        p.lead { color: var(--muted); margin: 0 0 24px; }
        .row { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; }
        .button { display: inline-block; padding: 12px 18px; border-radius: 12px; background: var(--card); color: var(--text);
                  text-decoration: none; font-weight: 600; border: 1px solid #2a2f3c; cursor: pointer; font-size: 15px; }
        .button.primary { background: var(--accent); color: #0b0d12; border-color: transparent; }
        video { width: 100%; border-radius: 12px; background: #000; display: none; margin-bottom: 20px; }
        ol { color: var(--muted); padding-left: 20px; }
        code { background: var(--card); padding: 2px 6px; border-radius: 6px; word-break: break-all; }
        </style></head>
        <body><main>
        <h1>\(title)</h1>
        <p class="lead">Playing from your phone. Keep SceneBox open on it while you watch.</p>
        <div class="row">
          <a class="button primary" href="play.m3u">Open in VLC</a>
          \(subtitleButton)
          <button class="button" onclick="var v=document.querySelector('video');v.style.display='block';v.play();">Play in this browser</button>
        </div>
        <video controls preload="none" src="\(video)">\(track)</video>
        <ol>
          <li>"Open in VLC" downloads a small playlist; open it with VLC (videolan.org). Or in VLC press Ctrl+N and paste <code>\(videoAddress)</code>.</li>
          \(subtitleHelp)
          <li>Browsers can't play some sound formats (Dolby, DTS); if there's no sound, use VLC.</li>
        </ol>
        </main></body></html>
        """
    }

    private func playlist(for content: Content) -> String {
        "#EXTM3U\n#EXTINF:-1,\(content.title)\n\(videoURL?.absoluteString ?? "")\n"
    }

    // MARK: HTTP basics

    private nonisolated static func readHead(_ connection: NWConnection) async throws -> String {
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil {
            guard buffer.count < 32 * 1024 else { throw NetworkIO.Failure.closed }
            buffer.append(try await NetworkIO.receive(connection, atMost: 8192))
        }
        let end = buffer.range(of: terminator)!
        return String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
    }

    private nonisolated static func sendHead(_ connection: NWConnection, _ status: String,
                                             _ headers: [String: String]) async throws {
        var all = headers
        all["Connection"] = "close"
        all["Access-Control-Allow-Origin"] = "*"
        all["Server"] = "SceneBox UPnP/1.0 DLNADOC/1.50"
        var text = "HTTP/1.1 \(status)\r\n"
        for (key, value) in all.sorted(by: { $0.key < $1.key }) { text += "\(key): \(value)\r\n" }
        text += "\r\n"
        try await NetworkIO.send(connection, Data(text.utf8))
    }

    private nonisolated static func sendBody(_ connection: NWConnection, method: String, type: String,
                                             data: Data, extra: [String: String] = [:]) async throws {
        var headers = extra
        headers["Content-Type"] = type
        headers["Content-Length"] = "\(data.count)"
        try await sendHead(connection, "200 OK", headers)
        if method != "HEAD" { try await NetworkIO.send(connection, data) }
    }

    /// "bytes=100-", "bytes=100-199", "bytes=-500" → an inclusive range.
    nonisolated static func parseRange(_ header: String, length: Int64) -> (Int64, Int64)? {
        guard let spec = header.lowercased().components(separatedBy: "bytes=").last?
                .split(separator: ",").first else { return nil }
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int64(parts[1]), suffix > 0 {
            return (max(0, length - suffix), length - 1)
        }
        guard let start = Int64(parts[0]), start < length else { return nil }
        let end = Int64(parts[1]).map { min($0, length - 1) } ?? length - 1
        return start <= end ? (start, end) : nil
    }

    nonisolated static func mimeType(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mkv": "video/x-matroska"
        case "avi": "video/x-msvideo"
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        case "ts", "m2ts": "video/mp2t"
        default: "video/x-matroska"
        }
    }
}

nonisolated private final class CastOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
