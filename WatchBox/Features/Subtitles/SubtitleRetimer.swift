//
//  SubtitleRetimer.swift
//  SceneBox
//

import Foundation
import CryptoKit

/// Writes a copy of a subtitle file with every timestamp moved.
///
/// Sync used to be VLC's subtitle delay, and a negative delay mostly showed
/// nothing: VLC would have to display a line before it has read it. Moving the
/// timestamps in the file itself works in both directions, and it also fixes
/// frame-rate drift: a file timed for a 25 fps release runs 4% short against a
/// 23.976 fps video, so its times are stretched by 25 / 23.976.
nonisolated enum SubtitleRetimer {
    /// `t' = t × scale + offset`, clamped at zero. Returns the source when there
    /// is nothing to change or the format is frame-based (MicroDVD .sub).
    static func retime(_ source: URL, offsetMilliseconds: Int, scale: Double) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard offsetMilliseconds != 0 || abs(scale - 1) > 0.000_1, ext != "sub" else { return source }

        let output = directory.appendingPathComponent(
            "\(digest("\(source.lastPathComponent)|\(offsetMilliseconds)|\(scale)")).\(ext)")
        if FileManager.default.fileExists(atPath: output.path) { return output }

        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8) else { return source }
        let shift = { (ms: Int) -> Int in max(0, Int((Double(ms) * scale).rounded()) + offsetMilliseconds) }

        let result: String
        switch ext {
        case "ass", "ssa": result = retimeASS(text, shift)
        default: result = retimeCues(text, shift)          // srt, vtt
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(result.utf8).write(to: output, options: .atomic)
        return output
    }

    /// SRT "00:01:02,345 --> 00:01:04,000" and VTT "01:02.345 --> 01:04.000".
    private static func retimeCues(_ text: String, _ shift: (Int) -> Int) -> String {
        let usesComma = text.contains("-->") && text.range(of: #"\d,\d{3}\s*-->"#, options: .regularExpression) != nil
        var lines: [String] = []
        lines.reserveCapacity(text.count / 30)
        for line in splitLines(text) {
            guard line.contains("-->") else { lines.append(line); continue }
            let parts = line.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseCueTime(parts[0]),
                  let end = parseCueTime(parts[1]) else { lines.append(line); continue }
            // Keep anything after the end time (VTT cue settings).
            let settings = parts[1].trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1).dropFirst().first.map { " " + $0 } ?? ""
            lines.append("\(formatCue(shift(start), comma: usesComma)) --> \(formatCue(shift(end), comma: usesComma))\(settings)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Lines with any line ending (CRLF, LF or CR).
    private static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// "01:02:03,456", "01:02:03.456" or "02:03.456" → milliseconds.
    private static func parseCueTime(_ raw: String) -> Int? {
        let token = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let pieces = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        let secondParts = pieces.last!.split(separator: ".")
        guard let seconds = Int(secondParts[0]) else { return nil }
        let fraction = secondParts.count > 1 ? String(secondParts[1].prefix(3)) : "0"
        let millis = (Int(fraction) ?? 0) * Int(pow(10, Double(3 - fraction.count)))
        let minutes = Int(pieces[pieces.count - 2]) ?? 0
        let hours = pieces.count == 3 ? (Int(pieces[0]) ?? 0) : 0
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis
    }

    private static func formatCue(_ ms: Int, comma: Bool) -> String {
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60, f = ms % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, comma ? "," : ".", f)
    }

    /// ASS/SSA "Dialogue: 0,0:01:02.34,0:01:04.00,…" (centiseconds).
    private static func retimeASS(_ text: String, _ shift: (Int) -> Int) -> String {
        var lines: [String] = []
        for line in splitLines(text) {
            guard line.hasPrefix("Dialogue:") || line.hasPrefix("Comment:") else { lines.append(line); continue }
            var fields = line.components(separatedBy: ",")
            guard fields.count > 3,
                  let start = parseASSTime(fields[1]), let end = parseASSTime(fields[2]) else {
                lines.append(line); continue
            }
            fields[1] = formatASS(shift(start))
            fields[2] = formatASS(shift(end))
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseASSTime(_ raw: String) -> Int? {
        let pieces = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard pieces.count == 3, let h = Int(pieces[0]), let m = Int(pieces[1]) else { return nil }
        let secondParts = pieces[2].split(separator: ".")
        guard let s = Int(secondParts[0]) else { return nil }
        let centis = secondParts.count > 1 ? (Int(secondParts[1].prefix(2)) ?? 0) : 0
        return ((h * 60 + m) * 60 + s) * 1000 + centis * 10
    }

    private static func formatASS(_ ms: Int) -> String {
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60, c = (ms % 1000) / 10
        return String(format: "%d:%02d:%02d.%02d", h, m, s, c)
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Subtitles/Retimed", isDirectory: true)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// One subtitle line: when it shows and what it says.
nonisolated struct SubtitleCue: Sendable {
    var start: String       // kept as written, so timing survives untouched
    var end: String
    var text: String

    /// The words only: formatting tags confuse a translator.
    var plainText: String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum SubtitleCues {
    /// SRT or VTT blocks: an optional number, a "start --> end" line, then text.
    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let start = parts[0].trimmingCharacters(in: .whitespaces)
            let end = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            let body = lines[(timing + 1)...].joined(separator: "\n")
            guard !body.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            cues.append(SubtitleCue(start: srtTime(start), end: srtTime(end), text: body))
        }
        return cues
    }

    /// "01:02.500" (VTT) → "00:01:02,500" (SRT).
    private static func srtTime(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: ".", with: ",")
        if value.filter({ $0 == ":" }).count == 1 { value = "00:" + value }
        return value
    }

    static func srt(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(cue.start) --> \(cue.end)\n\(cue.text)\n"
        }.joined(separator: "\n")
    }
}
