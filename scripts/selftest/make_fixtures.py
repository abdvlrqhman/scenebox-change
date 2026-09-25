"""Writes the self-test fixtures: zips (deflated and stored) and SRT/VTT/ASS samples."""
import os
import sys
import zipfile

out = sys.argv[1]
os.makedirs(out, exist_ok=True)

srt = (
    "1\r\n00:00:01,000 --> 00:00:03,500\r\nمرحبا\r\n\r\n"
    "2\r\n00:01:02,000 --> 00:01:04,000\r\n<i>Second</i>\r\n\r\n"
)
with open(os.path.join(out, "sample.srt"), "w", encoding="utf-8", newline="") as f:
    f.write(srt)

vtt = (
    "WEBVTT\n\n"
    "00:01.000 --> 00:03.500 line:90%\nFirst line\n\n"
    "00:00:05.000 --> 00:00:07.000\n<b>Second</b> line\n"
)
with open(os.path.join(out, "sample.vtt"), "w", encoding="utf-8", newline="") as f:
    f.write(vtt)

ass = (
    "[Script Info]\nTitle: test\n\n[Events]\n"
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    "Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,مرحبا, كيف الحال\n"
)
with open(os.path.join(out, "sample.ass"), "w", encoding="utf-8", newline="") as f:
    f.write(ass)

for name, method in [("deflated.zip", zipfile.ZIP_DEFLATED), ("stored.zip", zipfile.ZIP_STORED)]:
    with zipfile.ZipFile(os.path.join(out, name), "w", compression=method) as z:
        z.writestr("folder/", "")
        z.writestr("folder/readme.txt", "not a subtitle " * 50)
        z.writestr("folder/Show.S01E01.srt", srt.encode("utf-8"))
print("fixtures in", out)
