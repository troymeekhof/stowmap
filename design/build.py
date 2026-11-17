#!/usr/bin/env python3
"""Builds design/interface.html: the interface design for Stowmap (source of truth for the SwiftUI views).
States: ?s=map | tree | types | largest | scanning | idle | search | duplicates | copy-setup | copy-running | copy-pace | copy-done | check-copy.  Icons: Phosphor (fill), inlined."""
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

DRV = {  # name: (icon, badge colour)
    "Macintosh HD": ("hard-drive", "#40D9FF"), "Footage SSD": ("usb", "#B380FF"), "Archive 8TB": ("hard-drives", "#FFC74D"),
    "Studio NAS": ("network", "#59EBA6"), "Client Deliveries": ("folder", "#FF8CB3")}

def badge(name):
    ic, col = DRV[name]
    return f'<span class="badge"><i style="color:{col}">{icon(ic)}</i>{name}</span>'

def sidebar(sel="Macintosh HD", scans=None, query=None, tools=None, footer=None):
    """sel: selected row name (a drive, "Duplicates", "Copy & Verify" or "Search").
    scans: {drive: (frac or None for a network share, status)}; a drive mapped to "wait" is queued.
    tools: {"Duplicates"|"Copy & Verify": (frac or None, status, tone)}; footer: text of the running Scan All state."""
    scans = scans or {}; tools = tools or {}
    vols = [("Internal", [("Macintosh HD", 0.787, "212.3 GB free of 994.7 GB", True)]),
            ("External", [("Footage SSD", 0.61, "776.4 GB free of 2 TB", True),
                          ("Archive 8TB", 0.93, "548.1 GB free of 8 TB", False)]),
            ("Network", [("Studio NAS", 0.48, "18.6 TB free of 36 TB", True)]),
            ("Folders", [("Client Deliveries", None, "~/Documents/Client Deliveries", True)])]
    h = ['<aside class="side"><div class="lights"><b></b><b></b><b></b></div>',
         '<div class="brand"><img src="../Resources/icon_preview.png" alt=""><span>Stowmap</span></div>']
    if query:
        h.append(f'<div class="sbox on">{icon("magnifying-glass")}<span class="q">{query}</span>{icon("x-circle","clr")}</div>')
    else:
        h.append(f'<div class="sbox">{icon("magnifying-glass")}<span class="q">Search all drives</span><kbd>⌘F</kbd></div>')
    h.append('<div class="tools">')
    for name, ic, idle in [("Duplicates", "copy", "Find matching folders"), ("Copy & Verify", "shield-check", "Copy with checksums")]:
        on = " on" if name == sel else ""
        frac, status, tone = tools.get(name, (None, idle, ""))
        meter = f'<div class="meter work"><i style="width:{frac*100:.0f}%"></i></div>' if frac is not None else ""
        h.append(f'<div class="vol{on}"><div class="vic">{icon(ic)}</div><div class="vtx"><div class="vn"><span>{name}</span></div>{meter}<div class="vs {tone}">{status}</div></div></div>')
    h.append('</div><div class="vols">')
    for title, rows in vols:
        h.append(f'<div class="grp">{title}</div>')
        for name, frac, sub, scanned in rows:
            on = " on" if name == sel else ""
            ic = DRV[name][0]
            sc = scans.get(name)
            if sc == "wait":
                state = ""; sub_h = '<div class="vs">Waiting to scan</div>'
                meter = f'<div class="meter"><i style="width:{frac*100:.0f}%;background:rgba(255,255,255,.3)"></i></div>' if frac else ""
            elif sc:
                p, status = sc
                state = '<span class="spin"></span>'
                meter = (f'<div class="meter scan"><i style="width:{p*100:.0f}%"></i></div>' if p is not None
                         else '<div class="meter scan"><i class="slide" style="width:34%;margin-left:41%"></i></div>')
                sub_h = f'<div class="vs cy">{status}</div>'
            else:
                state = icon("check-circle", "ok") if scanned else ""
                col = "#FF6666" if (frac or 0) > 0.92 else ("#FFBF40" if (frac or 0) > 0.82 else "#40D9FF")
                meter = f'<div class="meter"><i style="width:{frac*100:.0f}%;background:{col}"></i></div>' if frac else ""
                sub_h = f'<div class="vs">{sub}</div>'
            h.append(f'<div class="vol{on}"><div class="vic">{icon(ic)}</div><div class="vtx"><div class="vn"><span>{name}</span>{state}</div>{meter}{sub_h}</div></div>')
    if footer:
        allb = f'<div class="scanall run"><span class="sat">{footer}</span><button class="quiet red sm">{icon("stop")}Stop</button></div>'
    else:
        allb = f'<button class="quiet scanall">{icon("hard-drives")}Scan All Drives</button>'
    h.append(f'</div><div class="sfoot">{allb}<div class="sfr"><button class="quiet">' + icon("folder-plus") + 'Scan a Folder…</button>' + icon("gear-six", "gear") + '</div></div></aside>')
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
        (0, "Users", 520.1, "folder", True, False, .66), (1, "alex", 520.1, "folder", True, False, 1.0),
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

# ---------- 1.3: Search, Duplicates, Copy & Verify ----------
def seg(items, active, cls=""):
    return f'<div class="seg {cls}">' + "".join(f'<span class="{"on" if i == active else ""}">{n}</span>' for i, n in enumerate(items)) + '</div>'

def tool_head(title, sub, right=""):
    return f'<div class="head"><div class="ht"><div class="h1">{title}</div><div class="hs">{sub}</div></div><div class="hr">{right}</div></div>'

def loc(drive, path):
    return f'<span class="loc">{badge(drive)}<small>{html.escape(path)}</small></span>'

def tile(drive):
    ic, col = DRV[drive]
    return f'<div class="vic" style="color:{col}">{icon(ic)}</div>'

def search_state():
    q = "Lakeshore"
    R = [("11 Lakeshore Wedding", "folder", "Footage SSD", "/2026", 212.4), ("11 Lakeshore Wedding", "folder", "Studio NAS", "/Projects/2026", 212.4),
         ("Lakeshore_Highlights_Master.mov", "video", "Macintosh HD", "/Users/alex/Movies/Exports", 24.6),
         ("Lakeshore Wedding Proxies", "folder", "Macintosh HD", "/Users/alex/Movies/Proxy Media", 18.2),
         ("Lakeshore_Ceremony_Multicam.mov", "video", "Footage SSD", "/2026/11 Lakeshore Wedding/Renders", 14.1),
         ("Lakeshore_Drone_Selects.mov", "video", "Footage SSD", "/2026/11 Lakeshore Wedding/Drone", 9.3),
         ("Lakeshore Wedding.fcpbundle", "zip", "Macintosh HD", "/Users/alex/Movies/Final Cut Projects", 6.8),
         ("Lakeshore Gallery Export", "folder", "Client Deliveries", "/2026", 4.2),
         ("Lakeshore_Teaser_60s.mp4", "video", "Client Deliveries", "/2026/Lakeshore Gallery Export", 1.1),
         ("Lakeshore_Audio_Stems.zip", "zip", "Studio NAS", "/Projects/2026/11 Lakeshore Wedding/Audio", 0.842),
         ("Lakeshore Catalog.lrcat", "code", "Macintosh HD", "/Users/alex/Pictures/Lightroom", 0.612),
         ("Lakeshore_Vows_Mix.wav", "audio", "Footage SSD", "/2026/11 Lakeshore Wedding/Audio", 0.318),
         ("Lakeshore Stills Selects", "folder", "Studio NAS", "/Projects/2026/11 Lakeshore Wedding", 0.204),
         ("Lakeshore Shot List.pdf", "doc", "Macintosh HD", "/Users/alex/Documents/Weddings", 0.0024),
         ("Lakeshore Timeline.pdf", "doc", "Macintosh HD", "/Users/alex/Documents/Weddings", 0.0011)]
    TINT = {"folder": "#4DBFFF", "video": "#8C5CFF", "zip": "#FF7366", "code": "#59EBA6", "audio": "#FF8CB3", "doc": "#FFC74D"}
    rows = "".join(
        f'<div class="srow{" hot" if i == 2 else ""}"><span class="sic" style="color:{TINT[k]}">{icon(KICON[k])}</span>'
        f'<span class="fn"><b>{n.replace(q, "<mark>" + q + "</mark>")}</b>{loc(d, p)}</span>'
        f'<div class="meter"><i style="width:{max(2, v / R[0][4] * 100):.0f}%;background:{DRV[d][1]}"></i></div><span class="rs">{gb(v)}</span>'
        f'<span class="ib">{icon("tray-arrow-down")}</span><span class="ib">{icon("chart-donut")}</span><span class="ib">{icon("magnifying-glass")}</span></div>'
        for i, (n, k, d, p, v) in enumerate(R))
    based = ('<div class="based"><b>Based on:</b> scans of Macintosh HD (2m ago), Footage SSD (1h ago), Studio NAS (yesterday) '
             'and Client Deliveries (3d ago). Archive 8TB is not scanned.</div>')
    return (tool_head("Search", "38 results for “lakeshore”  ·  4 drives", seg(["All", "Folders", "Files"], 0)) + based +
            f'<div class="card list tree">{rows}</div>')

def dup_state():
    right = (f'<button class="quiet">{icon("hard-drives")}All drives{icon("caret-down","cd")}</button>'
             f'<button class="quiet">{icon("sliders-horizontal")}Filters{icon("caret-down","cd")}</button>'
             f'<button class="glow sm">{icon("copy")}Find Duplicates</button>')
    SETS = [  # title, [(drive, path, collected)], GB per copy, files, verify state, expanded file sets
        ("11 Lakeshore Wedding", [("Footage SSD", "/2026/11 Lakeshore Wedding", True), ("Studio NAS", "/Projects/2026/11 Lakeshore Wedding", False)], 212.4, "682", ("done",), None),
        ("10 Brand Film", [("Footage SSD", "/2026/10 Brand Film", False), ("Studio NAS", "/Projects/2026/10 Brand Film", False)], 99.6, "522", ("run", .64), None),
        ("Card 03", [("Macintosh HD", "/Users/alex/Movies/Imports/A-Cam Card 03", False), ("Footage SSD", "/2026/11 Lakeshore Wedding/A-Cam/Card 03", False)], 38.9, "6", ("idle",),
         [("A003_C001_1107KT.braw", 6.48), ("A003_C002_1107KT.braw", 6.48), ("A003_C003_1107KT.braw", 7.12), ("A003_C004_1107KT.braw", 6.31)]),
        ("Drone Raw", [("Macintosh HD", "/Users/alex/Movies/Drone Raw", False), ("Studio NAS", "/Projects/2026/11 Lakeshore Wedding/Drone", False)], 15.4, "84", ("idle",), None),
        ("Stems", [("Footage SSD", "/2026/10 Brand Film/Audio/Stems", False), ("Client Deliveries", "/2026/Brand Film/Audio", False)], 4.6, "37", ("idle",), None),
    ]
    out = []
    for title, locs, per, files, ver, exp in SETS:
        ls = "".join(f'<div class="dloc">{badge(d)}<small>{p}</small><span class="ib sm{" amber" if c else ""}">{icon("tray" if c else "tray-arrow-down")}</span></div>' for d, p, c in locs)
        if ver[0] == "done": v = f'<span class="pill g">{icon("seal-check")}Verified identical</span>'
        elif ver[0] == "run": v = f'<div class="vprog"><div class="meter work"><i style="width:{ver[1]*100:.0f}%"></i></div><span class="num">{ver[1]*100:.0f}%</span><button class="quiet sm">Stop</button></div>'
        else: v = f'<button class="quiet">{icon("shield-check")}Verify</button>'
        free = per * (len(locs) - 1)
        fl = ""
        if exp:
            fl = '<div class="dfiles">' + "".join(
                f'<div class="dfile"><span class="ric" style="color:#8C5CFF">{icon("film-strip")}</span><span class="dn">{n}</span>'
                f'<span class="dc">2 copies  ·  {v2:.2f} GB each</span><span class="pill a">Samples match</span><span class="rs">{gb(v2)}</span></div>' for n, v2 in exp) + '</div>'
        out.append(f'<div class="dset{" open" if exp else ""}"><div class="drow"><span class="car{" open" if exp else ""}">{icon("caret-right")}</span>'
                   f'<span class="sic" style="color:#4DBFFF">{icon("folder")}</span><div class="dbody"><b class="dt">{title}</b>{ls}</div>'
                   f'<div class="dstat"><b>{gb(free)} to free</b><small>{files} files  ·  {gb(per)} per copy</small></div>'
                   f'<div class="dver">{v}</div><span class="ib">{icon("prohibit")}</span></div>{fl}</div>')
    chips = f'<span class="chip">11 Lakeshore Wedding<em>on Footage SSD  ·  212.4 GB</em>{icon("x","x")}</span>'
    coll = (f'<div class="card coll">{icon("tray","tray")}<div class="ct"><small>Collector</small><b>1 item  ·  212.4 GB</b></div>'
            f'<div class="chips">{chips}</div><button class="quiet">Clear</button><button class="quiet red">{icon("trash")}Move to Trash</button></div>')
    return (tool_head("Duplicates", "14 matching folders  ·  412.6 GB to free  ·  one copy of everything always stays", right) +
            f'<div class="card list tree dups">{"".join(out)}</div>' + coll)

MODE = lambda i: seg([icon("copy") + "Copy", icon("list-checks") + "Check a Copy"], i, "mode")

def copy_setup_state():
    SRC = [("A-Cam", "/2026/11 Lakeshore Wedding", 148.6, "412 files"), ("B-Cam", "/2026/11 Lakeshore Wedding", 41.2, "186 files"),
           ("Drone", "/2026/11 Lakeshore Wedding", 22.6, "84 files"), ("Footage", "/2026/10 Brand Film", 71.3, "212 files"),
           ("Audio", "/2026/10 Brand Film", 6.4, "96 files"), ("Project Files", "/2026/10 Brand Film", 21.9, "214 files")]
    src = "".join(f'<div class="crow"><span class="sic" style="color:#4DBFFF">{icon("folder")}</span><span class="fn"><b>{n}</b>{loc("Footage SSD", p)}</span>'
                  f'<span class="csz"><b>{gb(v)}</b><small>{c}</small></span><span class="ib ghostx">{icon("x")}</span></div>' for n, p, v, c in SRC)
    left = (f'<div class="card pane"><div class="phead"><b>From</b><span>6 items  ·  312 GB</span><span class="grow"></span><button class="quiet sm">{icon("plus")}Add…</button></div>'
            f'{src}<div class="drop">{icon("tray-arrow-down")}<span>Drop files or folders here</span></div></div>')
    DST = [("Archive 8TB", "/2026", .931, .039, "548.1 GB free", "236.1 GB after this copy"), ("Studio NAS", "/Projects/2026", .483, .009, "18.6 TB free", "18.3 TB after this copy")]
    dst = "".join(f'<div class="dest">{tile(d)}<div class="dtx"><div class="dl1"><b>{d}</b><small>{p}</small></div>'
                  f'<div class="meter two"><i style="width:{u*100:.1f}%"></i><i class="add" style="width:{max(c*100,1.2):.1f}%"></i></div>'
                  f'<div class="dl2"><span>{f}</span><span>{af}</span></div></div><span class="ib ghostx">{icon("x")}</span></div>' for d, p, u, c, f, af in DST)
    dst = f'<div class="dests">{dst}</div>'
    right = (f'<div class="card pane"><div class="phead"><b>To</b><span>2 of 3 destinations</span></div>{dst}'
             f'<div class="drop">{icon("plus-circle")}<span>Add Destination…</span><small>Up to three. Drop a drive or folder here.</small></div></div>')
    def menu(l, v): return f'<div class="opt"><small>{l}</small><button class="quiet">{v}{icon("caret-up-down","cd")}</button></div>'
    def sw(l, on): return f'<div class="opt"><small>{l}</small><span class="sw{" on" if on else ""}"><i></i></span></div>'
    opts = ('<div class="card opts">' + menu("Checksum", "xxHash64") + menu("Verify", "Destination") + menu("If a file exists", "Skip") +
            sw("Include hidden files", False) + sw("Write checksum list (MHL)", True) + '</div>')
    foot = (f'<div class="go"><div class="sum"><b>1,204 files  ·  312 GB to 2 destinations</b><span>Needs 624 GB. Both destinations have room.</span></div>'
            f'<button class="glow xl">{icon("shield-check")}Start Copy</button></div>')
    return (tool_head("Copy &amp; Verify", "Copy to as many as three places and check every file.", MODE(0)) +
            f'<div class="split">{left}{right}</div>' + opts + foot)

def smooth(pts):
    """Catmull-Rom through pts, as cubic beziers."""
    d = [f'M{pts[0][0]:.1f} {pts[0][1]:.1f}']
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, len(pts) - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6); c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(f'C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}')
    return "".join(d)

def speed_series(n=44, end=412, slow=False):
    """Sample copy speeds in MB/s: quick ramp, steady run with small-file dips, ending at `end`."""
    v = []
    for i in range(n):
        t = i / (n - 1)
        base = 405 * (1 - math.exp(-t * 26)) + 16 * math.sin(i * 0.9) + 9 * math.sin(i * 2.3 + 1)
        base -= 150 * math.exp(-((t - .36) / .035) ** 2) + 95 * math.exp(-((t - .71) / .03) ** 2)
        if slow: base = base * (1 - .91 / (1 + math.exp(-(t - .8) * 40)))
        v.append(max(base, 0))
    v[-1] = end; v[-2] = (v[-3] + end) / 2
    return v

def spark(vals, w=574, h=124, vmax=470):
    pad = 7
    _rid[0] += 1; u = _rid[0]
    pts = [(pad + i / (len(vals) - 1) * (w - 2 * pad), h - 6 - v / vmax * (h - 16)) for i, v in enumerate(vals)]
    line = smooth(pts)
    ex, ey = pts[-1]
    grid = "".join(f'<line x1="0" x2="{w}" y1="{y:.1f}" y2="{y:.1f}" stroke="rgba(255,255,255,.06)"/>' for y in (h - 6 - 200 / vmax * (h - 16), h - 6 - 400 / vmax * (h - 16)))
    return (f'<svg class="spark" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs>'
            f'<linearGradient id="spl{u}" x1="0" x2="1" y1="0" y2="0"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient>'
            f'<linearGradient id="spf{u}" x1="0" x2="0" y1="0" y2="1"><stop stop-color="#40D9FF" stop-opacity=".30"/><stop offset="1" stop-color="#8C5CFF" stop-opacity="0"/></linearGradient></defs>'
            f'{grid}<line x1="0" x2="{w}" y1="{h-.5}" y2="{h-.5}" stroke="rgba(255,255,255,.10)"/>'
            f'<path d="{line}L{ex:.1f} {h}L{pts[0][0]:.1f} {h}Z" fill="url(#spf{u})"/>'
            f'<path d="{line}" fill="none" stroke="url(#spl{u})" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="8" fill="rgba(64,217,255,.22)"/><circle cx="{ex:.1f}" cy="{ey:.1f}" r="4" fill="#40D9FF" stroke="#12121a" stroke-width="1.5"/></svg>')

def bigring(copied, verified, center, done=False):
    """260 px box. Outer track r116 w16 = copied (violet to cyan). Inner track r97 w8 = verified (green). Both start at 12 o'clock."""
    S, c, ro, ri = 260, 130, 116, 97
    Lo, Li = 2 * math.pi * ro, 2 * math.pi * ri
    _rid[0] += 1; u = _rid[0]
    oc = "#59E699" if done else f"url(#brg{u})"
    arc = lambda r, w, L, f, col, extra="": (f'<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round" '
                                              f'stroke-dasharray="{L*f:.1f} {L:.1f}" transform="rotate(-90 {c} {c})"{extra}/>') if f > .004 else ""
    return (f'<div class="bigring"><svg width="{S}" height="{S}" viewBox="0 0 {S} {S}"><defs><linearGradient id="brg{u}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient></defs>'
            f'<circle cx="{c}" cy="{c}" r="{ro}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="16"/>'
            f'<circle cx="{c}" cy="{c}" r="{ri}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="8"/>'
            f'{arc(ro, 16, Lo, copied, oc)}{arc(ri, 8, Li, verified, "#59E699")}</svg><div class="center">{center}</div></div>')

def stat(label, value, sub):
    return f'<div class="st"><small>{label}</small><b>{value}</b><span>{sub}</span></div>'

def lane(drive, path, copy, ver, l1, l2, tone=""):
    return (f'<div class="lane">{tile(drive)}<div class="ln2"><b>{drive}</b><small>{path}</small></div>'
            f'<div class="lbars"><div class="meter copy"><i style="width:{copy*100:.0f}%"></i></div><div class="meter ver"><i style="width:{ver*100:.0f}%"></i></div></div>'
            f'<div class="lst"><b class="{tone}">{l1}</b><small>{l2}</small></div></div>')

FILES = [  # name, folder, GB, checksum, state
    ("A003_C013_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 9.84, "9f3a61c2", "ok"),
    ("A003_C012_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 12.1, "04be7d19", "ok"),
    ("A003_C011_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 6.48, "c81e55a0", "ok"),
    ("A003_C010_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 7.12, "", "skip"),
    ("A003_C009_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 3.31, "71d09f4e", "ok"),
    ("A003_C008_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 8.02, "e2a47b36", "ok"),
    ("A003_C007_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 5.57, "5b90c2fd", "ok"),
    ("A003_C006_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 10.4, "38f6a1e7", "ok"),
    ("A003_C005_1107KT.braw", "11 Lakeshore Wedding/A-Cam/Card 03", 4.26, "d4c7b08a", "ok"),
]

def file_rows(rows, wide=True):
    out = []
    for n, p, v, hsh, state in rows:
        mid = f'<small class="fp">{p}</small>' if wide else ""
        if state == "ok": tail = f'<span class="hash">{hsh}</span>{icon("check-circle","okc")}'
        else: tail = f'<span class="hash amber">Skipped</span>{icon("warning","warnc")}'
        out.append(f'<div class="cfile{"" if wide else " narrow"}"><span class="ric" style="color:#8C5CFF">{icon("film-strip")}</span><span class="cn">{n}</span>{mid}<span class="rs">{gb(v)}</span>{tail}</div>')
    return "".join(out)

def copy_running_state(pace=False):
    center = '<div class="pv">41<em>%</em></div><div class="ph">Copying</div>'
    if pace:
        speed, vals = "38", speed_series(end=38, slow=True)
        stats = stat("Copied", "128.4 GB", "of 312 GB") + stat("Files", "480", "of 1,204") + stat("Time left", "1 h 22 min", "at this speed") + stat("Elapsed", "5:31", "started 2:16 PM")
        lanes = (lane("Archive 8TB", "/2026", .41, .38, "Writing 38 MB/s", "Verified 452 of 480") +
                 lane("Studio NAS", "/Projects/2026", .41, .19, "Writing 38 MB/s", "Verified 212 of 480", "amber"))
        note = f'<div class="pace">{icon("warning")}<span>Studio NAS is writing at 38 MB/s. Shares on this connection usually manage about 110. Check the cable or port.</span></div>'
    else:
        speed, vals = "412", speed_series()
        stats = stat("Copied", "128.4 GB", "of 312 GB") + stat("Files", "480", "of 1,204") + stat("Time left", "12 min", "with verifying") + stat("Elapsed", "5:31", "started 2:16 PM")
        lanes = (lane("Archive 8TB", "/2026", .41, .38, "Writing 412 MB/s", "Verified 452 of 480") +
                 lane("Studio NAS", "/Projects/2026", .41, .19, "Writing 398 MB/s", "Verified 212 of 480"))
        note = ""
    hero = (f'<div class="card run">{bigring(.41, .29, center)}<div class="rside">'
            f'<div class="spd"><b>{speed}</b><span>MB/s</span><span class="grow"></span><div class="key"><span><i class="kc"></i>Copied 41%</span><span><i class="kv"></i>Verified 29%</span></div></div>'
            f'{spark(vals)}<div class="stats4">{stats}</div></div></div>')
    now = (f'<div class="cfile now"><span class="ric" style="color:#8C5CFF">{icon("film-strip")}</span><span class="cn">A003_C014_1107KT.braw</span>'
           f'<div class="meter work"><i style="width:62%"></i></div><span class="rs">11.8 GB</span><span class="hash num">62%</span><span class="spin"></span></div>')
    files = (f'<div class="card list files"><div class="ctitle"><span>Files</span><em>480 of 1,204</em></div>{now}{file_rows(FILES)}</div>')
    ctl = f'<button class="quiet">{icon("pause")}Pause</button><button class="quiet red">{icon("stop")}Stop</button>'
    return (tool_head("Copy &amp; Verify", "6 items from Footage SSD to Archive 8TB and Studio NAS  ·  xxHash64  ·  verifying each destination", ctl) +
            hero + note + f'<div class="card lanes">{lanes}</div>' + files)

def copy_done_state():
    center = icon("check-fat", "bigcheck")
    btns = (f'<div class="btns"><button class="quiet">{icon("folder")}Show in Finder</button><button class="quiet">{icon("file-text")}Open Checksum List</button>'
            f'<button class="glow sm">{icon("plus")}New Copy</button></div>')
    hero = (f'<div class="card run done">{bigring(1, 1, center, True)}<div class="rside">'
            '<div class="dt1">All 1,204 files verified</div>'
            '<div class="dp">Every file was read back from Archive 8TB and Studio NAS, and its checksum matches the source.</div>'
            f'<div class="stats4 three">{stat("Copied", "312 GB", "to each destination")}{stat("Time", "14 min 20 s", "copy and verify")}{stat("Average", "362 MB/s", "over the whole copy")}</div>'
            f'{btns}</div></div>')
    def dres(d, p, sub): return (f'<div class="lane res">{tile(d)}<div class="ln2"><b>{d}</b><small>{p}  ·  {sub}</small></div>'
                                 f'<span class="pill g">{icon("seal-check")}Verified</span></div>')
    def cl(n, sub): return (f'<div class="lane res"><div class="vic" style="color:rgba(255,255,255,.7)">{icon("file-text")}</div><div class="ln2"><b>{n}</b><small>{sub}</small></div>'
                            f'<span class="ib">{icon("magnifying-glass")}</span></div>')
    left = ('<div class="card pane res"><div class="ctitle">Destinations</div>' + dres("Archive 8TB", "/2026", "1,204 files, 312 GB") + dres("Studio NAS", "/Projects/2026", "1,204 files, 312 GB") +
            '<div class="ctitle gap">Checksum lists, saved in each destination</div>' + cl("Footage SSD 2026-11-17 1416.mhl", "MHL  ·  xxHash64  ·  1,204 entries") +
            cl("Footage SSD 2026-11-17 1416.txt", "Plain text  ·  one line per file") + '</div>')
    done_files = [("A007_C031_1107KT.braw", "", 5.12, "1c6e9b40", "ok")] + [f for f in FILES if f[4] == "ok"] + [("A003_C004_1107KT.braw", "", 6.31, "ab02f7c3", "ok"), ("A003_C003_1107KT.braw", "", 7.12, "60d1e8b5", "ok")]
    right = f'<div class="card list files"><div class="ctitle"><span>Files</span><em>1,204 verified</em></div>{file_rows(done_files, False)}</div>'
    return tool_head("Copy &amp; Verify", "Finished at 2:30 PM  ·  6 items from Footage SSD to 2 destinations", MODE(0)) + hero + f'<div class="split">{left}{right}</div>'

def check_copy_state():
    def well(label, d, p): return f'<div class="well"><small>{label}</small><div class="wl">{tile(d)}<div class="ln2"><b>{p.rsplit("/", 1)[1]}</b>{loc(d, p.rsplit("/", 1)[0])}</div></div></div>'
    setup = ('<div class="card chk">' + well("Original", "Footage SSD", "/2026/11 Lakeshore Wedding") + f'<span class="arr">{icon("arrow-right")}</span>' +
             well("Copy", "Studio NAS", "/Projects/2026/11 Lakeshore Wedding") +
             f'<div class="well mode"><small>Full compares checksums</small>{seg(["Quick", "Full"], 1)}</div>'
             f'<button class="quiet">{icon("arrow-clockwise")}Check Again</button></div>')
    C = [("676", "Match", "check-circle", "#59E699"), ("4", "Missing from the copy", "minus-circle", "#FF6666"),
         ("2", "Different", "not-equals", "#FFC74D"), ("3", "Only in the copy", "plus-circle", "#40D9FF")]
    counters = '<div class="counters">' + "".join(f'<div class="card cnt"><span class="ci" style="color:{c}">{icon(ic)}</span><b>{n}</b><span>{l}</span></div>' for n, l, ic, c in C) + '</div>'
    def row(ic, col, n, p, detail, v, k="film-strip", tint="#8C5CFF"):
        return (f'<div class="krow"><span class="ks" style="color:{col}">{icon(ic)}</span><span class="ric" style="color:{tint}">{icon(k)}</span><span class="cn">{n}</span>'
                f'<small class="fp">{p}</small><span class="kd" style="color:{col}">{detail}</span><span class="rs">{v}</span><span class="ib">{icon("magnifying-glass")}</span></div>')
    R, A, B = "#FF6666", "#FFC74D", "#40D9FF"
    rows = ('<div class="ctitle"><span>Missing from the copy</span><em>4 files  ·  26.3 GB</em></div>' +
            row("minus-circle", R, "B001_C022_1107KT.braw", "B-Cam/Card 01", "Not on Studio NAS", "8.94 GB") +
            row("minus-circle", R, "B001_C023_1107KT.braw", "B-Cam/Card 01", "Not on Studio NAS", "7.61 GB") +
            row("minus-circle", R, "B001_C024_1107KT.braw", "B-Cam/Card 01", "Not on Studio NAS", "9.42 GB") +
            row("minus-circle", R, "Vows_Lav_02.wav", "Audio", "Not on Studio NAS", "318 MB", "music-notes", "#FF8CB3") +
            '<div class="ctitle gap"><span>Different</span><em>2 files</em></div>' +
            row("not-equals", A, "A003_C009_1107KT.braw", "A-Cam/Card 03", "Incomplete: 2.11 of 3.31 GB", "3.31 GB") +
            row("not-equals", A, "DJI_0412.MP4", "Drone", "Same size, checksum differs", "1.87 GB") +
            '<div class="ctitle gap"><span>Only in the copy</span><em>3 files</em></div>' +
            row("plus-circle", B, "Lakeshore_Selects_v2.fcpxml", "Edit", "Not in the original", "412 KB", "code", "#59EBA6") +
            row("plus-circle", B, "Lakeshore_Selects_v1.fcpxml", "Edit", "Not in the original", "398 KB", "code", "#59EBA6") +
            row("plus-circle", B, "Notes for colour.pdf", "Edit", "Not in the original", "1.2 MB", "file-text", "#FFC74D"))
    foot = (f'<div class="card coll">{icon("warning","tray")}<div class="ct"><small>Not complete yet</small><b>4 files are missing and 2 are different on Studio NAS</b></div>'
            f'<span class="grow"></span><button class="glow sm">{icon("copy")}Copy the missing files</button></div>')
    return (tool_head("Copy &amp; Verify", "Checked 682 files in 3 min 12 s  ·  full check with xxHash64", MODE(1)) + setup + counters +
            f'<div class="card list tree chkl">{rows}</div>' + foot)

SCAN_ALL = dict(scans={"Footage SSD": (.58, "Scanning 58%  ·  862K files"), "Archive 8TB": (.12, "Scanning 12%  ·  96K files"),
                       "Studio NAS": (None, "Scanning  ·  213 GB mapped"), "Macintosh HD": "wait", "Client Deliveries": "wait"},
                footer="Scanning 3 drives, 2 waiting")
DUP_DONE = ("Duplicates", (None, "412.6 GB to free in 14 folders", "g"))
STATES = {  # key: (body, sidebar arguments)
    "map": (map_state, {}), "tree": (tree_state, {}), "types": (types_state, {}), "largest": (largest_state, {}),
    "scanning": (scanning_state, dict(sel="Footage SSD", **SCAN_ALL)), "idle": (idle_state, dict(sel="Archive 8TB")),
    "search": (search_state, dict(sel="Search", query="lakeshore")),
    "duplicates": (dup_state, dict(sel="Duplicates", tools={"Duplicates": (.64, "Verifying 64%  ·  10 Brand Film", "cy")})),
    "copy-setup": (copy_setup_state, dict(sel="Copy & Verify", tools=dict([DUP_DONE]))),
    "copy-running": (copy_running_state, dict(sel="Copy & Verify", tools=dict([DUP_DONE, ("Copy & Verify", (.41, "Copying 41%  ·  412 MB/s", "cy"))]))),
    "copy-pace": (lambda: copy_running_state(True), dict(sel="Copy & Verify", tools=dict([DUP_DONE, ("Copy & Verify", (.41, "Copying 41%  ·  38 MB/s", "cy"))]))),
    "copy-done": (copy_done_state, dict(sel="Copy & Verify", tools=dict([DUP_DONE, ("Copy & Verify", (None, "1,204 files verified", "g"))]))),
    "check-copy": (check_copy_state, dict(sel="Copy & Verify", tools=dict([DUP_DONE, ("Copy & Verify", (None, "4 missing, 2 different", "am"))]))),
}

CSS = open(os.path.join(HERE, "interface.css")).read()
pages = "".join(f'<section class="win" data-s="{k}">{sidebar(**kw)}<main class="main">{fn()}</main></section>' for k, (fn, kw) in STATES.items())
doc = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Stowmap interface design</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>{CSS}</style></head><body>
<svg width="0" height="0" style="position:absolute"><defs><filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0" stdDeviation="7" flood-color="#40D9FF" flood-opacity=".55"/></filter></defs></svg>
{pages}
<script>const s=new URLSearchParams(location.search).get("s");if(s){{document.body.classList.add("one");document.querySelectorAll(".win").forEach(w=>w.hidden=w.dataset.s!==s)}}</script>
</body></html>'''
open(os.path.join(HERE, "interface.html"), "w").write(doc)
print("wrote interface.html", len(doc))
