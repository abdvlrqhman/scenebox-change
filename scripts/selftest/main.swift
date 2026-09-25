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

try? FileManager.default.removeItem(at: work)
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
