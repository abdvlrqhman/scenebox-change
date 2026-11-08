//
//  MatroskaAudio.swift
//  SceneBox
//

import Foundation

/// TVs pick their own audio and subtitle track from a Matroska file, and DLNA
/// has no way to ask for another. So the cast server rewrites the file's track
/// list on its way to the TV: only the voice playing on the phone stays (and the
/// built-in subtitle showing there, if any); every other audio and subtitle
/// entry becomes an EBML Void of the same length. The TV can't list or pick
/// them, the list keeps its exact length, and every offset (and every range the
/// TV asks for) stays where it was. Their packets are skipped as unknown tracks.
nonisolated enum MatroskaAudio {
    struct Track: Sendable, Equatable {
        let language: String        // "eng", "fre", or a BCP 47 tag like "pt-BR"
        let name: String?
        let isDefault: Bool
    }

    /// Bytes to lay over the file, starting at `offset`.
    struct Patch: Sendable, Equatable {
        let offset: Int64
        let bytes: Data
    }

    /// The audio tracks, in file order, from the file's first bytes. Empty
    /// when it isn't Matroska or the track list isn't in `head`.
    static func audioTracks(in head: Data) -> [Track] {
        TrackList([UInt8](head))?.audio.map(\.track) ?? []
    }

    /// The built-in subtitle tracks, in file order.
    static func subtitleTracks(in head: Data) -> [Track] {
        TrackList([UInt8](head))?.subtitles.map(\.track) ?? []
    }

    /// The rewritten track list that leaves the TV audio track `index` and, if given,
    /// built-in subtitle track `subtitle`; nothing else to list or pick. Nil when
    /// nothing needs to change or the list can't be read.
    static func patch(head: Data, choosing index: Int, keepingSubtitle subtitle: Int? = nil) -> Patch? {
        var bytes = [UInt8](head)
        guard let list = TrackList(bytes), list.audio.indices.contains(index) else { return nil }
        let original = Array(bytes[list.data])
        var keep: Set<Int> = [list.audio[index].child]
        if let subtitle, list.subtitles.indices.contains(subtitle) { keep.insert(list.subtitles[subtitle].child) }
        for entry in list.audio + list.subtitles {
            let range = list.children[entry.child]
            if keep.contains(entry.child) {
                // The one left is the default, whatever the file said.
                if let flag = entry.flag {
                    for p in flag { bytes[p] = 0 }
                    bytes[flag.upperBound - 1] = 1
                }
            } else {
                guard let void = voidElement(length: range.count) else { return nil }
                bytes.replaceSubrange(range, with: void)
            }
        }
        var data = Array(bytes[list.data])
        if let crc = list.crc {             // a leading CRC-32 covers everything after itself
            let value = crc32(data[(crc.upperBound - list.data.lowerBound)...])
            for i in 0..<4 { data[crc.lowerBound - list.data.lowerBound + i] = UInt8(value >> (8 * UInt32(i)) & 0xFF) }
        }
        guard data != original else { return nil }
        return Patch(offset: Int64(list.data.lowerBound), bytes: Data(data))
    }

    /// Lays `patch` over `chunk`, a piece of the file starting at `position`.
    static func apply(_ patch: Patch?, to chunk: inout Data, at position: Int64) {
        guard let patch, !chunk.isEmpty else { return }
        let start = max(position, patch.offset)
        let end = min(position + Int64(chunk.count), patch.offset + Int64(patch.bytes.count))
        guard start < end else { return }
        let from = patch.bytes.startIndex + Int(start - patch.offset)
        chunk.replaceSubrange(chunk.startIndex + Int(start - position) ..< chunk.startIndex + Int(end - position),
                              with: patch.bytes[from ..< from + Int(end - start)])
    }

    /// An EBML Void element exactly `length` bytes long: ID 0xEC, the shortest size
    /// that fits, then zeros. Nil below 2 bytes (no TrackEntry is that short).
    static func voidElement(length: Int) -> [UInt8]? {
        for sizeLength in 1...8 {
            let payload = length - 1 - sizeLength
            guard payload >= 0 else { return nil }
            let limit = (UInt64(1) << UInt64(7 * sizeLength)) - 1       // all ones means "unknown size"
            guard UInt64(payload) < limit else { continue }
            let size = UInt64(payload) | (UInt64(1) << UInt64(7 * sizeLength))   // the length marker bit
            let sizeBytes = (0..<sizeLength).reversed().map { UInt8(truncatingIfNeeded: size >> UInt64(8 * $0)) }
            return [0xEC] + sizeBytes + [UInt8](repeating: 0, count: payload)
        }
        return nil
    }

    /// IEEE CRC-32, as EBML stores it (little-endian).
    static func crc32(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

// MARK: - Reading the track list

/// The Tracks element of a Matroska file: where it sits, its children back to
/// back, and which of them are audio tracks.
nonisolated private struct TrackList {
    struct Entry {
        let child: Int              // index into `children`
        let language: String
        let name: String?
        let flag: Range<Int>?       // FlagDefault's value bytes
        let isDefault: Bool

        var track: MatroskaAudio.Track { .init(language: language, name: name, isDefault: isDefault) }
    }

    let data: Range<Int>
    let children: [Range<Int>]
    let audio: [Entry]
    let subtitles: [Entry]
    let crc: Range<Int>?            // a leading CRC-32's value bytes

    // shortcut: only a track list ahead of the first cluster (where muxers put it); one after would need the SeekHead.
    init?(_ b: [UInt8]) {
        guard let ebml = EBMLElement(b, at: 0), ebml.id == 0x1A45_DFA3, let ebmlEnd = ebml.end,
              let segment = EBMLElement(b, at: ebmlEnd), segment.id == 0x1853_8067 else { return nil }
        var at = segment.dataStart
        var tracks: EBMLElement?
        while let element = EBMLElement(b, at: at) {
            if element.id == 0x1654_AE6B { tracks = element; break }
            guard element.id != 0x1F43_B675, let end = element.end else { return nil }
            at = end
        }
        guard let tracks, let end = tracks.end, end <= b.count else { return nil }

        var children: [Range<Int>] = [], audio: [Entry] = [], subtitles: [Entry] = [], crc: Range<Int>?
        at = tracks.dataStart
        while at < end {
            guard let child = EBMLElement(b, at: at), let childEnd = child.end, childEnd <= end else { return nil }
            if child.id == 0xBF, children.isEmpty, child.size == 4 { crc = child.dataStart..<childEnd }
            if child.id == 0xAE {
                guard let entry = Self.entry(b, child.dataStart..<childEnd, child: children.count) else { return nil }
                if entry.type == 2 { audio.append(entry.track) }
                if entry.type == 0x11 { subtitles.append(entry.track) }
            }
            children.append(at..<childEnd)
            at = childEnd
        }
        data = tracks.dataStart..<end
        self.children = children
        self.audio = audio
        self.subtitles = subtitles
        self.crc = crc
    }

    /// One TrackEntry's type (2: audio, 0x11: subtitles) and details; nil if it can't be read.
    private static func entry(_ b: [UInt8], _ range: Range<Int>, child: Int) -> (type: UInt64, track: Entry)? {
        var type: UInt64 = 0, language = "eng", tag: String?, name: String?, flag: Range<Int>?
        var at = range.lowerBound
        while at < range.upperBound {
            guard let e = EBMLElement(b, at: at), let end = e.end, end <= range.upperBound else { return nil }
            let value = b[e.dataStart..<end]
            switch e.id {
            case 0x83 where value.count <= 8: type = value.reduce(0) { $0 << 8 | UInt64($1) }
            case 0x88 where (1...8).contains(value.count): flag = e.dataStart..<end
            case 0x22_B59C: language = text(value)
            case 0x22_B59D: tag = text(value)
            case 0x536E: name = text(value)
            default: break
            }
            at = end
        }
        var isDefault = true                                    // a missing flag means default
        if let flag { isDefault = b[flag].contains { $0 != 0 } }
        if let found = tag, !found.isEmpty { language = found }
        let track = Entry(child: child, language: language, name: name?.isEmpty == false ? name : nil,
                          flag: flag, isDefault: isDefault)
        return (type, track)
    }

    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
    }
}

/// An EBML element's header: its ID, where its data starts and how long it is (nil: unknown).
nonisolated private struct EBMLElement {
    let id: UInt32
    let dataStart: Int
    let size: Int?
    var end: Int? { size.map { dataStart + $0 } }

    init?(_ b: [UInt8], at: Int) {
        guard let id = Self.vint(b, at, keepMarker: true), id.length <= 4,
              let size = Self.vint(b, at + id.length, keepMarker: false) else { return nil }
        self.id = UInt32(id.value)
        dataStart = at + id.length + size.length
        let unknown = size.value == (UInt64(1) << (7 * UInt64(size.length))) - 1
        self.size = unknown ? nil : Int(size.value)
    }

    /// A variable-length EBML number: its length comes from the leading zero bits.
    private static func vint(_ b: [UInt8], _ at: Int, keepMarker: Bool) -> (value: UInt64, length: Int)? {
        guard at >= 0, at < b.count, b[at] != 0 else { return nil }
        let length = b[at].leadingZeroBitCount + 1
        guard at + length <= b.count else { return nil }
        var value = UInt64(keepMarker ? b[at] : b[at] & UInt8(truncatingIfNeeded: 0xFF >> length))
        for i in 1..<length { value = value << 8 | UInt64(b[at + i]) }
        return (value, length)
    }
}
