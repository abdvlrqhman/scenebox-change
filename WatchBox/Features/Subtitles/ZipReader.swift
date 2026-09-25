//
//  ZipReader.swift
//  SceneBox
//

import Foundation
import Compression

/// Reads the first subtitle out of a zip. SubDL and SubSource hand out zipped
/// subtitles; Foundation can't open a zip, and this is the whole of what's
/// needed: find the entry, then inflate it.
nonisolated enum ZipReader {
    private static let subtitleExtensions = ["srt", "vtt", "ass", "ssa", "sub"]

    static func isZip(_ data: Data) -> Bool {
        data.count > 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
    }

    /// The first subtitle entry's bytes, and its name.
    static func firstSubtitle(in data: Data) -> (name: String, contents: Data)? {
        for entry in entries(in: data) {
            let ext = (entry.name as NSString).pathExtension.lowercased()
            guard subtitleExtensions.contains(ext), !entry.name.hasPrefix("__MACOSX") else { continue }
            if let contents = extract(entry, from: data), contents.count > 20 {
                return (entry.name, contents)
            }
        }
        return nil
    }

    private struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Walks the central directory, which is at the end of the file.
    private static func entries(in data: Data) -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { return [] }
        func read16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
        func read32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }

        // End of central directory: scan back over the comment (max 64 KB).
        var eocd = -1
        let lowest = max(0, bytes.count - 22 - 65_536)
        var index = bytes.count - 22
        while index >= lowest {
            if read32(index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { return [] }
        let count = Int(read16(eocd + 10))
        var offset = Int(read32(eocd + 16))
        guard count > 0, offset > 0, offset < bytes.count else { return [] }

        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, read32(offset) == 0x0201_4B50 else { break }
            let method = read16(offset + 10)
            let compressed = Int(read32(offset + 20))
            let uncompressed = Int(read32(offset + 24))
            let nameLength = Int(read16(offset + 28))
            let extraLength = Int(read16(offset + 30))
            let commentLength = Int(read16(offset + 32))
            let local = Int(read32(offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            result.append(Entry(name: name, method: method, compressedSize: compressed,
                                uncompressedSize: uncompressed, localHeaderOffset: local))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func extract(_ entry: Entry, from data: Data) -> Data? {
        let bytes = [UInt8](data)
        let start = entry.localHeaderOffset
        guard start + 30 <= bytes.count else { return nil }
        func read16(_ i: Int) -> Int { Int(UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8) }
        guard UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
                | UInt32(bytes[start + 2]) << 16 | UInt32(bytes[start + 3]) << 24 == 0x0403_4B50 else { return nil }
        let nameLength = read16(start + 26)
        let extraLength = read16(start + 28)
        let dataStart = start + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= bytes.count else { return nil }
        let payload = data.subdata(in: dataStart..<(dataStart + entry.compressedSize))

        switch entry.method {
        case 0: return payload                       // stored
        case 8: return inflate(payload, expected: entry.uncompressedSize)
        default: return nil
        }
    }

    /// Raw DEFLATE, which is what zip stores (COMPRESSION_ZLIB in Apple's
    /// framework means raw deflate, no zlib wrapper).
    private static func inflate(_ data: Data, expected: Int) -> Data? {
        let capacity = max(expected, data.count * 8) + 4096
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, capacity,
                                                 sourceBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
