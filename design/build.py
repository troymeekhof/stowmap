#!/usr/bin/env python3
"""Builds design/interface.html: the interface design for Stowmap (source of truth for the SwiftUI views).
States: ?s=map | tree | types | largest | scanning | idle.  Icons: Phosphor (fill), inlined."""
import math, os, sys, html

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "icons")

def icon(name, cls=""):
    svg = open(os.path.join(ICON_DIR, f"{name}-fill.svg")).read()
    path = svg[svg.index("<path"):svg.rindex("</svg>")]
    return f'<svg class="i {cls}" viewBox="0 0 256 256" aria-hidden="true">{path}</svg>'

PAL = ["#8C5CFF", "#40D9FF", "#FF7366", "#FFC74D", "#59EBA6", "#FF8CB3", "#4DBFFF", "#B380FF", "#FFD94D", "#73F2B3"]
REST = "rgba(255,255,255,.22)"
CAT = {"Video": "#8C5CFF", "Images": "#40D9FF", "Audio": "#FF8CB3", "Documents": "#FFC74D", "Code & Data": "#59EBA6",
       "Archives & Disk Images": "#FF7366", "Apps & Libraries": "#4DBFFF", "System & Caches": "#B380FF", "Everything Else": REST}

def gb(v):
    if v >= 1000: return f"{v/1000:.2f} TB"
    if v >= 100: return f"{v:.1f} GB"
    if v >= 1: return f"{v:.1f} GB" if v < 10 else f"{v:.1f} GB"
    return f"{v*1000:.0f} MB"

def pct(f):
    return f"{f*100:.1f}%" if f < 0.1 else f"{f*100:.0f}%"

def donut(items, size=320, thick=54, hot=None):
    """items: [(value, color)]. Clockwise from 12 o'clock, 1.4 degree gaps, hovered slice grows 8px."""
    total = sum(v for v, _ in items)
    c = size / 2
    out = [f'<svg class="donut" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    a = 0.0
    for idx, (v, col) in enumerate(items):
        span = v / total * 360
        g = 0.7 if span > 3 else 0
        a0, a1 = a + g, a + span - g
        ro = c - 8 + (8 if idx == hot else 0)
        ri = c - 8 - thick
        def pt(r, ang):
            t = math.radians(ang - 90)
            return c + r * math.cos(t), c + r * math.sin(t)
        x0, y0 = pt(ro, a0); x1, y1 = pt(ro, a1); x2, y2 = pt(ri, a1); x3, y3 = pt(ri, a0)
        large = 1 if (a1 - a0) > 180 else 0
        op = 1 if hot is None or idx == hot else 0.55
        glow = f' filter="url(#glow)"' if idx == hot else ""
        out.append(f'<path d="M{x0:.2f} {y0:.2f}A{ro} {ro} 0 {large} 1 {x1:.2f} {y1:.2f}L{x2:.2f} {y2:.2f}A{ri} {ri} 0 {large} 0 {x3:.2f} {y3:.2f}Z" fill="{col}" opacity="{op}"{glow}/>')
        a += span
    out.append('</svg>')
    return "".join(out)

# ---------- data ----------
FOLDER = [  # name, GB, kind, hidden
    ("Movies", 214.6, "folder", False), ("Library", 96.3, "folder", False), ("Pictures", 81.2, "folder", False),
    ("Developer", 44.9, "folder", False), ("Documents", 31.5, "folder", False), ("Music", 18.4, "folder", False),
    (".Trash", 12.7, "folder", True), ("Downloads", 9.8, "folder", False), (".cache", 4.1, "folder", True),
    (".docker", 2.4, "folder", True), ("Desktop", 2.3, "folder", False),
    ("Screen Recording 2026-11-02.mov", 1.9, "video", False), ("212 small files", 0.014, "small", False),
]
TOTAL = sum(v for _, v, _, _ in FOLDER)
KICON = {"folder": "folder", "video": "film-strip", "small": "files", "image": "image", "zip": "package",
         "code": "code", "audio": "music-notes", "doc": "file-text", "hidden": "eye-slash", "app": "app-window"}

def sidebar(scanning=None, sel="Macintosh HD"):
    vols = [("Internal", [("Macintosh HD", "hard-drive", 0.787, "212.3 GB free of 994.7 GB", True)]),
            ("External", [("Footage SSD", "usb", 0.61, "776.4 GB free of 2 TB", True),
                          ("Archive 8TB", "hard-drives", 0.93, "548.1 GB free of 8 TB", False)]),
            ("Network", [("Studio NAS", "network", 0.48, "18.6 TB free of 36 TB", True)]),
            ("Folders", [("Client Deliveries", "folder", None, "~/Documents/Client Deliveries", True)])]
    h = ['<aside class="side"><div class="lights"><b></b><b></b><b></b></div>',
         f'<div class="brand"><img src="../Resources/icon_preview.png" alt=""><span>Stowmap</span></div><div class="vols">']
    for title, rows in vols:
        h.append(f'<div class="grp">{title}</div>')
        for name, ic, frac, sub, scanned in rows:
            on = " on" if name == sel else ""
            if name == scanning: state = '<span class="spin"></span>'
            elif scanned: state = icon("check-circle", "ok")
            else: state = ""
            col = "#FF6666" if (frac or 0) > 0.92 else ("#FFBF40" if (frac or 0) > 0.82 else "#40D9FF")
            meter = f'<div class="meter"><i style="width:{frac*100:.0f}%;background:{col}"></i></div>' if frac else ""
            h.append(f'<div class="vol{on}"><div class="vic">{icon(ic)}</div><div class="vtx"><div class="vn"><span>{name}</span>{state}</div>{meter}<div class="vs">{sub}</div></div></div>')
    h.append('</div><div class="sfoot"><button class="quiet">' + icon("folder-plus") + 'Scan a Folder…</button>' + icon("gear-six", "gear") + '</div></aside>')
    return "".join(h)

def header(name="Macintosh HD", sub="Startup disk  ·  APFS  ·  782.4 GB used of 994.7 GB  ·  212.3 GB free", frac=0.787, scanned=True, col="#40D9FF"):
    right = ""
    if scanned:
        right = ('<span class="pill g"><i></i>Scanned 2m ago</span><span class="pill c"><i></i>1.4M files</span>'
                 f'<button class="quiet cy">{icon("eye")}Hidden</button>{icon("dots-three-circle","more")}'
                 f'<button class="quiet">{icon("arrow-clockwise")}Rescan</button>')
    meter = f'<div class="meter big"><i style="width:{frac*100:.0f}%;background:{col}"></i></div>' if frac else ""
    return f'<div class="head"><div class="ht"><div class="h1">{name}</div><div class="hs">{sub}</div></div><div class="hr">{right}</div></div>{meter}'

def tabs(active):
    t = [("Map", "chart-donut"), ("Tree", "tree-structure"), ("File Types", "stack"), ("Largest Files", "ranking")]
    return '<div class="tabs">' + "".join(
        f'<div class="tab{" on" if i == active else ""}">{icon(ic)}{n}</div>' for i, (n, ic) in enumerate(t)) + '</div>'

def crumbs(parts):
    h = [f'<div class="crumbs"><span class="ib">{icon("caret-up")}</span>']
    for i, p in enumerate(parts):
        if i: h.append(icon("caret-right", "sep"))
        h.append(f'<span class="{"cur" if i == len(parts)-1 else ""}">{p}</span>')
    h.append(f'<span class="grow"></span><span class="ib">{icon("folder")}</span></div>')
    return "".join(h)

def collector():
    chips = "".join(f'<span class="chip">{n}<em>{s}</em>{icon("x","x")}</span>' for n, s in
                    [(".Trash", "12.7 GB"), ("Proxy Media", "31.8 GB"), ("node_modules", "3.7 GB")])
    return (f'<div class="card coll">{icon("tray","tray")}<div class="ct"><small>Collector</small><b>3 items  ·  48.2 GB</b></div>'
            f'<div class="chips">{chips}</div><button class="quiet">Clear</button><button class="quiet red">{icon("trash")}Move to Trash</button></div>')

def map_state():
    top = FOLDER[:9]; rest = FOLDER[9:]
    items = [(v, PAL[i]) for i, (_, v, _, _) in enumerate(top)] + [(sum(v for _, v, _, _ in rest), REST)]
    hot = 1
    rows = []
    for i, (name, v, kind, hid) in enumerate(FOLDER):
        col = PAL[i] if i < 9 else REST
        f = v / TOTAL
        ic = "folder" if kind == "folder" else KICON[kind]
        tint = "#4DBFFF" if kind == "folder" and not hid else ("#8C5CFF" if kind == "video" else "rgba(255,255,255,.55)")
        tag = f'<span class="tag">{icon("eye-slash")}</span>' if hid else ""
        coll = name == ".Trash"
        acts = (f'<span class="ib{" amber" if coll else " ghost"}">{icon("tray-arrow-down" if not coll else "tray")}</span><span class="ib">{icon("folder" if kind=="folder" else "magnifying-glass")}</span>'
                if kind != "small" else '<span class="ib none"></span><span class="ib">' + icon("folder") + '</span>')
        chev = icon("caret-right", "chev") if kind == "folder" else '<span class="chev"></span>'
        rows.append(f'<div class="row{" hot" if i == hot else ""}{" hid" if hid else ""}"><i class="dot" style="background:{col}"></i>'
                    f'<span class="ric" style="color:{tint}">{icon(ic)}</span><span class="rn"><span>{html.escape(name)}</span>{tag}</span>'
                    f'<div class="meter"><i style="width:{max(2,f*100/ (FOLDER[0][1]/TOTAL)):.0f}%;background:{col}"></i></div>'
                    f'<span class="rs">{gb(v)}</span><span class="rp">{pct(f)}</span>{acts}{chev}</div>')
    hn, hv = FOLDER[hot][0], FOLDER[hot][1]
    center = (f'<div class="center"><div class="cl" style="color:{PAL[hot]}">{hn}</div><div class="cv">{gb(hv)}</div>'
              f'<div class="cs">{pct(hv/TOTAL)} of this folder</div></div>')
    return (header() + tabs(0) + crumbs(["Macintosh HD", "Users", "alex"]) +
            f'<div class="split"><div class="card dcard">{donut(items, hot=hot)}{center}</div>'
            f'<div class="card list">{"".join(rows)}</div></div>' + collector())

def tree_state():
    T = [  # depth, name, GB, kind, open, hidden, frac-of-parent
        (0, "Users", 518.2, "folder", True, False, .66), (1, "alex", 518.2, "folder", True, False, 1.0),
        (2, "Movies", 214.6, "folder", True, False, .41), (3, "Final Cut Projects", 142.8, "folder", False, False, .67),
        (3, "Proxy Media", 31.8, "folder", False, False, .15), (3, "Wedding_Highlights_Master.mov", 24.6, "video", None, False, .11),
        (3, "Drone Raw", 15.4, "folder", False, False, .07),
        (2, "Library", 96.3, "folder", False, False, .19), (2, "Pictures", 81.2, "folder", False, False, .16),
        (2, "Developer", 44.9, "folder", False, False, .09), (2, "Documents", 31.5, "folder", False, False, .06),
        (2, "Music", 18.4, "folder", False, False, .04), (2, ".Trash", 12.7, "folder", False, True, .02),
        (0, "Hidden space", 86.1, "hidden", None, False, .11), (0, "Applications", 74.2, "folder", False, False, .09),
        (0, "Library", 41.8, "folder", False, False, .05), (0, "System", 28.6, "folder", False, False, .04),
        (0, "private", 19.4, "folder", False, True, .02), (0, "opt", 9.7, "folder", False, False, .012),
    ]
    rows = []
    for d, name, v, kind, op, hid, f in T:
        car = f'<span class="car{" open" if op else ""}">{icon("caret-right")}</span>' if op is not None else '<span class="car"></span>'
        ic = KICON.get(kind, "folder")
        tint = "#4DBFFF" if kind == "folder" and not hid else ("#8C5CFF" if kind == "video" else "rgba(255,255,255,.55)")
        tag = f'<span class="tag">{icon("eye-slash")}</span>' if hid else ""
        acts = ('<span class="ib none"></span><span class="ib none"></span>' if kind == "hidden" else
                f'<span class="ib ghost">{icon("tray-arrow-down")}</span><span class="ib">{icon("folder" if kind=="folder" else "magnifying-glass")}</span>')
        hot = " hot" if name == "Proxy Media" else ""
        rows.append(f'<div class="trow{hot}{" hid" if hid else ""}" style="padding-left:{10+d*18}px">{car}<span class="ric" style="color:{tint}">{icon(ic)}</span>'
                    f'<span class="rn{" fw" if kind=="folder" else ""}"><span>{name}</span>{tag}</span>'
                    f'<div class="meter"><i style="width:{max(2,f*100):.0f}%;background:{"#40D9FF" if kind=="folder" else "#B380FF"}"></i></div>'
                    f'<span class="rp">{pct(f)}</span><span class="rs">{gb(v)}</span>{acts}</div>')
    search = f'<div class="search">{icon("magnifying-glass")}<span>Find a file or folder by name</span><span class="grow"></span><button class="quiet">Collapse All</button></div>'
    return header() + tabs(1) + f'<div class="card list tree">{search}{"".join(rows)}</div>'

def types_state():
    cats = [("Video", 238.4, "21,406", "film-strip"), ("Apps & Libraries", 121.7, "412K", "app-window"), ("Images", 98.2, "184K", "image"),
            ("Code & Data", 71.3, "602K", "code"), ("Archives & Disk Images", 52.6, "1,948", "package"), ("System & Caches", 44.1, "96K", "gear-six"),
            ("Audio", 27.9, "12,380", "music-notes"), ("Documents", 16.4, "38K", "file-text"), ("Everything Else", 25.7, "71K", "file")]
    tot = sum(v for _, v, _, _ in cats)
    items = [(v, CAT[n]) for n, v, _, _ in cats]
    legend = "".join(f'<div class="lg"><i class="dot" style="background:{CAT[n]}"></i><span class="ric">{icon(ic)}</span><span class="ln">{n}</span><span class="lc">{c} files</span><span class="rs">{gb(v)}</span></div>'
                     for n, v, c, ic in cats)
    exts = [(".mov", "Video", "9,412", 151.2), (".braw", "Video", "1,204", 58.6), (".dylib", "Apps & Libraries", "31K", 44.8), (".dng", "Images", "22,810", 41.3),
            (".dmg", "Archives & Disk Images", "86", 29.4), (".mp4", "Video", "8,930", 24.1), (".psd", "Images", "1,117", 22.7), (".sqlite", "Code & Data", "2,406", 19.8),
            (".zip", "Archives & Disk Images", "1,502", 17.9), (".wav", "Audio", "6,044", 16.2), (".heic", "Images", "61K", 14.6), (".cache", "System & Caches", "44K", 13.1),
            (".json", "Code & Data", "312K", 9.4), (".pdf", "Documents", "18K", 8.8),
            (".framework", "Apps & Libraries", "2,210", 8.1), (".aif", "Audio", "3,318", 7.6), (".pkg", "Archives & Disk Images", "41", 6.9),
            (".log", "System & Caches", "51K", 5.2), (".cr3", "Images", "4,402", 4.7)]
    rows = "".join(f'<div class="erow"><i class="dot" style="background:{CAT[c]}"></i><span class="en">{e}</span><span class="ec">{c}</span>'
                   f'<div class="meter"><i style="width:{v/exts[0][3]*100:.0f}%;background:{CAT[c]}"></i></div><span class="rp w56">{n}</span><span class="rs">{gb(v)}</span></div>'
                   for e, c, n, v in exts)
    center = f'<div class="center"><div class="cl dim">All files</div><div class="cv">{gb(tot)}</div><div class="cs">312 file types</div></div>'
    return (header() + tabs(2) +
            f'<div class="split"><div class="card dcard col"><div class="dwrap">{donut(items, size=280, thick=48)}{center}</div><div class="legend">{legend}</div></div>'
            f'<div class="card list"><div class="ctitle">By extension</div>{rows}</div></div>')

def largest_state():
    F = [("Wedding_Highlights_Master.mov", "/Users/alex/Movies", 24.6, "film-strip", "#8C5CFF"), ("Docker.raw", "/Users/alex/Library/Containers/com.docker.docker/Data/vms/0/data", 21.3, "file", REST),
         ("A001_C014_1102RT.braw", "/Users/alex/Movies/Drone Raw", 11.8, "film-strip", "#8C5CFF"), ("macOS Installer.dmg", "/Users/alex/Downloads", 9.2, "package", "#FF7366"),
         ("Photos Library.sqlite", "/Users/alex/Pictures/Photos Library.photoslibrary/database", 7.4, "code", "#59EBA6"), ("Lake Michigan Timelapse.mov", "/Users/alex/Movies/Final Cut Projects/Renders", 6.9, "film-strip", "#8C5CFF"),
         ("sleepimage", "/private/var/vm", 6.0, "file", REST), ("Catalog Backup 2026-10.zip", "/Users/alex/Documents/Lightroom", 5.6, "package", "#FF7366"),
         ("Session_Mix_Final.wav", "/Users/alex/Music/Sessions", 4.8, "music-notes", "#FF8CB3"), ("Brand Film v7.prproj.mov", "/Users/alex/Movies/Exports", 4.3, "film-strip", "#8C5CFF"),
         ("iPhone Backup.tar", "/Users/alex/Library/Application Support/MobileSync", 3.9, "package", "#FF7366"), ("Elopement_4K_Grade.mov", "/Users/alex/Movies/Final Cut Projects/Renders", 3.7, "film-strip", "#8C5CFF")]
    rows = "".join(f'<div class="frow{" hot" if i==2 else ""}"><span class="rk">{i+1}</span><span class="ric" style="color:{c}">{icon(ic)}</span>'
                   f'<span class="fn"><b>{n}</b><small>{p}</small></span><div class="meter"><i style="width:{v/F[0][2]*100:.0f}%;background:{c}"></i></div>'
                   f'<span class="rs">{gb(v)}</span><span class="ib">{icon("chart-donut")}</span><span class="ib">{icon("eye")}</span><span class="ib">{icon("magnifying-glass")}</span></div>'
                   for i, (n, p, v, ic, c) in enumerate(F))
    search = f'<div class="search">{icon("funnel")}<span>Filter by name, folder or extension</span><span class="grow"></span><em>250 files  ·  214.8 GB</em></div>'
    return header() + tabs(3) + f'<div class="card list tree">{search}{rows}</div>'

_rid = [0]
def ring(frac, label, sub, spin=False):
    r, c = 83, 95
    L = 2 * math.pi * r
    _rid[0] += 1; gid = f"rg{_rid[0]}"
    sp = f'<circle class="sweep" cx="{c}" cy="{c}" r="{r+13}" fill="none" stroke="#40D9FF" stroke-width="3" stroke-linecap="round" stroke-dasharray="{2*math.pi*(r+13)*.18:.1f} 999" transform="rotate(205 {c} {c})"/>' if spin else ""
    return (f'<div class="ringw"><svg width="216" height="216" viewBox="-13 -13 216 216"><defs><linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient></defs>'
            f'<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="13"/>'
            f'<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="url(#{gid})" stroke-width="13" stroke-linecap="round" stroke-dasharray="{L*frac:.1f} {L:.1f}" transform="rotate(-90 {c} {c})"/>{sp}</svg>'
            f'<div class="center"><div class="cv">{label}</div><div class="cs">{sub}</div></div></div>')

def facts(title, rows):
    return f'<div class="ctitle">{title}</div>' + "".join(f'<div class="fact"><span>{k}</span><b>{v}</b></div>' for k, v in rows)

def scanning_state():
    left = (f'<div class="card hero">{ring(.58, "348.2 GB", "mapped", True)}'
            '<div class="it">Mapping Footage SSD</div>'
            '<div class="ip">You can keep working. Other drives can scan at the same time.</div>'
            '<button class="quiet">Cancel</button></div>')
    paths = ["/Volumes/Footage SSD/2026/11 Lakeshore Wedding/A-Cam/Card 03", "/Volumes/Footage SSD/2026/11 Lakeshore Wedding/Drone/DJI_0412",
             "/Volumes/Footage SSD/2026/10 Brand Film/Proxies", "/Volumes/Footage SSD/2026/10 Brand Film/Audio/Stems",
             "/Volumes/Footage SSD/.Spotlight-V100/Store-V2", "/Volumes/Footage SSD/2026/09 Elopement/B-Cam/Card 01"]
    tick = "".join(f'<div class="tk" style="opacity:{1-i*.15:.2f}">{p}</div>' for i, p in enumerate(paths))
    right = ('<div class="card list plain">' + facts("This scan", [("Mapped so far", "348.2 GB"), ("Files", "862,104"), ("Progress", "58%"), ("Elapsed", "0:41"), ("Folders without access", "0")])
             + f'<div class="ctitle gap">Reading now</div>{tick}</div>')
    return header("Footage SSD", "External  ·  APFS  ·  1.22 TB used of 2 TB  ·  776.4 GB free", .61, False) + f'<div class="split">{left}{right}</div>'

def idle_state():
    left = (f'<div class="card hero">{ring(.93, "93%", "used")}'
            '<div class="it">See what\'s filling Archive 8TB</div>'
            '<div class="ip">Stowmap reads every folder, hidden ones included, and draws the result as a map you can click through.</div>'
            f'<button class="glow">{icon("magnifying-glass")}Scan Archive 8TB</button></div>')
    gets = [("chart-donut", "Map", "The biggest folders as slices. Click one to go inside."),
            ("tree-structure", "Tree", "Every folder as an outline, with search."),
            ("stack", "File Types", "Space by kind and by extension."),
            ("ranking", "Largest Files", "The 250 biggest files on the drive.")]
    g = "".join(f'<div class="get"><span class="gi">{icon(ic)}</span><span><b>{t}</b><small>{d}</small></span></div>' for ic, t, d in gets)
    right = ('<div class="card list plain">' + facts("This drive", [("Capacity", "8 TB"), ("Used", "7.45 TB"), ("Free", "548.1 GB"), ("Format", "Mac OS Extended"), ("Location", "/Volumes/Archive 8TB"), ("Last scanned", "Never")])
             + f'<div class="ctitle gap">What you get</div>{g}</div>')
    return header("Archive 8TB", "External  ·  Mac OS Extended  ·  7.45 TB used of 8 TB  ·  548.1 GB free", .93, False, "#FF6666") + f'<div class="split">{left}{right}</div>'

STATES = {"map": (map_state, None, "Macintosh HD"), "tree": (tree_state, None, "Macintosh HD"), "types": (types_state, None, "Macintosh HD"),
          "largest": (largest_state, None, "Macintosh HD"), "scanning": (scanning_state, "Footage SSD", "Footage SSD"), "idle": (idle_state, None, "Archive 8TB")}

CSS = open(os.path.join(HERE, "interface.css")).read()
pages = "".join(f'<section class="win" data-s="{k}">{sidebar(sc, sel)}<main class="main">{fn()}</main></section>' for k, (fn, sc, sel) in STATES.items())
doc = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Stowmap interface design</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>{CSS}</style></head><body>
<svg width="0" height="0" style="position:absolute"><defs><filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0" stdDeviation="7" flood-color="#40D9FF" flood-opacity=".55"/></filter></defs></svg>
{pages}
<script>const s=new URLSearchParams(location.search).get("s");if(s){{document.body.classList.add("one");document.querySelectorAll(".win").forEach(w=>w.hidden=w.dataset.s!==s)}}</script>
</body></html>'''
open(os.path.join(HERE, "interface.html"), "w").write(doc)
print("wrote interface.html", len(doc))
