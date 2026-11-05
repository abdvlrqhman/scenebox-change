"""Writes the design-direction mockups (HTML) that render.mjs turns into PNGs.
Real catalog artwork (metahub) and real episode data; tokens from Theme.swift."""
import os

OUT = os.path.dirname(os.path.abspath(__file__))
MH = "https://images.metahub.space"
def bg(i, size="large"): return f"{MH}/background/{size}/{i}/img"
def poster(i): return f"{MH}/poster/medium/{i}/img"
def logo(i): return f"{MH}/logo/medium/{i}/img"
def still(s, e): return f"https://episodes.metahub.space/tt0903747/{s}/{e}/w780.jpg"

ICONS = """<svg width="0" height="0" style="position:absolute"><defs>
<symbol id="i-home" viewBox="0 0 24 24"><path d="M3.5 10.2 12 3.5l8.5 6.7V20a1 1 0 0 1-1 1H15v-6.2H9V21H4.5a1 1 0 0 1-1-1z" fill="currentColor"/></symbol>
<symbol id="i-search" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="m15.5 15.5 5 5" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></symbol>
<symbol id="i-stack" viewBox="0 0 24 24"><rect x="3" y="7" width="18" height="13" rx="3" fill="currentColor"/><path d="M6 4.5h12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>
<symbol id="i-play" viewBox="0 0 24 24"><path d="M7 4.6v14.8a1 1 0 0 0 1.5.86l12.1-7.4a1 1 0 0 0 0-1.72L8.5 3.74A1 1 0 0 0 7 4.6z" fill="currentColor"/></symbol>
<symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></symbol>
<symbol id="i-check" viewBox="0 0 24 24"><path d="m5 12.5 4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-down" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.5v8m-3.5-3.5L12 15.5l3.5-3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-downfill" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M12 7v9m-4-4 4 4 4-4" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-back" viewBox="0 0 24 24"><path d="m14.5 5-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-tv" viewBox="0 0 24 24"><rect x="2.5" y="4" width="19" height="13" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M8 20.5h8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></symbol>
<symbol id="i-share" viewBox="0 0 24 24"><path d="M12 15V3.5m-4 4 4-4 4 4M6 11H5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-star" viewBox="0 0 24 24"><path d="m12 3 2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 16.8l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z" fill="currentColor"/></symbol>
<symbol id="i-bookmark" viewBox="0 0 24 24"><path d="M6.5 3.5h11v17l-5.5-4-5.5 4z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></symbol>
<symbol id="i-chev" viewBox="0 0 24 24"><path d="m9 5 7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-chevdown" viewBox="0 0 24 24"><path d="m5 9 7 7 7-7" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></symbol>
<symbol id="i-wifi" viewBox="0 0 24 24"><path d="M2 9.5a15 15 0 0 1 20 0M5.5 13a10 10 0 0 1 13 0M9 16.5a5 5 0 0 1 6 0" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><circle cx="12" cy="20" r="1.6" fill="currentColor"/></symbol>
<symbol id="i-captions" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M10.5 10.2a2.2 2.2 0 1 0 0 3.6M16.5 10.2a2.2 2.2 0 1 0 0 3.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></symbol>
<symbol id="i-sliders" viewBox="0 0 24 24"><path d="M4 7h10m4 0h2M4 17h4m4 0h8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="16" cy="7" r="2.2" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="10" cy="17" r="2.2" fill="none" stroke="currentColor" stroke-width="2"/></symbol>
</defs></svg>"""

TRIM = """<script>
// The app trims transparent margins off title logos (TrimTransparentEdges); so do the mockups.
document.querySelectorAll('img.logo').forEach(img => {
  const trim = () => {
    if (img.dataset.trimmed) return
    img.dataset.trimmed = '1'
    const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight
    const x = c.getContext('2d'); x.drawImage(img, 0, 0)
    const d = x.getImageData(0, 0, c.width, c.height).data
    let a = c.width, b = c.height, e = -1, f = -1
    for (let y = 0; y < c.height; y++) for (let i = 0; i < c.width; i++)
      if (d[(y * c.width + i) * 4 + 3] > 10) { if (i < a) a = i; if (i > e) e = i; if (y < b) b = y; if (y > f) f = y }
    if (e < 0) return
    const o = document.createElement('canvas'); o.width = e - a + 1; o.height = f - b + 1
    o.getContext('2d').drawImage(c, a, b, o.width, o.height, 0, 0, o.width, o.height)
    img.src = o.toDataURL()
  }
  if (img.complete && img.naturalWidth) trim(); else img.addEventListener('load', trim)
})
</script>"""

def icon(name, size=22, style=""):
    return f'<svg width="{size}" height="{size}" style="{style}"><use href="#i-{name}"/></svg>'

STATUS = f"""<div class="status"><span>9:41</span><div class="island"></div><div class="icons"><div class="bars"></div>{icon('wifi', 18)}<div class="batt"><i></i></div></div></div>"""

def tabbar(active, tabs=(("home", "Home"), ("search", "Search"), ("stack", "My Stuff"))):
    items = "".join(f'<div class="tab{" on" if i == active else ""}">{icon(n, 24)}<span>{t}</span></div>' for i, (n, t) in enumerate(tabs))
    return f'<div class="tabbar">{items}</div><div class="home-indicator"></div>'

def page(name, body, extra_css=""):
    html = f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="kit.css"><style>{extra_css}</style></head>
<body>{ICONS}{STATUS}{body}{TRIM}</body></html>"""
    with open(os.path.join(OUT, name + ".html"), "w") as f:
        f.write(html)
    print("wrote", name)

def progress(frac, color="var(--accent)", track="rgba(255,255,255,.28)", h=3):
    return f'<div style="height:{h}px;border-radius:{h}px;background:{track};overflow:hidden"><div style="height:100%;width:{int(frac*100)}%;background:{color}"></div></div>'

TOP_SHOWS = ["tt26598805", "tt33043892", "tt31510819", "tt11540908", "tt23148340", "tt5875444"]
MOVIES = ["tt26581740", "tt22084616", "tt37287335", "tt21285562", "tt14173636", "tt0107688"]

# ---------------------------------------------------------------- A: Marquee
page("A1-marquee-home", f"""
<div style="position:absolute;inset:0 0 auto 0;height:600px;background:url({bg('tt5875444')}) 58% 20%/cover"></div>
<div style="position:absolute;inset:0 0 auto 0;height:600px;background:linear-gradient(180deg,rgba(13,13,18,.55) 0,rgba(13,13,18,0) 22%,rgba(13,13,18,0) 45%,rgba(13,13,18,.85) 80%,var(--ink) 100%)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;align-items:center;justify-content:space-between">
  <div class="display" style="font-size:30px">SceneBox</div>
  <div style="width:36px;height:36px;border-radius:18px;background:#2f6fde;display:grid;place-items:center;font:700 16px Inter">M</div>
</div>
<div style="position:absolute;top:356px;left:16px;right:16px">
  <img class="logo" src="{logo('tt5875444')}" style="height:96px;max-width:300px;object-fit:contain;object-position:left bottom;display:block;filter:drop-shadow(0 4px 14px rgba(0,0,0,.5))">
  <div style="display:flex;gap:14px;align-items:center;margin:12px 0 16px;font:600 14px Inter;color:rgba(255,255,255,.85)">
    <span style="display:flex;gap:4px;align-items:center">{icon('star',14)}8.4</span><span>2022–</span><span>Drama, Thriller</span><span class="t2">New season</span>
  </div>
  <div style="display:flex;gap:12px;align-items:center">
    <div class="cta" style="width:200px">{icon('play',20)}Play S5 E1</div>
    <div class="round">{icon('plus',22)}</div>
    <div style="flex:1"></div>
    <div style="display:flex;gap:6px"><i style="width:18px;height:6px;border-radius:3px;background:#fff"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i></div>
  </div>
</div>
<div style="position:absolute;top:608px;left:16px;right:0">
  <div style="display:flex;align-items:baseline;gap:6px;margin-bottom:12px"><span class="display" style="font-size:26px">Up next</span></div>
  <div style="display:flex;gap:12px">
    <div style="width:262px;flex:none">
      <div style="height:147px;border-radius:14px;background:url({still(1,4)}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">
        <div style="position:absolute;inset:auto 0 0 0;height:60px;background:linear-gradient(transparent,rgba(0,0,0,.6))"></div>
        <div style="position:absolute;left:12px;bottom:12px;width:36px;height:36px;border-radius:18px;background:rgba(0,0,0,.5);display:grid;place-items:center;backdrop-filter:blur(8px)">{icon('play',16)}</div>
      </div>
      <div style="margin-top:8px;font:600 14px Inter">Breaking Bad</div>
      <div style="font:500 13px Inter" class="t2"><b style="color:rgba(255,255,255,.85)">S1 E4</b>&nbsp; Cancer Man</div>
    </div>
    <div style="width:262px;flex:none">
      <div style="height:147px;border-radius:14px;background:url({bg('tt1375666','medium')}) center/cover;position:relative;overflow:hidden">
        <div style="position:absolute;left:12px;right:12px;bottom:10px">{progress(0.46)}</div>
      </div>
      <div style="margin-top:8px;font:600 14px Inter">Inception</div>
      <div style="font:500 13px Inter" class="t2">1h 20m left</div>
    </div>
  </div>
</div>
<div style="position:absolute;top:842px;left:16px" class="display"><span style="font-size:26px">Top 10 shows</span></div>
{tabbar(0)}
""")

page("A2-marquee-title", f"""
<div style="position:absolute;inset:0 0 auto 0;height:470px;background:url({bg('tt0903747')}) 62% 30%/cover"></div>
<div style="position:absolute;inset:0 0 auto 0;height:470px;background:linear-gradient(180deg,rgba(13,13,18,.45) 0,rgba(13,13,18,0) 25%,rgba(13,13,18,.2) 55%,var(--ink) 100%)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;justify-content:space-between">
  <div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45);backdrop-filter:blur(10px);border-color:rgba(255,255,255,.12)">{icon('back',20)}</div>
  <div style="display:flex;gap:10px"><div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45);border-color:rgba(255,255,255,.12)">{icon('tv',20)}</div><div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45);border-color:rgba(255,255,255,.12)">{icon('share',20)}</div></div>
</div>
<div style="position:absolute;top:322px;left:16px;right:16px">
  <img class="logo" src="{logo('tt0903747')}" style="height:88px;object-fit:contain;object-position:left bottom;display:block">
  <div style="display:flex;gap:14px;margin:10px 0 16px;font:600 14px Inter;color:rgba(255,255,255,.85)"><span style="display:flex;gap:4px;align-items:center">{icon('star',14)}9.5</span><span>2008–2013</span><span>5 seasons</span><span>Crime, Drama</span></div>
  <div style="display:flex;gap:12px">
    <div class="cta" style="flex:1;position:relative;flex-direction:column;gap:0;height:56px"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume S1 E3</div><div style="font:600 11.5px Inter;opacity:.7">33 min left</div></div>
    <div class="round" style="width:56px;height:56px">{icon('down',24)}</div>
    <div class="round" style="width:56px;height:56px">{icon('plus',24)}</div>
  </div>
  <div style="margin-top:16px;font:400 15px/1.45 Inter" class="t2">A chemistry teacher diagnosed with inoperable lung cancer turns to manufacturing methamphetamine… <b style="color:#fff">More</b></div>
</div>
<div style="position:absolute;top:640px;left:16px;right:0">
  <div style="display:flex;gap:8px;margin-bottom:14px">
    <span class="chip" style="background:#fff;color:#000">Season 1</span><span class="chip">Season 2</span><span class="chip">Season 3</span><span class="chip">Season 4</span><span class="chip">Season 5</span>
  </div>
  {''.join(f'''<div style="display:flex;gap:12px;align-items:center;margin-bottom:14px;padding-right:16px">
    <div style="width:132px;height:74px;border-radius:10px;flex:none;background:url({still(1,e)}) center/cover;position:relative;overflow:hidden">{'<div style="position:absolute;left:8px;right:8px;bottom:6px">'+progress(0.31)+'</div>' if e==3 else ''}</div>
    <div style="flex:1;min-width:0"><div style="font:600 15px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{e}. {n}</div><div style="font:500 13px Inter" class="t3">{m}</div></div>
    <div style="color:var(--t2)">{icon('down',24)}</div></div>''' for e, n, m in [(1,"Pilot","58m&nbsp;&nbsp; Watched"),(2,"Cat's in the Bag...","48m&nbsp;&nbsp; Watched"),(3,"...And the Bag's in the River","33m left")])}
</div>
""")

# ---------------------------------------------------------------- B: Up Next
page("B1-upnext-home", f"""
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;align-items:center;justify-content:space-between">
  <div class="display" style="font-size:38px">Up next</div>
  <div style="width:36px;height:36px;border-radius:18px;background:#2f6fde;display:grid;place-items:center;font:700 16px Inter">M</div>
</div>
<div style="position:absolute;top:116px;left:16px;right:16px">
  <div style="height:228px;border-radius:18px;background:url({still(1,4)}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">
    <div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,0) 40%,rgba(0,0,0,.75))"></div>
    <img class="logo" src="{logo('tt0903747')}" style="position:absolute;left:16px;bottom:56px;height:52px;max-width:200px;object-fit:contain;object-position:left bottom">
    <div style="position:absolute;left:16px;bottom:16px;font:600 14px Inter"><b>S1 E4</b><span style="color:rgba(255,255,255,.75)">&nbsp; Cancer Man&nbsp;&nbsp;46m&nbsp;&nbsp; Ready offline</span></div>
  </div>
  <div class="cta" style="margin-top:12px">{icon('play',20)}Play next episode</div>
</div>
<div style="position:absolute;top:440px;left:16px;right:0">
  <div class="display" style="font-size:24px;margin-bottom:12px">Keep watching</div>
  <div style="display:flex;gap:12px">
    {''.join(f'''<div style="width:168px;flex:none"><div style="height:95px;border-radius:12px;background:url({img}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px"><div style="position:absolute;left:8px;right:8px;bottom:7px">{progress(f)}</div></div>
    <div style="margin-top:7px;font:600 13px Inter">{t}</div><div style="font:500 12px Inter" class="t2">{s}</div></div>''' for img, t, s, f in [(bg('tt1375666','medium'), "Inception", "1h 20m left", .46), (bg('tt5875444','medium'), "Slow Horses", "S5 E2&nbsp;&nbsp; 31m left", .3), (bg('tt0944947','medium'), "Game of Thrones", "S2 E7&nbsp;&nbsp; 12m left", .8)])}
  </div>
</div>
<div style="position:absolute;top:640px;left:16px;right:0">
  <div style="display:flex;align-items:center;gap:6px;margin-bottom:12px"><span class="display" style="font-size:24px">Popular shows</span><span class="t3">{icon('chev',16)}</span></div>
  <div style="display:flex;gap:10px">{''.join(f'<div class="poster" style="width:116px;height:174px;flex:none;background-image:url({poster(i)})"></div>' for i in TOP_SHOWS)}</div>
</div>
{tabbar(0)}
""")

page("B2-upnext-title", f"""
<div style="position:absolute;inset:0 0 auto 0;height:330px;background:url({bg('tt0903747')}) 60% 30%/cover;filter:saturate(.9)"></div>
<div style="position:absolute;inset:0 0 auto 0;height:330px;background:linear-gradient(180deg,rgba(13,13,18,.5),rgba(13,13,18,.35) 40%,var(--ink))"></div>
<div style="position:absolute;top:58px;left:16px"><div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45);border-color:rgba(255,255,255,.12)">{icon('back',20)}</div></div>
<div style="position:absolute;top:196px;left:16px;right:16px;display:flex;gap:14px;align-items:flex-end">
  <div class="poster" style="width:104px;height:156px;flex:none;background-image:url({poster('tt0903747')});box-shadow:0 10px 30px rgba(0,0,0,.5)"></div>
  <div style="padding-bottom:4px">
    <div class="display" style="font-size:34px">Breaking Bad</div>
    <div style="font:600 13.5px Inter;margin-top:6px" class="t2">{icon('star',12,'vertical-align:-1px')} 9.5&nbsp;&nbsp; 2008–2013&nbsp;&nbsp; Crime, Drama</div>
    <div style="display:flex;gap:10px;margin-top:12px;color:#fff">{icon('plus',22)}<span style="width:8px"></span>{icon('down',22)}<span style="width:8px"></span>{icon('tv',22)}<span style="width:8px"></span>{icon('share',22)}</div>
  </div>
</div>
<div style="position:absolute;top:378px;left:16px;right:16px;font:400 14.5px/1.45 Inter" class="t2">A chemistry teacher diagnosed with inoperable lung cancer turns to cooking meth with a former student to secure his family's future. <b style="color:#fff">More</b></div>
<div style="position:absolute;top:470px;left:16px;right:0">
  <div style="display:flex;align-items:center;gap:6px;margin-bottom:12px"><span class="display" style="font-size:24px">Season 1</span><span class="t3">{icon('chevdown',16)}</span><span class="t3" style="font:500 13px Inter;margin-left:6px">7 episodes</span></div>
  <div style="display:flex;gap:12px">
    {''.join(f'''<div style="width:272px;flex:none"><div style="height:153px;border-radius:14px;background:url({still(1,e)}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">{'<div style="position:absolute;left:10px;right:10px;bottom:9px">'+progress(.31)+'</div>' if e==3 else ''}{'<div style="position:absolute;top:8px;left:8px;padding:3px 8px;border-radius:10px;background:rgba(0,0,0,.6);font:600 11px Inter">Watched</div>' if e<3 else ''}</div>
    <div style="margin-top:8px;font:600 14.5px Inter">{e}. {n}</div><div style="font:400 13px/1.4 Inter;margin-top:3px" class="t2">{d}</div></div>''' for e, n, d in [(3,"...And the Bag's in the River","Walter fights with Jesse over his drug use, causing him to leave Walter alone with their captive."),(4,"Cancer Man","Walter finally tells his family that he has cancer. Meanwhile, the DEA believes…"),(5,"Gray Matter","")])}
  </div>
</div>
<div style="position:absolute;left:0;right:0;bottom:0;height:140px;background:linear-gradient(transparent,var(--ink) 30%)"></div>
<div style="position:absolute;left:16px;right:16px;bottom:44px;display:flex;gap:12px;align-items:center">
  <div class="cta" style="flex:1;height:58px;flex-direction:column;gap:0"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume S1 E3</div><div style="font:600 11.5px Inter;opacity:.7">33 min left</div></div>
</div>
<div class="home-indicator"></div>
""")

# ---------------------------------------------------------------- C: Ambient
page("C1-ambient-home", f"""
<div style="position:absolute;inset:0;background:url({bg('tt33043892')}) 46% center/cover"></div>
<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(10,6,8,.35) 0,rgba(10,6,8,0) 18%,rgba(10,6,8,.0) 40%,rgba(40,8,10,.82) 70%,#120709 100%)"></div>
<div style="position:absolute;top:60px;left:0;right:0;display:flex;justify-content:center;gap:6px">
  <div style="display:flex;gap:2px;padding:4px;border-radius:20px;background:rgba(0,0,0,.35);backdrop-filter:blur(16px);border:1px solid rgba(255,255,255,.1);font:600 14px Inter">
    <span style="padding:7px 14px;border-radius:16px;background:rgba(255,255,255,.18)">For you</span><span style="padding:7px 14px" class="t2">Shows</span><span style="padding:7px 14px" class="t2">Movies</span><span style="padding:7px 14px" class="t2">Anime</span>
  </div>
</div>
<div style="position:absolute;left:16px;right:16px;bottom:150px">
  <img class="logo" src="{logo('tt33043892')}" style="height:110px;max-width:320px;object-fit:contain;object-position:left bottom;display:block">
  <div style="font:600 14px Inter;margin:12px 0 8px;color:rgba(255,255,255,.85)">{icon('star',14,'vertical-align:-2px')} 9.0&nbsp;&nbsp; 2025–&nbsp;&nbsp; Crime, Drama&nbsp;&nbsp; <span class="t2">#2 in Shows</span></div>
  <div style="font:400 15px/1.45 Inter;color:rgba(255,255,255,.78);max-width:380px">Dexter Morgan wakes up from a coma and heads to New York City, set on finding Harrison and making things right.</div>
  <div style="display:flex;gap:12px;margin-top:18px;align-items:center">
    <div class="cta" style="width:150px">{icon('play',20)}Play</div>
    <div class="round" style="background:rgba(255,255,255,.14);border-color:rgba(255,255,255,.14)">{icon('plus',22)}</div>
    <div class="round" style="background:rgba(255,255,255,.14);border-color:rgba(255,255,255,.14)">{icon('chev',22)}</div>
  </div>
</div>
<div style="position:absolute;right:10px;top:380px;display:flex;flex-direction:column;gap:6px">{''.join(f'<i style="width:4px;height:{22 if k==1 else 8}px;border-radius:2px;background:{"#fff" if k==1 else "rgba(255,255,255,.35)"}"></i>' for k in range(6))}</div>
<div style="position:absolute;left:0;right:0;bottom:100px;height:30px;display:flex;justify-content:center;font:600 12px Inter" class="t2">Swipe up for the next one</div>
{tabbar(0)}
""")

page("C2-ambient-title", f"""
<div style="position:absolute;inset:0;background:radial-gradient(120% 60% at 50% 0%,#3a3a12 0%,#1e2410 40%,#0d0d12 75%)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;justify-content:space-between">
  <div class="round" style="width:44px;height:44px;background:rgba(255,255,255,.1);border-color:rgba(255,255,255,.1)">{icon('back',20)}</div>
  <div class="round" style="width:44px;height:44px;background:rgba(255,255,255,.1);border-color:rgba(255,255,255,.1)">{icon('share',20)}</div>
</div>
<div style="position:absolute;top:110px;left:0;right:0;display:flex;flex-direction:column;align-items:center">
  <div class="poster" style="width:196px;height:294px;background-image:url({poster('tt0903747')});border-radius:14px;box-shadow:0 24px 60px rgba(0,0,0,.6),0 0 80px rgba(200,200,60,.15)"></div>
  <div class="display" style="font-size:40px;margin-top:20px">Breaking Bad</div>
  <div style="font:600 14px Inter;margin-top:8px;color:rgba(255,255,255,.8)">{icon('star',13,'vertical-align:-1px')} 9.5&nbsp;&nbsp; 2008–2013&nbsp;&nbsp; 5 seasons&nbsp;&nbsp; Crime, Drama</div>
</div>
<div style="position:absolute;top:510px;left:16px;right:16px">
  <div style="display:flex;gap:12px">
    <div class="cta" style="flex:1;flex-direction:column;gap:0;height:56px"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume S1 E3</div><div style="font:600 11.5px Inter;opacity:.7">33 min left</div></div>
    <div class="round" style="width:56px;height:56px;background:rgba(255,255,255,.1)">{icon('down',24)}</div>
    <div class="round" style="width:56px;height:56px;background:rgba(255,255,255,.1)">{icon('plus',24)}</div>
  </div>
  <div style="display:flex;gap:22px;margin:22px 0 14px;font:700 15px Inter;border-bottom:1px solid var(--hair)">
    <span style="padding-bottom:10px;border-bottom:2px solid #fff">Episodes</span><span class="t3">About</span><span class="t3">More like this</span>
  </div>
  {''.join(f'''<div style="display:flex;gap:12px;align-items:center;margin-bottom:12px"><div style="width:112px;height:63px;border-radius:9px;flex:none;background:url({still(1,e)}) center/cover"></div><div><div style="font:600 14.5px Inter">{e}. {n}</div><div style="font:500 12.5px Inter" class="t3">{m}</div></div></div>''' for e, n, m in [(1,"Pilot","58m&nbsp;&nbsp; Watched"),(2,"Cat's in the Bag...","48m&nbsp;&nbsp; Watched"),(3,"...And the Bag's in the River","33m left")])}
</div>
{tabbar(0)}
""")

# ================================================================ Chosen: "Marquee Up Next"
AVATAR = '<div style="width:36px;height:36px;border-radius:18px;background:#2f6fde;display:grid;place-items:center;font:700 16px Inter">M</div>'
def header(title):
    return f'<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;align-items:center;justify-content:space-between"><div class="display" style="font-size:36px">{title}</div>{AVATAR}</div>'
def row_title(t, link=False):
    chev = f'<span class="t3" style="margin-left:4px">{icon("chev",15)}</span>' if link else ""
    return f'<div style="display:flex;align-items:center;margin-bottom:12px"><span class="display" style="font-size:24px">{t}</span>{chev}</div>'
def keep_card(img, t, line, frac, w=210, h=118):
    bar = f'<div style="position:absolute;left:8px;right:8px;bottom:7px">{progress(frac)}</div>' if frac else ""
    return f'''<div style="width:{w}px;flex:none"><div style="height:{h}px;border-radius:12px;background:url({img}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">{bar}</div>
    <div style="margin-top:7px;font:600 13.5px Inter">{t}</div><div style="font:500 12.5px Inter" class="t2">{line}</div></div>'''
def ranked(n, i):
    return f'''<div style="position:relative;width:150px;height:174px;flex:none"><div class="display" style="position:absolute;left:-4px;bottom:-14px;font-size:150px;font-weight:900;color:transparent;-webkit-text-stroke:2px rgba(255,255,255,.55);line-height:1">{n}</div>
    <div class="poster" style="position:absolute;right:0;top:0;width:110px;height:165px;background-image:url({poster(i)});box-shadow:-8px 0 20px rgba(0,0,0,.5)"></div></div>'''

page("M1-home-returning", f"""
{header('Home')}
<div style="position:absolute;top:116px;left:16px;right:16px">
  <div style="height:216px;border-radius:18px;background:url({still(1,4)}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">
    <div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,0) 35%,rgba(0,0,0,.8))"></div>
    <img class="logo" src="{logo('tt0903747')}" style="position:absolute;left:16px;bottom:44px;height:50px;max-width:190px;object-fit:contain;object-position:left bottom">
    <div style="position:absolute;left:16px;bottom:15px;font:600 14px Inter"><b>S1 E4</b><span style="color:rgba(255,255,255,.78)">&nbsp; Cancer Man&nbsp;&nbsp; 46m&nbsp;&nbsp; Ready offline</span></div>
  </div>
  <div class="cta" style="margin-top:12px">{icon('play',20)}Play next episode</div>
</div>
<div style="position:absolute;top:420px;left:16px;right:0">
  {row_title('Keep watching')}
  <div style="display:flex;gap:12px">{keep_card(bg('tt1375666','medium'),'Inception','1h 20m left',.46)}{keep_card(bg('tt5875444','medium'),'Slow Horses','<b style="color:rgba(255,255,255,.85)">S5 E2</b>&nbsp; 31m left',.3)}{keep_card(bg('tt0944947','medium'),'Game of Thrones','<b style="color:rgba(255,255,255,.85)">S2 E7</b>&nbsp; 12m left',.8)}</div>
</div>
<div style="position:absolute;top:646px;left:16px;right:0">
  {row_title('Top 10 shows', True)}
  <div style="display:flex;gap:4px">{ranked(1,TOP_SHOWS[0])}{ranked(2,TOP_SHOWS[1])}{ranked(3,TOP_SHOWS[2])}</div>
</div>
{tabbar(0)}
""")

page("M2-home-new-viewer", f"""
<div style="position:absolute;inset:0 0 auto 0;height:590px;background:url({bg('tt5875444')}) 58% 20%/cover"></div>
<div style="position:absolute;inset:0 0 auto 0;height:590px;background:linear-gradient(180deg,rgba(13,13,18,.55) 0,rgba(13,13,18,0) 22%,rgba(13,13,18,0) 45%,rgba(13,13,18,.86) 80%,var(--ink) 100%)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;align-items:center;justify-content:space-between"><div class="display" style="font-size:36px">Home</div>{AVATAR}</div>
<div style="position:absolute;top:380px;left:16px;right:16px">
  <img class="logo" src="{logo('tt5875444')}" style="height:84px;max-width:280px;object-fit:contain;object-position:left bottom;display:block;filter:drop-shadow(0 4px 14px rgba(0,0,0,.5))">
  <div style="display:flex;gap:14px;align-items:center;margin:12px 0 16px;font:600 14px Inter;color:rgba(255,255,255,.85)">
    <span style="display:flex;gap:4px;align-items:center">{icon('star',14)}8.4</span><span>2022–</span><span>Drama, Thriller</span><span class="t2">#6 in Shows</span>
  </div>
  <div style="display:flex;gap:12px;align-items:center">
    <div class="cta" style="width:160px">{icon('play',20)}Play</div>
    <div class="round">{icon('plus',22)}</div>
    <div style="flex:1"></div>
    <div style="display:flex;gap:6px"><i style="width:18px;height:6px;border-radius:3px;background:#fff"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i><i style="width:6px;height:6px;border-radius:3px;background:var(--t3)"></i></div>
  </div>
</div>
<div style="position:absolute;top:612px;left:16px;right:0">
  {row_title('Top 10 shows', True)}
  <div style="display:flex;gap:4px">{ranked(1,TOP_SHOWS[0])}{ranked(2,TOP_SHOWS[1])}{ranked(3,TOP_SHOWS[2])}</div>
</div>
{tabbar(0)}
""")

def ep_row(e, n, line, frac=None, glyph="down"):
    bar = f'<div style="position:absolute;left:7px;right:7px;bottom:6px">{progress(frac)}</div>' if frac else ""
    g = icon('downfill', 26, 'color:var(--success)') if glyph == "done" else icon('down', 26)
    return f'''<div style="display:flex;gap:12px;align-items:center;height:80px;padding-right:16px">
    <div style="width:122px;height:69px;border-radius:9px;flex:none;background:url({still(1,e)}) center/cover;position:relative;overflow:hidden;outline:1px solid var(--hair);outline-offset:-1px">{bar}</div>
    <div style="flex:1;min-width:0"><div style="font:600 15px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{e}. {n}</div><div style="font:500 13px Inter;margin-top:2px" class="t2">{line}</div></div>
    <div style="width:44px;height:44px;display:grid;place-items:center;color:rgba(255,255,255,.75)">{g}</div></div>'''

def title_top(backdrop, pos):
    glass = 'class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45);backdrop-filter:blur(10px);border-color:rgba(255,255,255,.12)"'
    return f'''<div style="position:absolute;inset:0 0 auto 0;height:450px;background:url({backdrop}) {pos}/cover"></div>
<div style="position:absolute;inset:0 0 auto 0;height:450px;background:linear-gradient(180deg,rgba(13,13,18,.45) 0,rgba(13,13,18,0) 25%,rgba(13,13,18,.25) 58%,var(--ink) 100%)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;justify-content:space-between">
  <div {glass}>{icon('back',20)}</div>
  <div style="display:flex;gap:10px"><div {glass}>{icon('tv',20)}</div><div {glass}>{icon('share',20)}</div><div {glass}><span style="font:800 16px Inter;letter-spacing:1px">···</span></div></div>
</div>'''

page("M3-title-series", f"""
{title_top(bg('tt0903747'), '62% 30%')}
<div style="position:absolute;top:300px;left:16px;right:16px">
  <img class="logo" src="{logo('tt0903747')}" style="height:84px;max-width:250px;object-fit:contain;object-position:left bottom;display:block">
  <div style="display:flex;gap:14px;margin:10px 0 16px;font:600 14px Inter;color:rgba(255,255,255,.85)"><span style="display:flex;gap:4px;align-items:center">{icon('star',14)}9.5</span><span>2008–2013</span><span>5 seasons</span><span>Crime, Drama</span></div>
  <div style="display:flex;gap:12px">
    <div class="cta" style="flex:1;flex-direction:column;gap:0;height:56px"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume S1 E3</div><div style="font:600 11.5px Inter;opacity:.72">33m left</div></div>
    <div class="round" style="width:56px;height:56px">{icon('down',24)}</div>
    <div class="round" style="width:56px;height:56px">{icon('plus',24)}</div>
  </div>
  <div style="margin-top:14px;font:400 15px/1.45 Inter" class="t2">A chemistry teacher diagnosed with inoperable lung cancer turns to cooking meth with a former student… <b style="color:#fff">More</b></div>
</div>
<div style="position:absolute;top:596px;left:16px;right:0">
  <div style="display:flex;gap:8px;margin-bottom:6px;white-space:nowrap">
    <span class="chip" style="background:#fff;color:#000">Season 1</span><span class="chip">Season 2</span><span class="chip">Season 3</span><span class="chip">Season 4</span><span class="chip">Season 5</span>
  </div>
  {ep_row(1,"Pilot","58m&nbsp;&nbsp; Watched", glyph="done")}
  {ep_row(2,"Cat's in the Bag...","48m&nbsp;&nbsp; Watched", glyph="done")}
  {ep_row(3,"...And the Bag's in the River","33m left", .31)}
  {ep_row(4,"Cancer Man","48m&nbsp;&nbsp; Downloaded", glyph="done")}
</div>
""")

page("M4-title-movie", f"""
{title_top(bg('tt1375666'), 'center 40%')}
<div style="position:absolute;top:310px;left:16px;right:16px">
  <img class="logo" src="{logo('tt1375666')}" style="height:70px;max-width:280px;object-fit:contain;object-position:left bottom;display:block">
  <div style="display:flex;gap:14px;margin:12px 0 16px;font:600 14px Inter;color:rgba(255,255,255,.85)"><span style="display:flex;gap:4px;align-items:center">{icon('star',14)}8.8</span><span>2010</span><span>2h 28m</span><span>Sci-Fi, Action</span></div>
  <div style="display:flex;gap:12px">
    <div class="cta" style="flex:1;flex-direction:column;gap:0;height:56px"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume</div><div style="font:600 11.5px Inter;opacity:.72">1h 20m left</div></div>
    <div class="round" style="width:56px;height:56px;color:var(--success)">{icon('downfill',26)}</div>
    <div class="round" style="width:56px;height:56px">{icon('check',24)}</div>
  </div>
  <div style="margin-top:10px;font:500 13px Inter" class="t2">Downloaded&nbsp;&nbsp; In your Watchlist</div>
  <div style="margin-top:16px;font:400 15px/1.45 Inter" class="t2">A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea into the mind of a CEO. <b style="color:#fff">More</b></div>
</div>
<div style="position:absolute;top:620px;left:16px;right:0">
  {row_title('Cast &amp; crew')}
  <div style="display:flex;gap:16px">{''.join(f'<div style="width:78px;text-align:center"><div style="width:72px;height:72px;margin:0 auto;border-radius:36px;background:var(--surface);display:grid;place-items:center;font:600 20px Inter;color:var(--t2)">{i}</div><div style="font:500 12.5px Inter;margin-top:6px">{n}</div><div style="font:500 11px Inter" class="t3">{r}</div></div>' for i, n, r in [("LD","Leonardo DiCaprio","Cobb"),("JG","Joseph Gordon-Levitt","Arthur"),("EP","Elliot Page","Ariadne"),("TH","Tom Hardy","Eames")])}</div>
</div>
<div style="position:absolute;top:822px;left:16px;right:0">{row_title('More like this')}<div style="display:flex;gap:10px">{''.join(f'<div class="poster" style="width:104px;height:156px;flex:none;background-image:url({poster(i)})"></div>' for i in ["tt0816692","tt0468569","tt0137523","tt0133093"])}</div></div>
""")

def dl_row(img, title, line, right, frac=None, poster_img=True):
    bar = f'<div style="margin-top:8px;width:210px">{progress(frac)}</div>' if frac is not None else ""
    art = f'<div class="poster" style="width:52px;height:78px;flex:none;background-image:url({img})"></div>' if poster_img else f'<div style="width:104px;height:58px;border-radius:9px;flex:none;background:url({img}) center/cover"></div>'
    return f'''<div style="display:flex;gap:12px;align-items:center;padding:8px 16px 8px 0">{art}
    <div style="flex:1;min-width:0"><div style="font:600 15px Inter">{title}</div><div style="font:500 13px Inter;margin-top:2px" class="t2">{line}</div>{bar}</div>{right}</div>'''
PLAYB = f'<div style="width:44px;height:44px;border-radius:22px;background:var(--elevated);display:grid;place-items:center">{icon("play",18)}</div>'
PAUSEB = '<div style="width:44px;height:44px;border-radius:22px;background:var(--elevated);display:grid;place-items:center"><div style="display:flex;gap:4px"><i style="width:4px;height:14px;background:#fff;border-radius:1px"></i><i style="width:4px;height:14px;background:#fff;border-radius:1px"></i></div></div>'

page("M5-my-stuff", f"""
{header('My Stuff')}
<div style="position:absolute;top:118px;left:16px;right:16px;height:40px;border-radius:20px;background:var(--surface);border:1px solid var(--hair);display:flex;padding:3px;font:600 14px Inter">
  <div style="flex:1;border-radius:17px;background:var(--elevated);display:grid;place-items:center">Downloads</div><div style="flex:1;display:grid;place-items:center" class="t2">Watchlist</div><div style="flex:1;display:grid;place-items:center" class="t2">History</div>
</div>
<div style="position:absolute;top:180px;left:16px;right:0">
  <div class="display" style="font-size:24px;margin-bottom:4px">Ready offline</div>
  {dl_row(poster('tt1375666'),'Inception','Movie&nbsp;&nbsp; 2.6 GB&nbsp;&nbsp; 1h 20m left', PLAYB)}
  {dl_row(poster('tt0903747'),'Breaking Bad','Next: <b style="color:#fff">S1 E4</b>&nbsp; 3 episodes, 4.2 GB', f'<div style="display:flex;gap:6px;align-items:center">{PLAYB}<span class="t3">{icon("chev",16)}</span></div>')}
  <div class="display" style="font-size:24px;margin:18px 0 4px">Downloading</div>
  {dl_row(still(1,5),'S1 E5&nbsp; Gray Matter','640 MB of 1.4 GB&nbsp;&nbsp; 6 min left', PAUSEB, .45, poster_img=False)}
  {dl_row(still(1,6),"S1 E6&nbsp; Crazy Handful of Nothin'",'Waiting for Wi-Fi', PAUSEB, 0, poster_img=False)}
</div>
<div style="position:absolute;top:640px;left:16px;right:16px;padding:14px 16px;border-radius:14px;background:var(--surface);border:1px solid var(--hair)">
  <div style="display:flex;justify-content:space-between;font:600 14px Inter"><span>8.2 GB on this iPhone</span><span class="t2">96 GB free</span></div>
  <div style="margin:10px 0 12px">{progress(.08, color='rgba(255,255,255,.85)', track='rgba(255,255,255,.12)', h=6)}</div>
  <div style="display:flex;justify-content:space-between;align-items:center;font:600 14px Inter"><span class="t2">2 watched episodes, 2.8 GB</span><span style="padding:8px 14px;border-radius:16px;background:var(--elevated)">Remove watched</span></div>
</div>
{tabbar(2)}
""")

# ---------------------------------------------------------------- contact sheets
def sheet(name, title, items, cols=3, note=""):
    cells = "".join(f'<figure><img src="{src}"><figcaption>{cap}</figcaption></figure>' for src, cap in items)
    html = f"""<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=block"><style>
body{{margin:0;background:#08080b;color:#fff;font:15px Inter;padding:40px 48px 48px;width:1800px;box-sizing:border-box}}
h1{{font:700 34px Inter;margin:0 0 6px}} p{{color:rgba(255,255,255,.6);margin:0 0 28px;font-size:17px;max-width:1500px}}
.grid{{display:grid;grid-template-columns:repeat({cols},1fr);gap:28px}}
figure{{margin:0}} img{{width:100%;border-radius:22px;display:block;outline:1px solid rgba(255,255,255,.1)}}
figcaption{{margin-top:10px;font:600 16px Inter;color:rgba(255,255,255,.85)}}</style></head>
<body><h1>{title}</h1><p>{note}</p><div class="grid">{cells}</div></body></html>"""
    with open(os.path.join(OUT, "..", f"sheet-{name}.html"), "w") as f:
        f.write(html)
    print("wrote sheet", name)

S = "shots/"
sheet("chosen", "Chosen direction: Marquee Up Next", [
    (S+"M1-home-returning.jpg", "Home, returning viewer: the next episode, one Play"),
    (S+"M2-home-new-viewer.jpg", "Home, new viewer: the marquee hero"),
    (S+"M3-title-series.jpg", "Title page, series: Resume, then the episodes"),
    (S+"M4-title-movie.jpg", "Title page, movie"),
    (S+"M5-my-stuff.jpg", "My Stuff: Ready offline first, Remove watched"),
], cols=5, note="Merge picked by the UI/UX director: B's watch-first Home, A's cinematic title page, C's status-in-text. HTML mockups with real catalog artwork; Barlow Condensed stands in for SF Pro Condensed (it runs narrower).")
sheet("directions", "Three directions explored", [
    (S+"A1-marquee-home.jpg", "A · Marquee: Home"), (S+"A2-marquee-title.jpg", "A · Marquee: title page"),
    (S+"B1-upnext-home.jpg", "B · Up Next: Home"), (S+"B2-upnext-title.jpg", "B · Up Next: title page"),
    (S+"C1-ambient-home.jpg", "C · Ambient: Home"), (S+"C2-ambient-title.jpg", "C · Ambient: title page"),
], cols=6, note="Director's scores: A1 7.5, A2 8.0, B1 8.0, B2 6.3, C1 6.7, C2 7.0.")
