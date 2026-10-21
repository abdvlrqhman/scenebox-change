//
//  MatroskaAudio.swift
//  SceneBox
//

import Foundation

/// TVs play the audio track a Matroska file marks as default (or simply the
/// first one), and DLNA has no way to ask for another. So the cast server
/// rewrites the file's track list on its way to the TV: the chosen track
/// becomes the only default audio track and moves in front of the others.
/// The list keeps its exact length, so every offset (and every range the TV
/// asks for) stays where it was.
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
        TrackList([UInt8](head))?.audio.map { Track(language: $0.language, name: $0.name, isDefault: $0.isDefault) } ?? []
    }

    /// The rewritten track list that makes audio track `index` the one TVs
    /// play. Nil when nothing needs to change or the list can't be read.
    static func patch(head: Data, choosing index: Int) -> Patch? {
        var bytes = [UInt8](head)
        guard let list = TrackList(bytes), list.audio.count > 1, list.audio.indices.contains(index) else { return nil }
        let original = Array(bytes[list.data])
        // Explicit default flags: on for the chosen track, off for the rest.
        // A missing flag means "default", which is fine once the chosen track comes first.
        for (i, track) in list.audio.enumerated() {
            guard let flag = track.flag else { continue }
            for p in flag { bytes[p] = 0 }
            bytes[flag.upperBound - 1] = i == index ? 1 : 0
        }
        var pieces = list.children.map { Array(bytes[$0]) }
        let first = list.audio[0].child, chosen = list.audio[index].child
        if chosen != first { pieces.insert(pieces.remove(at: chosen), at: first) }
        var data = pieces.flatMap { $0 }
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
    struct Audio {
        let child: Int              // index into `children`
        let language: String
        let name: String?
        let flag: Range<Int>?       // FlagDefault's value bytes
        let isDefault: Bool
    }

    let data: Range<Int>
    let children: [Range<Int>]
    let audio: [Audio]
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

        var children: [Range<Int>] = [], audio: [Audio] = [], crc: Range<Int>?
        at = tracks.dataStart
        while at < end {
            guard let child = EBMLElement(b, at: at), let childEnd = child.end, childEnd <= end else { return nil }
            if child.id == 0xBF, children.isEmpty, child.size == 4 { crc = child.dataStart..<childEnd }
            if child.id == 0xAE {
                guard let entry = Self.entry(b, child.dataStart..<childEnd, child: children.count) else { return nil }
                if entry.type == 2 { audio.append(entry.track) }
            }
            children.append(at..<childEnd)
            at = childEnd
        }
        data = tracks.dataStart..<end
        self.children = children
        self.audio = audio
        self.crc = crc
    }

    /// One TrackEntry's type (2: audio) and details; nil if it can't be read.
    private static func entry(_ b: [UInt8], _ range: Range<Int>, child: Int) -> (type: UInt64, track: Audio)? {
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
        let isDefault = flag.map { range in b[range].contains { $0 != 0 } } ?? true
        let track = Audio(child: child, language: tag.flatMap { $0.isEmpty ? nil : $0 } ?? language,
                          name: name.flatMap { $0.isEmpty ? nil : $0 }, flag: flag, isDefault: isDefault)
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
