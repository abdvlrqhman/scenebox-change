//
//  DLNA.swift
//  SceneBox
//
//  Talking to TVs and players (DLNA / UPnP media renderers): finding them
//  with SSDP, reading their description, and the SOAP commands that load,
//  play, pause, seek and report position. Pure where possible, so the CI
//  self-test checks the bytes.
//

import Foundation

// MARK: - SSDP (finding renderers)

nonisolated enum SSDP {
    static let multicastAddress = "239.255.255.250"
    static let port: UInt16 = 1900
    static let mediaRenderer = "urn:schemas-upnp-org:device:MediaRenderer:1"

    struct Response: Sendable, Equatable {
        let location: URL
        let server: String?
        let usn: String?
    }

    /// An M-SEARCH. `host` is the multicast group, or one device's address
    /// when asking it directly (which works without the multicast permission
    /// iOS keeps from sideloaded apps).
    static func searchMessage(host: String, target: String = mediaRenderer) -> Data {
        let text = "M-SEARCH * HTTP/1.1\r\n"
            + "HOST: \(host):\(port)\r\n"
            + "MAN: \"ssdp:discover\"\r\n"
            + "MX: 1\r\n"
            + "ST: \(target)\r\n"
            + "USER-AGENT: iOS UPnP/1.1 SceneBox/1.7\r\n\r\n"
        return Data(text.utf8)
    }

    /// A search answer ("HTTP/1.1 200 OK" with a LOCATION header).
    static func parseResponse(_ data: Data) -> Response? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let lines = text.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        guard let status = lines.first?.uppercased(), status.hasPrefix("HTTP/"), status.contains(" 200") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let raw = headers["location"], let location = URL(string: raw),
              location.scheme?.lowercased() == "http" else { return nil }
        return Response(location: location, server: headers["server"], usn: headers["usn"])
    }
}

// MARK: - Device description

/// A renderer that can be told what to play.
nonisolated struct RendererDescription: Sendable, Equatable, Codable, Identifiable {
    let location: URL
    let name: String
    let manufacturer: String
    let model: String
    let udn: String
    let avTransport: URL
    let renderingControl: URL?

    var id: String { udn.isEmpty ? location.absoluteString : udn }

    /// Kodi, Windows Media Player and the like run on computers.
    var isComputer: Bool {
        let text = "\(manufacturer) \(model) \(name)".lowercased()
        return ["kodi", "xbmc", "microsoft", "windows", "vlc", "plex", "jellyfin"].contains { text.contains($0) }
    }
}

nonisolated enum UPnPDescription {
    static let avTransportType = "urn:schemas-upnp-org:service:AVTransport:"
    static let renderingControlType = "urn:schemas-upnp-org:service:RenderingControl:"

    /// The first device in the description (itself or nested) that offers
    /// AVTransport, with its control addresses made absolute.
    static func parse(_ data: Data, location: URL) -> RendererDescription? {
        let collector = DescriptionCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() || !collector.devices.isEmpty else { return nil }
        let base = collector.urlBase.flatMap { URL(string: $0) } ?? location
        for device in collector.devices {
            guard let transport = device.services.first(where: { $0.type.hasPrefix(avTransportType) }),
                  let control = URL(string: transport.controlURL, relativeTo: base)?.absoluteURL else { continue }
            let rendering = device.services.first { $0.type.hasPrefix(renderingControlType) }
                .flatMap { URL(string: $0.controlURL, relativeTo: base)?.absoluteURL }
            let name = device.friendlyName.isEmpty ? (location.host ?? "TV") : device.friendlyName
            return RendererDescription(location: location, name: name, manufacturer: device.manufacturer,
                                       model: device.modelName, udn: device.udn,
                                       avTransport: control, renderingControl: rendering)
        }
        return nil
    }
}

nonisolated private final class DescriptionCollector: NSObject, XMLParserDelegate {
    struct Service { var type = ""; var controlURL = "" }
    struct Device {
        var friendlyName = "", manufacturer = "", modelName = "", udn = ""
        var services: [Service] = []
    }

    private(set) var devices: [Device] = []
    private(set) var urlBase: String?
    private var deviceStack: [Device] = []
    private var service: Service?
    private var text = ""

    private func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch local(elementName) {
        case "device": deviceStack.append(Device())
        case "service": service = Service()
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local(elementName) {
        case "URLBase": urlBase = value
        case "friendlyName": if !deviceStack.isEmpty { deviceStack[deviceStack.count - 1].friendlyName = value }
        case "manufacturer": if !deviceStack.isEmpty { deviceStack[deviceStack.count - 1].manufacturer = value }
        case "modelName": if !deviceStack.isEmpty { deviceStack[deviceStack.count - 1].modelName = value }
        case "UDN": if !deviceStack.isEmpty { deviceStack[deviceStack.count - 1].udn = value }
        case "serviceType": service?.type = value
        case "controlURL": service?.controlURL = value
        case "service":
            if let service, !deviceStack.isEmpty { deviceStack[deviceStack.count - 1].services.append(service) }
            service = nil
        case "device":
            if let device = deviceStack.popLast() { devices.append(device) }
        default: break
        }
        text = ""
    }
}

// MARK: - SOAP commands

nonisolated enum DLNA {
    static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"

    /// Byte seeking allowed, streamed, not transcoded: without this several
    /// TVs refuse to seek or to play at all.
    static let contentFeatures = "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"

    static func soapEnvelope(action: String, service: String = avTransport,
                             arguments: [(String, String)]) -> Data {
        let body = arguments.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
            + "<u:\(action) xmlns:u=\"\(service)\">\(body)</u:\(action)>"
            + "</s:Body></s:Envelope>"
        return Data(xml.utf8)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }

    /// What the TV shows about the video, with the subtitle file given in
    /// every form TVs look for: Samsung (`sec:CaptionInfoEx`), LG, Kodi and
    /// most others (a text `res`), and `pv:subtitleFileUri`.
    static func didl(title: String, videoURL: URL, mimeType: String, size: Int64?,
                     durationSeconds: Double?, subtitleURL: URL?) -> String {
        // LG shows nothing for a title without a dot in it.
        let shownTitle = title.contains(".") ? title : "\(title)."
        var resAttributes = "protocolInfo=\"http-get:*:\(mimeType):\(contentFeatures)\""
        if let size, size > 0 { resAttributes += " size=\"\(size)\"" }
        if let durationSeconds, durationSeconds > 0 {
            resAttributes += " duration=\"\(timeString(durationSeconds)).000\""
        }
        var subtitleParts = ""
        if let subtitleURL {
            let sub = escape(subtitleURL.absoluteString)
            resAttributes += " pv:subtitleFileUri=\"\(sub)\" pv:subtitleFileType=\"srt\""
            subtitleParts = "<res protocolInfo=\"http-get:*:text/srt:*\">\(sub)</res>"
                + "<sec:CaptionInfoEx sec:type=\"srt\">\(sub)</sec:CaptionInfoEx>"
                + "<sec:CaptionInfo sec:type=\"srt\">\(sub)</sec:CaptionInfo>"
        }
        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" "
            + "xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" "
            + "xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\" "
            + "xmlns:sec=\"http://www.sec.co.kr/\" xmlns:pv=\"http://www.pv.com/pvns/\">"
            + "<item id=\"0\" parentID=\"-1\" restricted=\"1\">"
            + "<dc:title>\(escape(shownTitle))</dc:title>"
            + "<upnp:class>object.item.videoItem.movie</upnp:class>"
            + "<res \(resAttributes)>\(escape(videoURL.absoluteString))</res>"
            + subtitleParts
            + "</item></DIDL-Lite>"
    }

    /// 3725 → "1:02:05".
    static func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    /// "1:02:05", "01:02:05.500" → seconds; "NOT_IMPLEMENTED" and the like → nil.
    static func parseTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    /// The text of `<tag>` in a SOAP answer, whatever its namespace prefix.
    static func value(of tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<(?:[A-Za-z0-9_]+:)?\(tag)(?:\\s[^>]*)?>", options: .regularExpression),
              let close = xml.range(of: "</(?:[A-Za-z0-9_]+:)?\(tag)>", options: .regularExpression,
                                    range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound])
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// A UPnP error's description, from a SOAP fault.
    static func fault(in xml: String) -> String? {
        value(of: "errorDescription", in: xml) ?? value(of: "faultstring", in: xml)
    }
}

nonisolated enum CastError: LocalizedError {
    case renderer(String)
    case noNetwork
    case unreachable

    var errorDescription: String? {
        switch self {
        case .renderer(let message): "The TV said: \(message)"
        case .noNetwork: "Connect to the same Wi-Fi as the TV."
        case .unreachable: "The TV didn't answer. Check it's on and on the same Wi-Fi."
        }
    }
}

/// Commands to one renderer.
nonisolated struct DLNAController: Sendable {
    let device: RendererDescription

    @discardableResult
    func call(_ action: String, _ arguments: [(String, String)] = [],
              timeout: TimeInterval = 8) async throws -> String {
        var request = URLRequest(url: device.avTransport)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        // Written exactly so: some Samsung TVs match these case-sensitively,
        // and refuse commands from a client that doesn't say it's UPnP.
        request.setValue("\"\(DLNA.avTransport)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.setValue("SceneBox/1.7 UPnP/1.0 DLNADOC/1.50", forHTTPHeaderField: "User-Agent")
        request.httpBody = DLNA.soapEnvelope(action: action, arguments: [("InstanceID", "0")] + arguments)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CastError.unreachable
        }
        let text = String(decoding: data, as: UTF8.self)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = DLNA.value(of: "errorCode", in: text).map { " (\($0))" } ?? ""
            throw CastError.renderer((DLNA.fault(in: text) ?? "error \(status)") + code)
        }
        return text
    }

    func load(_ url: URL, metadata: String) async throws {
        try await call("SetAVTransportURI", [("CurrentURI", url.absoluteString), ("CurrentURIMetaData", metadata)],
                       timeout: 15)
    }

    func play() async throws { try await call("Play", [("Speed", "1")]) }
    func pause() async throws { try await call("Pause") }
    func stop() async throws { try await call("Stop", timeout: 4) }

    func seek(to seconds: Double) async throws {
        try await call("Seek", [("Unit", "REL_TIME"), ("Target", DLNA.timeString(seconds))])
    }

    /// PLAYING, PAUSED_PLAYBACK, STOPPED, TRANSITIONING, NO_MEDIA_PRESENT.
    func transportState() async throws -> String {
        let answer = try await call("GetTransportInfo", timeout: 4)
        return DLNA.value(of: "CurrentTransportState", in: answer) ?? ""
    }

    func position() async throws -> (position: Double?, duration: Double?) {
        let answer = try await call("GetPositionInfo", timeout: 4)
        return (DLNA.value(of: "RelTime", in: answer).flatMap(DLNA.parseTime),
                DLNA.value(of: "TrackDuration", in: answer).flatMap(DLNA.parseTime))
    }
}
