"""Writes sheet-before-after.html from two CI screenshot folders.
usage: python3 before_after.py <before-shots-dir> <after-shots-dir>"""
import os
import sys

before, after = sys.argv[1], sys.argv[2]
portrait = [("01-home", "01-home", "Home"), ("06-detail-series", "06-detail-series", "Title page"),
            ("10-detail-episodes", "10-detail-episodes", "Episodes"), ("11-search-results", "11-search-results", "Search"),
            ("02-library-downloads", "02-library-downloads", "My Stuff"), ("05-profile", "05-profile", "Settings"),
            ("00-first-launch", "18-first-run", "First run"), ("17-home-new-viewer", "17-home-new-viewer", "Home, new viewer")]
landscape = [("13-player", "13-player", "Player"), ("15-cast-playing", "15-cast-playing", "Casting")]

def pair(b, a, title):
    return f"""<figure class="pair"><figcaption>{title}</figcaption><div class="imgs">
<div><img src="file://{os.path.join(before, b)}.png"><span>1.9.0</span></div>
<div><img src="file://{os.path.join(after, a)}.png"><span>2.0</span></div></div></figure>"""

html = f"""<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=block"><style>
body{{margin:0;background:#000;color:#fff;font:15px Inter;padding:40px 48px 48px;width:1800px;box-sizing:border-box}}
h1{{font:700 34px Inter;margin:0 0 6px}} p{{color:rgba(255,255,255,.6);margin:0 0 28px;font-size:17px}}
.grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:28px 32px}} .wide{{display:grid;grid-template-columns:repeat(2,1fr);gap:32px;margin-top:32px}}
figure{{margin:0}} figcaption{{font:700 18px Inter;margin-bottom:10px}}
.imgs{{display:grid;grid-template-columns:1fr 1fr;gap:10px}} .imgs img{{width:100%;border-radius:14px;display:block;outline:1px solid rgba(255,255,255,.12)}}
.imgs span{{display:block;margin-top:6px;font:600 13px Inter;color:rgba(255,255,255,.55)}}
</style></head><body><h1>SceneBox 1.9.0 → 2.0 "Noir Lumière"</h1>
<p>Same seeded data, same simulator (iPhone 17 Pro Max), CI screenshots. Left of each pair: before. Right: after.</p>
<div class="grid">{''.join(pair(*p) for p in portrait)}</div>
<div class="wide">{''.join(pair(*p) for p in landscape)}</div></body></html>"""
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sheet-before-after.html"), "w").write(html)
print("wrote sheet-before-after.html")
