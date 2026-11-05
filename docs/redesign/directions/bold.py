"""Bold visual directions (round 2): Lumière, Noir, Marquee. Home, title page, player each.
Run after build.py (imports its helpers)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build
from build import ICONS, STATUS, TRIM, icon, bg, poster, logo, still, progress, TOP_SHOWS, OUT

FONTS = "@import url('https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;0,6..72,600;1,6..72,400;1,6..72,500&display=block');"

def page(name, body, css="", status=True, landscape=False):
    size = "width:956px;height:440px" if landscape else ""
    html = f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="kit.css"><style>{FONTS} body{{{size}}} {css}</style></head>
<body>{ICONS}{STATUS if status else ''}{body}{TRIM}</body></html>"""
    with open(os.path.join(OUT, name + ".html"), "w") as f:
        f.write(html)
    print("wrote", name)

def tabs(active, accent="#fff", glass=True):
    names = (("home", "Home"), ("search", "Search"), ("stack", "My Stuff"))
    items = "".join(f'<div class="tab" style="{"background:rgba(255,255,255,.14);color:"+accent if i == active else ""}">{icon(n, 24)}<span>{t}</span></div>' for i, (n, t) in enumerate(names))
    return f'<div class="tabbar" style="background:rgba(30,30,34,.55);backdrop-filter:blur(30px) saturate(1.6);-webkit-backdrop-filter:blur(30px) saturate(1.6)">{items}</div><div class="home-indicator"></div>'

AV = '<div style="width:38px;height:38px;border-radius:19px;background:#2f6fde;display:grid;place-items:center;font:700 16px Inter;box-shadow:0 0 0 2px rgba(255,255,255,.25)">M</div>'
PLAYER_FRAME = still(1, 3)

# =================================================================== LUMIÈRE
LUM = """
.ambient{position:absolute;inset:-60px;background-size:cover;background-position:center;filter:blur(60px) saturate(1.8) brightness(.85);transform:scale(1.2)}
.glass{background:rgba(255,255,255,.10);backdrop-filter:blur(24px) saturate(1.6);-webkit-backdrop-filter:blur(24px) saturate(1.6);border:1px solid rgba(255,255,255,.16)}
.lt{font:700 34px/1.05 Inter;letter-spacing:-.025em}
.lh{font:700 21px Inter;letter-spacing:-.015em}
.wbtn{height:52px;border-radius:26px;background:#fff;color:#000;display:flex;align-items:center;justify-content:center;gap:8px;font:700 17px Inter}
.gbtn{width:52px;height:52px;border-radius:26px;display:grid;place-items:center}
"""
page("L1-lumiere-home", f"""
<div class="ambient" style="background-image:url({still(1,4)})"></div>
<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.05),rgba(0,0,0,.2) 50%,rgba(0,0,0,.8) 90%)"></div>
<div style="position:absolute;top:60px;left:20px;right:20px;display:flex;align-items:center;justify-content:space-between"><div class="lt">Home</div>{AV}</div>
<div style="position:absolute;top:118px;left:20px;right:20px;height:330px;border-radius:28px;overflow:hidden;box-shadow:0 30px 80px rgba(0,0,0,.55);background:url({still(1,4)}) center/cover">
  <div style="position:absolute;inset:auto 0 0 0;height:150px;background:linear-gradient(transparent,rgba(0,0,0,.7))"></div>
  <img class="logo" src="{logo('tt0903747')}" style="position:absolute;left:20px;bottom:96px;height:54px;max-width:200px;object-fit:contain;object-position:left bottom">
  <div style="position:absolute;left:20px;bottom:70px;font:600 14px Inter;color:rgba(255,255,255,.85)">Up next&nbsp;&nbsp; <b style="color:#fff">S1 E4</b>&nbsp; Cancer Man</div>
  <div style="position:absolute;left:14px;right:14px;bottom:14px;display:flex;gap:10px">
    <div class="wbtn" style="flex:1;height:46px">{icon('play',18)}Play</div>
    <div class="gbtn glass" style="width:46px;height:46px">{icon('plus',20)}</div>
  </div>
</div>
<div style="position:absolute;top:476px;left:20px;right:0">
  <div class="lh" style="margin-bottom:12px">Keep watching</div>
  <div style="display:flex;gap:12px">
    {''.join(f'''<div style="width:200px;flex:none"><div style="height:112px;border-radius:18px;background:url({img}) center/cover;position:relative;overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,.4)"><div style="position:absolute;left:10px;right:10px;bottom:9px">{progress(f, color="#fff", track="rgba(255,255,255,.3)")}</div></div>
    <div style="margin-top:8px;font:600 14px Inter">{t}</div><div style="font:500 13px Inter;color:rgba(255,255,255,.6)">{l}</div></div>''' for img, t, l, f in [(bg('tt1375666','medium'),"Inception","1h 20m left",.46),(bg('tt5875444','medium'),"Slow Horses","S5 E2&nbsp; 31m left",.3),(bg('tt0944947','medium'),"Game of Thrones","S2 E7",.8)])}
  </div>
</div>
<div style="position:absolute;top:688px;left:20px;right:0">
  <div class="lh" style="margin-bottom:12px">Top 10 shows</div>
  <div style="display:flex;gap:14px;align-items:flex-end">{''.join(f'<div style="display:flex;align-items:flex-end;gap:2px;flex:none"><span style="font:200 96px/0.8 Inter;letter-spacing:-.06em;color:rgba(255,255,255,.9)">{n}</span><div class="poster" style="width:96px;height:144px;border-radius:14px;background-image:url({poster(i)})"></div></div>' for n, i in [(1,TOP_SHOWS[0]),(2,TOP_SHOWS[1]),(3,TOP_SHOWS[2])])}</div>
</div>
{tabs(0)}
""", LUM)

page("L2-lumiere-title", f"""
<div class="ambient" style="background-image:url({bg('tt0903747')})"></div>
<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,0) 0,rgba(0,0,0,.35) 50%,rgba(0,0,0,.75))"></div>
<div style="position:absolute;inset:0 0 auto 0;height:430px;background:url({bg('tt0903747')}) 62% 30%/cover;-webkit-mask-image:linear-gradient(#000 60%,transparent)"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;justify-content:space-between">
  <div class="gbtn glass" style="width:44px;height:44px">{icon('back',20)}</div>
  <div class="glass" style="display:flex;border-radius:22px;height:44px;align-items:center;padding:0 6px">{''.join(f'<div style="width:40px;display:grid;place-items:center">{icon(n,20)}</div>' for n in ["tv","share"])}<div style="width:40px;text-align:center;font:800 16px Inter">···</div></div>
</div>
<div style="position:absolute;top:318px;left:20px;right:20px">
  <img class="logo" src="{logo('tt0903747')}" style="height:84px;max-width:250px;object-fit:contain;object-position:left bottom;display:block">
  <div style="margin:12px 0 18px;font:600 14px Inter;color:rgba(255,255,255,.8)">{icon('star',13,'vertical-align:-1px')} 9.5&nbsp;&nbsp;&nbsp;2008–2013&nbsp;&nbsp;&nbsp;5 seasons&nbsp;&nbsp;&nbsp;Crime, Drama</div>
  <div style="display:flex;gap:10px">
    <div class="wbtn" style="flex:1;height:56px;flex-direction:column;gap:0"><div style="display:flex;gap:8px;align-items:center">{icon('play',20)}Resume S1 E3</div><div style="font:600 11.5px Inter;opacity:.6">33m left</div></div>
    <div class="gbtn glass" style="width:56px;height:56px">{icon('down',24)}</div>
    <div class="gbtn glass" style="width:56px;height:56px">{icon('plus',24)}</div>
  </div>
  <div style="margin-top:16px;font:400 15px/1.45 Inter;color:rgba(255,255,255,.75)">A chemistry teacher diagnosed with inoperable lung cancer turns to cooking meth with a former student… <b style="color:#fff">More</b></div>
</div>
<div style="position:absolute;top:620px;left:20px;right:0">
  <div style="display:flex;gap:8px;margin-bottom:12px">{''.join(f'<span class="glass" style="padding:8px 14px;border-radius:18px;font:600 14px Inter;{"background:#fff;color:#000" if k==1 else ""}">Season {k}</span>' for k in range(1,6))}</div>
  {''.join(f'''<div class="glass" style="display:flex;gap:12px;align-items:center;border-radius:18px;padding:8px;margin:0 20px 10px 0"><div style="width:112px;height:63px;border-radius:12px;background:url({still(1,e)}) center/cover;flex:none;position:relative;overflow:hidden">{'<div style="position:absolute;left:6px;right:6px;bottom:5px">'+progress(.31,color="#fff")+'</div>' if e==3 else ''}</div>
    <div style="flex:1;min-width:0"><div style="font:600 15px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{e}. {n}</div><div style="font:500 13px Inter;color:rgba(255,255,255,.6)">{m}</div></div><div style="padding-right:8px;color:{c}">{icon(g,24)}</div></div>''' for e,n,m,g,c in [(1,"Pilot","58m&nbsp;&nbsp; Watched","downfill","#fff"),(2,"Cat's in the Bag...","48m&nbsp;&nbsp; Watched","downfill","#fff"),(3,"...And the Bag's in the River","33m left","down","rgba(255,255,255,.7)")])}
</div>
""", LUM)

page("L3-lumiere-player", f"""
<div style="position:absolute;inset:0;background:url({PLAYER_FRAME}) center/cover"></div>
<div style="position:absolute;inset:0;background:radial-gradient(120% 80% at 50% 50%,transparent 40%,rgba(0,0,0,.55)),linear-gradient(180deg,rgba(0,0,0,.45),transparent 30%,transparent 60%,rgba(0,0,0,.7))"></div>
<div style="position:absolute;top:22px;left:44px;right:44px;display:flex;align-items:center;gap:14px">
  <div class="gbtn glass" style="width:44px;height:44px">{icon('plus',20,'transform:rotate(45deg)')}</div>
  <div><div style="font:700 17px Inter">Breaking Bad</div><div style="font:500 13px Inter;color:rgba(255,255,255,.7)">S1 E3&nbsp; ...And the Bag's in the River</div></div>
  <div style="flex:1"></div>
  <div class="glass" style="display:flex;border-radius:22px;height:44px;align-items:center;padding:0 6px">{''.join(f'<div style="width:42px;display:grid;place-items:center">{icon(n,20)}</div>' for n in ["captions","tv","sliders"])}</div>
</div>
<div style="position:absolute;top:170px;left:0;right:0;display:flex;justify-content:center;align-items:center;gap:56px">
  <span style="font:600 15px Inter;opacity:.9">−10</span>
  <div class="gbtn glass" style="width:84px;height:84px;border-radius:42px">{icon('play',34)}</div>
  <span style="font:600 15px Inter;opacity:.9">+10</span>
</div>
<div style="position:absolute;left:44px;right:44px;bottom:26px">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
    <div class="glass" style="border-radius:22px;height:44px;padding:0 16px;display:flex;align-items:center;gap:8px;font:600 14px Inter">{icon('stack',16)}Episodes</div>
    <div class="glass" style="border-radius:22px;height:44px;padding:0 16px;display:flex;align-items:center;gap:8px;font:600 14px Inter">Next episode {icon('chev',14)}</div>
  </div>
  <div style="display:flex;align-items:center;gap:14px;font:500 13px Inter;font-variant-numeric:tabular-nums">
    <span>14:52</span><div style="flex:1;height:4px;border-radius:2px;background:rgba(255,255,255,.3);position:relative"><div style="position:absolute;inset:0 69% 0 0;background:#fff;border-radius:2px;box-shadow:0 0 12px rgba(255,255,255,.8)"></div><div style="position:absolute;left:31%;top:-6px;width:16px;height:16px;margin-left:-8px;border-radius:8px;background:#fff"></div></div><span>−33:08</span>
  </div>
</div>
""", LUM + ".status{display:none}", status=False, landscape=True)

# =================================================================== NOIR
NOIR = """
body{background:#000}
.serif{font-family:'Newsreader',serif;font-optical-sizing:auto}
.nt{font:500 42px/1 'Newsreader',serif;letter-spacing:-.02em}
.nh{font:500 24px/1.1 'Newsreader',serif;letter-spacing:-.01em}
.scope{aspect-ratio:2.39/1;background-size:cover;background-position:center}
.hair{border-top:1px solid rgba(255,255,255,.14)}
.wbtn{height:50px;border-radius:25px;background:#f4f1ea;color:#000;display:flex;align-items:center;justify-content:center;gap:8px;font:600 16px Inter}
.obtn{height:50px;border-radius:25px;border:1px solid rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;gap:8px;font:600 15px Inter}
"""
page("N1-noir-home", f"""
<div style="position:absolute;top:60px;left:24px;right:24px;display:flex;align-items:center;justify-content:space-between"><div class="serif" style="font:italic 500 30px 'Newsreader'">SceneBox</div>{AV}</div>
<div style="position:absolute;top:122px;left:0;right:0">
  <div class="scope" style="background-image:url({still(1,4)})"></div>
  <div style="padding:18px 24px 0">
    <div style="font:600 12.5px Inter;color:rgba(255,255,255,.55);margin-bottom:6px">Up next</div>
    <div class="nt">Breaking Bad</div>
    <div style="font:500 15px Inter;color:rgba(255,255,255,.7);margin-top:8px">Season 1, episode 4&nbsp;&nbsp; <span class="serif" style="font-style:italic;font-size:17px;color:#fff">Cancer Man</span>&nbsp;&nbsp; 46 min</div>
    <div style="display:flex;gap:10px;margin-top:18px"><div class="wbtn" style="flex:1">{icon('play',18)}Play episode 4</div><div class="obtn" style="width:50px">{icon('plus',20)}</div></div>
  </div>
</div>
<div style="position:absolute;top:500px;left:24px;right:24px">
  <div class="nh" style="margin-bottom:10px">Keep watching</div>
  {''.join(f'''<div class="hair" style="display:flex;gap:14px;align-items:center;padding:12px 0"><div class="scope" style="width:116px;background-image:url({img});flex:none"></div><div style="flex:1"><div class="serif" style="font:500 19px 'Newsreader'">{t}</div><div style="font:500 13px Inter;color:rgba(255,255,255,.55);margin-top:2px">{l}</div><div style="margin-top:8px">{progress(f, color="#f4f1ea", track="rgba(255,255,255,.18)", h=2)}</div></div></div>''' for img,t,l,f in [(bg('tt1375666','medium'),"Inception","1h 20m left",.46),(bg('tt5875444','medium'),"Slow Horses","Season 5, episode 2",.3)])}
</div>
<div style="position:absolute;top:690px;left:24px;right:24px">
  <div class="nh" style="margin-bottom:6px">Top 10 shows this week</div>
  {''.join(f'''<div class="hair" style="display:flex;gap:16px;align-items:baseline;padding:10px 0"><span class="serif" style="font:400 34px/1 'Newsreader';width:30px;color:rgba(255,255,255,.85)">{n}</span><span style="font:600 16px Inter">{t}</span><span style="margin-left:auto;font:500 13px Inter;color:rgba(255,255,255,.5)">{g}</span></div>''' for n,t,g in [(1,"Nocturne","Crime"),(2,"Dexter: Resurrection","Crime"),(3,"MobLand","Drama")])}
</div>
{tabs(0)}
""", NOIR)

page("N2-noir-title", f"""
<div class="scope" style="position:absolute;top:54px;left:0;right:0;background-image:url({bg('tt0903747')})"></div>
<div style="position:absolute;top:58px;left:16px;right:16px;display:flex;justify-content:space-between">
  <div class="gbtn" style="width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.55);display:grid;place-items:center">{icon('back',20)}</div>
  <div style="display:flex;gap:8px">{''.join(f'<div style="width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.55);display:grid;place-items:center">{icon(n,18)}</div>' for n in ["tv","share"])}</div>
</div>
<div style="position:absolute;top:252px;left:24px;right:24px">
  <div class="nt" style="font-size:50px">Breaking Bad</div>
  <div style="font:500 14px Inter;color:rgba(255,255,255,.6);margin:10px 0 18px">2008–2013&nbsp;&nbsp;&nbsp;5 seasons&nbsp;&nbsp;&nbsp;Crime, Drama&nbsp;&nbsp;&nbsp;{icon('star',12,'vertical-align:-1px')} 9.5</div>
  <div class="serif" style="font:400 18px/1.45 'Newsreader';color:rgba(255,255,255,.82)">A chemistry teacher diagnosed with inoperable lung cancer turns to cooking meth with a former student to secure his family's future.</div>
  <div style="display:flex;gap:10px;margin-top:20px"><div class="wbtn" style="flex:1;flex-direction:column;gap:0;height:56px"><div style="display:flex;gap:8px;align-items:center">{icon('play',18)}Resume episode 3</div><div style="font:600 11.5px Inter;opacity:.55">33 minutes left</div></div><div class="obtn" style="width:56px;height:56px;border-radius:28px">{icon('down',22)}</div><div class="obtn" style="width:56px;height:56px;border-radius:28px">{icon('plus',22)}</div></div>
</div>
<div style="position:absolute;top:592px;left:24px;right:24px">
  <div style="display:flex;gap:20px;align-items:baseline;margin-bottom:6px"><span class="nh">Season 1</span><span style="font:500 14px Inter;color:rgba(255,255,255,.45)">2&nbsp;&nbsp;3&nbsp;&nbsp;4&nbsp;&nbsp;5</span></div>
  {''.join(f'''<div class="hair" style="display:flex;gap:14px;align-items:center;padding:11px 0"><span class="serif" style="font:400 26px/1 'Newsreader';width:22px;color:rgba(255,255,255,{'.35' if w else '.9'})">{e}</span><div class="scope" style="width:104px;background-image:url({still(1,e)});flex:none;opacity:{.55 if w else 1}"></div><div style="flex:1;min-width:0"><div style="font:600 15px Inter;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{n}</div><div style="font:500 13px Inter;color:rgba(255,255,255,.5)">{m}</div></div></div>''' for e,n,m,w in [(1,"Pilot","58 min&nbsp;&nbsp; Watched",True),(2,"Cat's in the Bag...","48 min&nbsp;&nbsp; Watched",True),(3,"...And the Bag's in the River","33 min left",False),(4,"Cancer Man","48 min",False)])}
</div>
""", NOIR)

page("N3-noir-player", f"""
<div style="position:absolute;inset:0;background:#000"></div>
<div class="scope" style="position:absolute;top:22px;bottom:22px;left:50%;transform:translateX(-50%);height:396px;background-image:url({PLAYER_FRAME})"></div>
<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.6),transparent 25%,transparent 55%,rgba(0,0,0,.85))"></div>
<div style="position:absolute;top:24px;left:48px;right:48px;display:flex;align-items:center;gap:22px;font:500 14px Inter">
  {icon('plus',22,'transform:rotate(45deg)')}<div style="flex:1"></div>{icon('captions',22)}{icon('tv',22)}{icon('sliders',22)}
</div>
<div style="position:absolute;top:178px;left:0;right:0;display:flex;justify-content:center;gap:70px;align-items:center;font:500 15px Inter;color:rgba(255,255,255,.85)"><span>10 s back</span>{icon('play',44)}<span>10 s on</span></div>
<div style="position:absolute;left:48px;right:48px;bottom:28px">
  <div style="display:flex;align-items:flex-end;justify-content:space-between;margin-bottom:16px">
    <div><div class="serif" style="font:500 30px/1 'Newsreader'">Breaking Bad</div><div class="serif" style="font:italic 400 17px 'Newsreader';color:rgba(255,255,255,.75);margin-top:4px">Episode 3, ...And the Bag's in the River</div></div>
    <div style="font:600 14px Inter;display:flex;gap:18px"><span>Episodes</span><span>Next episode →</span></div>
  </div>
  <div style="display:flex;align-items:center;gap:14px;font:500 12.5px Inter;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.8)"><span>14:52</span><div style="flex:1;height:2px;background:rgba(255,255,255,.25);position:relative"><div style="position:absolute;inset:0 69% 0 0;background:#f4f1ea"></div><div style="position:absolute;left:31%;top:-5px;width:2px;height:12px;background:#f4f1ea"></div></div><span>33:08 left</span></div>
</div>
""", NOIR, status=False, landscape=True)

# =================================================================== MARQUEE (control): reuse M1/M3, add a player
page("Q3-marquee-player", f"""
<div style="position:absolute;inset:0;background:url({PLAYER_FRAME}) center/cover"></div>
<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.6),transparent 30%,transparent 55%,rgba(0,0,0,.8))"></div>
<div style="position:absolute;top:22px;left:44px;right:44px;display:flex;align-items:center;gap:12px">
  <div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45)">{icon('plus',20,'transform:rotate(45deg)')}</div>
  <div style="font:600 15px Inter">Breaking Bad&nbsp; <span style="color:rgba(255,255,255,.7)">S1 E3</span></div><div style="flex:1"></div>
  {''.join(f'<div class="round" style="width:44px;height:44px;background:rgba(0,0,0,.45)">{icon(n,20)}</div>' for n in ["captions","tv","sliders"])}
</div>
<div style="position:absolute;top:170px;left:0;right:0;display:flex;justify-content:center;gap:56px;align-items:center"><span style="font:700 15px Inter">−10</span><div style="width:84px;height:84px;border-radius:42px;background:var(--accent);color:#000;display:grid;place-items:center">{icon('play',34)}</div><span style="font:700 15px Inter">+10</span></div>
<div style="position:absolute;left:44px;right:44px;bottom:26px">
  <div style="display:flex;justify-content:space-between;align-items:flex-end;margin-bottom:12px"><div class="display" style="font-size:40px">...And the Bag's in the River</div><div class="chip" style="height:44px">Next episode {icon('chev',14)}</div></div>
  <div style="display:flex;align-items:center;gap:14px;font:600 13px Inter"><span>14:52</span><div style="flex:1">{progress(.31, h=5)}</div><span>−33:08</span></div>
</div>
""", "", status=False, landscape=True)

build.sheet("bold", "Bold directions: Lumière, Noir, Marquee", [
    ("shots/L1-lumiere-home.jpg", "Lumière: Home"), ("shots/L2-lumiere-title.jpg", "Lumière: title page"),
    ("shots/N1-noir-home.jpg", "Noir: Home"), ("shots/N2-noir-title.jpg", "Noir: title page"),
    ("shots/M1-home-returning.jpg", "Marquee: Home"), ("shots/M3-title-series.jpg", "Marquee: title page"),
], cols=6, note="Players: shots/L3-lumiere-player.jpg, N3-noir-player.jpg, Q3-marquee-player.jpg")
