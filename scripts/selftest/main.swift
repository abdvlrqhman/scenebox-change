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

try? FileManager.default.removeItem(at: work)
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
