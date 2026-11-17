import json, re, os, html
DOCS='/home/user/stowmap/docs'
ICONS='/tmp/claude-0/-home-user-Home-Dash/69d508ce-2d04-5989-ad88-d078f40989cf/scratchpad/npm/node_modules/@phosphor-icons/core/assets/fill/'
def icon(n):
    s=open(ICONS+n+'-fill.svg').read(); p=s[s.index('<path'):s.rindex('</svg>')]
    return f'<svg viewBox="0 0 256 256" aria-hidden="true">{p}</svg>'
SITE='https://troymeekhof.github.io/stowmap/'
DMG='https://github.com/troymeekhof/stowmap/releases/latest/download/Stowmap.dmg'
SRC='https://github.com/troymeekhof/stowmap'
TITLE='Stowmap: Free Disk Space Analyzer for Mac'
DESC="Stowmap is a free disk space analyzer for Mac. See what's taking up space on your startup disk, external drives and NAS shares, then clean up from one list."
FAQ=[
 ("Is Stowmap free?", "Yes. Stowmap is free to download and use, with no account. The source code is on GitHub."),
 ("Which Macs does it run on?", "Any Mac on macOS 13 or later, Apple Silicon or Intel."),
 ("How do I see what's taking up space on my Mac?", "Open Stowmap, pick your startup disk in the sidebar and click Scan. When the scan finishes, the Map tab shows the biggest folders as slices. Click a slice to go inside it, and keep going until you find the files you forgot about."),
 ("Why does macOS say Stowmap can't be opened?", "Stowmap isn't notarized by Apple yet, so macOS blocks it the first time. Open System Settings, go to Privacy & Security, find the message about Stowmap and click Open Anyway. You only need to do this once."),
 ("Does Stowmap need Full Disk Access?", "No, it's optional. Without it, macOS keeps a few protected folders out of reach and Stowmap reports that space as hidden space. With it, the results are complete. You can turn it on in System Settings under Privacy & Security, then Full Disk Access."),
 ("Can it scan a NAS or an external drive?", "Yes. External drives on USB or Thunderbolt, SD cards, and network shares over SMB, AFP or NFS all appear in the sidebar once they are mounted. Each one can be scanned, and several can scan at the same time."),
 ("Why is there a slice called hidden space?", "Some space can't be read by any scan: local snapshots, purgeable space and protected system data. Stowmap shows it as its own slice so the total matches what Finder reports for the drive."),
 ("Does Stowmap delete files?", "Stowmap moves the items you collect to the Trash. They stay there, recoverable, until you empty the Trash yourself."),
 ("Does Stowmap send my data anywhere?", "No. Scans and results stay on your Mac. There is no account and no telemetry."),
 ("How does it update?", "Stowmap updates itself. When a new version is out, the app offers to install it."),
]
faq_html=''.join(f'<details><summary>{html.escape(q,quote=False)}</summary><p>{html.escape(a,quote=False)}</p></details>\n' for q,a in FAQ)
ld={"@context":"https://schema.org","@graph":[
 {"@type":"WebSite","@id":SITE+"#website","url":SITE,"name":"Stowmap","publisher":{"@id":SITE+"#publisher"}},
 {"@type":"Organization","@id":SITE+"#publisher","name":"Mid-July Media","url":"https://midjulymedia.com","founder":{"@type":"Person","name":"Troy Meekhof","url":"https://troymeekhof.com"}},
 {"@type":"SoftwareApplication","@id":SITE+"#app","name":"Stowmap","description":DESC,"url":SITE,"image":SITE+"assets/img/og.jpg","screenshot":SITE+"assets/video/stowmap-hero-poster.jpg",
  "applicationCategory":"UtilitiesApplication","applicationSubCategory":"Disk space analyzer","operatingSystem":"macOS 13 or later","processorRequirements":"Apple Silicon or Intel",
  "downloadUrl":DMG,"installUrl":DMG,"isAccessibleForFree":True,"codeRepository":SRC,
  "offers":{"@type":"Offer","price":"0","priceCurrency":"USD","availability":"https://schema.org/InStock"},
  "author":{"@type":"Person","name":"Troy Meekhof","url":"https://troymeekhof.com"},"publisher":{"@id":SITE+"#publisher"},
  "featureList":["Scans startup, internal, external and network drives","Donut map of any folder with click-through","Tree view with sizes","File type breakdown by category and extension","250 largest files","Collector list that moves items to the Trash","Hidden files included and marked","Saved scans reopen instantly"]},
 {"@type":"FAQPage","@id":SITE+"#faq","mainEntity":[{"@type":"Question","name":q,"acceptedAnswer":{"@type":"Answer","text":a}} for q,a in FAQ]},
 {"@type":"VideoObject","name":"Stowmap in 16 seconds","description":"A scan of a Mac startup disk in Stowmap: the map appears, two clicks go into the home folder, three hidden folders are collected and moved to the Trash.","thumbnailUrl":SITE+"assets/video/stowmap-hero-poster.jpg","contentUrl":SITE+"assets/video/stowmap-hero.mp4","uploadDate":"2026-11-17","duration":"PT16S"}
]}
def head(title, desc, path, rel, index=True, og_type='website'):
    url=SITE+path
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<link rel="canonical" href="{url}">
<meta name="robots" content="{'index,follow,max-image-preview:large,max-video-preview:-1' if index else 'noindex'}">
<meta name="author" content="Troy Meekhof">
<meta property="og:type" content="{og_type}">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(desc)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}assets/img/og.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Stowmap window on a dark background: a donut map of a home folder with the Library slice selected at 96.3 GB, next to the headline See what's taking up space on your Mac.">
<meta property="og:site_name" content="Stowmap">
<meta property="og:locale" content="en_US">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{html.escape(title)}">
<meta name="twitter:description" content="{html.escape(desc)}">
<meta name="twitter:image" content="{SITE}assets/img/og.jpg">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#12121a">
<link rel="icon" href="{rel}favicon.ico" sizes="48x48">
<link rel="icon" type="image/png" sizes="32x32" href="{rel}assets/img/favicon-32.png">
<link rel="apple-touch-icon" href="{rel}assets/img/apple-touch-icon.png">
<link rel="manifest" href="{rel}site.webmanifest">
<link rel="sitemap" type="application/xml" href="{rel}sitemap.xml">
'''
def header(rel, home):
    h = '' if home else rel
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="top"><div class="wrap">
  <a class="brand" href="{rel or './'}"{' aria-current="page"' if home else ''}><img src="{rel}assets/img/icon-64.png" width="30" height="30" alt="">Stowmap</a>
  <nav aria-label="Sections"><ul><li><a href="{h}#features">Features</a></li><li><a href="{h}#compare">Compare</a></li><li><a href="{h}#install">Install</a></li><li><a href="{h}#faq">FAQ</a></li></ul></nav>
  <a class="btn sm" href="{DMG}">Download</a>
</div></header>
'''
def footer(rel):
    return f'''<footer><div class="wrap">
  <p>© 2026 Mid-July Media. Made by <a href="https://troymeekhof.com">Troy Meekhof</a> in Michigan.</p>
  <ul><li><a href="{DMG}">Download</a></li><li><a href="{SRC}">Source on GitHub</a></li><li><a href="{SRC}/releases">Releases</a></li><li><a href="{rel}privacy/">Privacy</a></li></ul>
</div></footer>
'''
def loop(name, w, h, label, crop=None):
    c = f' crop" style="--pos:{crop}' if crop else ''
    return f'''<figure class="window{c}"><video data-loop muted loop playsinline preload="none" width="{w}" height="{h}" poster="assets/video/stowmap-{name}-poster.webp" aria-label="{label}"><source src="assets/video/stowmap-{name}.webm" type="video/webm"><source src="assets/video/stowmap-{name}.mp4" type="video/mp4"></video></figure>'''
def view(key, alt, cap):
    return f'''<figure class="vp vp-{key}"><div class="window"><picture><source media="(max-width:640px)" srcset="assets/img/view-{key}-crop-880.webp" width="880" height="1100"><img src="assets/img/view-{key}-1400.webp" srcset="assets/img/view-{key}-1400.webp 1400w, assets/img/view-{key}-2400.webp 2400w" sizes="(max-width:1280px) 92vw, 1200px" width="2400" height="1560" loading="lazy" decoding="async" alt="{alt}"></picture></div><figcaption>{cap}</figcaption></figure>'''

index = head(TITLE, DESC, '', '') + f'''<link rel="preload" as="image" href="assets/video/stowmap-hero-poster.webp" type="image/webp" fetchpriority="high">
<link rel="stylesheet" href="assets/style.css">
<script src="assets/site.js" defer></script>
</head>
<body>
{header('', True)}<main id="main" tabindex="-1">

<section class="hero" aria-labelledby="hero-h"><div class="wrap">
  <h1 id="hero-h">See what's taking up space on your Mac.</h1>
  <p class="lede">Stowmap is a free disk space analyzer for Mac. It scans your startup disk, external drives and NAS shares, then draws each folder as a map you can click through.</p>
  <div class="actions"><a class="btn" href="{DMG}">{icon('download-simple')}Download for Mac</a><a class="btn ghost" href="{SRC}">{icon('github-logo')}View source</a></div>
  <p class="meta">Free for macOS 13 or later, on Apple Silicon and Intel.</p>
  <figure class="window"><video data-loop autoplay muted loop playsinline preload="metadata" width="1920" height="1080" poster="assets/video/stowmap-hero-poster.webp" aria-label="Stowmap scans a startup disk, the map of the drive appears, two clicks go into the home folder, and three hidden folders are collected and moved to the Trash."><source src="assets/video/stowmap-hero.webm" type="video/webm"><source src="assets/video/stowmap-hero.mp4" type="video/mp4"></video></figure>
</div></section>

<section id="features" aria-labelledby="f1-h"><div class="wrap feature">
  <div class="copy"><p class="eyebrow">Drives</p><h2 id="f1-h">Every drive in one sidebar</h2>
  <p>Your startup SSD, internal and external drives on USB or Thunderbolt, SD cards, and network shares over SMB, AFP or NFS each get a row with a live used and free bar. Plug a drive in and it appears. Unplug it and it goes. Any folder can be scanned too, with the button or by dragging it in.</p>
  <p>Scans run in parallel, and several drives can scan at once. A typical internal SSD takes well under a minute.</p></div>
  {loop('scan',1200,1000,'A never-scanned external drive is picked in the Stowmap sidebar and scanned. A progress ring fills, then the map of the drive appears.')}
</div></section>

<section aria-labelledby="f2-h"><div class="wrap feature flip">
  <div class="copy"><p class="eyebrow">Map</p><h2 id="f2-h">A map you can click through</h2>
  <p>The Map tab draws the folder you're in as a donut. The biggest items are coloured slices. Hover one to read its name, size and share of the folder. Click it to go inside, and use the breadcrumbs to come back.</p>
  <p>Beside the donut, the same items sit in a ranked list with size bars.</p></div>
  {loop('drill',1200,994,'The pointer hovers the Users slice, clicks into Users and then the alex folder, reads two slices, and returns with the breadcrumb.','0%')}
</div></section>

<section aria-labelledby="f3-h"><div class="wrap feature">
  <div class="copy"><p class="eyebrow">Hidden files</p><h2 id="f3-h">Totals that match Finder</h2>
  <p>Hidden files and folders are part of every scan and carry a small mark, with a toggle to fold them away.</p>
  <p>Some space can't be read by any scan: local snapshots, purgeable space and protected system data. Stowmap gives it its own slice, so the map adds up to the number Finder shows for the drive.</p></div>
  <figure class="window crop" style="--pos:0%"><img src="assets/img/hidden-space-1200.webp" srcset="assets/img/hidden-space-1200.webp 1200w, assets/img/hidden-space-2400.webp 2400w" sizes="(max-width:900px) 92vw, 720px" width="1200" height="994" loading="lazy" decoding="async" alt="The map of Macintosh HD with the Hidden space slice selected: 86.1 GB, 11% of the drive. The list beside it marks hidden folders such as private and usr with an eye icon."></figure>
</div></section>

<section aria-labelledby="f4-h"><div class="wrap">
  <div class="sec-head"><p class="eyebrow">Views</p><h2 id="f4-h">Four ways to look at a drive</h2>
  <p>One scan feeds all four tabs. Every row has a button that opens the item in Finder, and you can copy its path or preview it with Quick Look.</p></div>
  <fieldset class="views"><legend class="vh">Choose a view</legend>
    <input type="radio" name="view" id="v-map"><input type="radio" name="view" id="v-tree" checked><input type="radio" name="view" id="v-types"><input type="radio" name="view" id="v-largest">
    <div class="vtabs"><label for="v-map">Map</label><label for="v-tree">Tree</label><label for="v-types">File Types</label><label for="v-largest">Largest Files</label></div>
    <div class="vpanels">
    {view('map','The Map tab in Stowmap: a donut of the alex home folder next to a ranked list of folders, with the Collector bar holding three items along the bottom.','<strong>Map.</strong> The current folder as a donut, with a ranked list beside it.')}
    {view('tree','The Tree tab in Stowmap: an expandable outline of Users, alex and Movies with a size and percent bar on every row.','<strong>Tree.</strong> An expandable folder hierarchy with sizes and percent bars.')}
    {view('types','The File Types tab in Stowmap: a donut of categories such as Video, Images and Code and Data, next to a list of extensions with file counts and sizes.','<strong>File Types.</strong> Space by category (Video, Images, Audio, Documents, Code &amp; Data, Archives, Apps, System) and by extension, with file counts.')}
    {view('largest','The Largest Files tab in Stowmap: a numbered list of the biggest files on the drive with their folders and sizes.','<strong>Largest Files.</strong> The 250 biggest files on the drive.')}
    </div>
  </fieldset>
</div></section>

<section aria-labelledby="f5-h"><div class="wrap feature flip">
  <div class="copy"><p class="eyebrow">Collector</p><h2 id="f5-h">Clean up from one list</h2>
  <p>Add items to the Collector as you find them. It keeps a running total of the space you'd get back.</p>
  <p>When the list looks right, one click moves everything to the Trash. Nothing is gone for good until you empty the Trash yourself.</p></div>
  {loop('collect',1200,994,'Three hidden folders are added to the Collector, the total reaches 19.2 GB, and Move to Trash clears them from the list.','100%')}
</div></section>

<section aria-labelledby="f6-h"><div class="wrap">
  <div class="sec-head"><h2 id="f6-h">The rest of it</h2></div>
  <div class="cards">
    <div class="card">{icon('magnifying-glass')}<h3>Straight to Finder</h3><p>Open in Finder or Reveal on every row. Copy the path, or preview the file with Quick Look.</p></div>
    <div class="card">{icon('lightning')}<h3>Saved scans</h3><p>The last scan of each drive is saved and reopens instantly. Rescan whenever you like.</p></div>
    <div class="card">{icon('lock-simple')}<h3>Private</h3><p>Everything stays on your Mac. No account and no telemetry.</p></div>
    <div class="card">{icon('arrow-clockwise')}<h3>Free, with updates</h3><p>Stowmap costs nothing and updates itself when a new version is out.</p></div>
  </div>
</div></section>

<section id="compare" aria-labelledby="cmp-h"><div class="wrap">
  <div class="sec-head"><p class="eyebrow">Compare</p><h2 id="cmp-h">How it compares with what's built in</h2>
  <p>macOS has two storage tools of its own. Here is what each one shows next to Stowmap.</p></div>
  <div class="tablewrap" tabindex="0" role="region" aria-labelledby="cmp-h"><table>
    <thead><tr><td></td><th scope="col" class="us">Stowmap</th><th scope="col">Storage in System Settings</th><th scope="col">Get Info in Finder</th></tr></thead>
    <tbody>
    <tr><th scope="row">What you see</th><td class="us">Every folder and file, ranked by size</td><td>Totals by category</td><td>One item at a time</td></tr>
    <tr><th scope="row">External drives and NAS shares</th><td class="us">Each one in the sidebar</td><td>Startup disk only</td><td>One at a time</td></tr>
    <tr><th scope="row">Hidden files and folders</th><td class="us">Included and marked</td><td>Counted inside category totals</td><td>Only after you show them in Finder</td></tr>
    <tr><th scope="row">Snapshots and purgeable space</th><td class="us">Its own slice on the map</td><td>Part of System Data</td><td>Purgeable space, for whole volumes</td></tr>
    <tr><th scope="row">Cleaning up</th><td class="us">A list with a running total, then one move to the Trash</td><td>Recommendations and per-category lists</td><td>Drag each item to the Trash</td></tr>
    <tr><th scope="row">Price</th><td class="us">Free</td><td>Built in</td><td>Built in</td></tr>
    </tbody>
  </table></div>
  <p class="note">Paid disk analyzers cover similar ground. Stowmap is free, and its source is public.</p>
</div></section>

<section id="install" aria-labelledby="ins-h"><div class="wrap">
  <div class="sec-head"><p class="eyebrow">Install</p><h2 id="ins-h">Install it in four steps</h2>
  <p>Stowmap isn't notarized by Apple yet, so macOS asks you to approve it once. Step three covers that.</p></div>
  <ol class="steps">
    <li><h3>Download</h3><p>Get <a href="{DMG}">Stowmap.dmg</a> from the latest release.</p></li>
    <li><h3>Drag to Applications</h3><p>Open the disk image and drag Stowmap into your Applications folder.</p></li>
    <li><h3>Click Open Anyway</h3><p>Open Stowmap. macOS will block it the first time. Go to System Settings, then Privacy &amp; Security, find the message about Stowmap and click Open Anyway.</p></li>
    <li><h3>Optional: Full Disk Access</h3><p>For complete results, add Stowmap under System Settings, Privacy &amp; Security, Full Disk Access. It works without it.</p></li>
  </ol>
</div></section>

<section id="faq" aria-labelledby="faq-h"><div class="wrap">
  <div class="sec-head"><p class="eyebrow">FAQ</p><h2 id="faq-h">Questions</h2></div>
  <div class="faq">
{faq_html}  </div>
</div></section>

<section class="cta" aria-labelledby="cta-h"><div class="wrap"><div class="panel">
  <img src="assets/img/icon-192.png" width="88" height="88" loading="lazy" decoding="async" alt="Stowmap app icon">
  <h2 id="cta-h">Find out where the space went</h2>
  <p>Free for macOS 13 or later.</p>
  <div class="actions"><a class="btn" href="{DMG}">{icon('download-simple')}Download for Mac</a><a class="btn ghost" href="{SRC}">{icon('github-logo')}View source</a></div>
</div></div></section>

</main>
{footer('')}<script type="application/ld+json">
{json.dumps(ld, ensure_ascii=False)}
</script>
</body>
</html>
'''
open(DOCS+'/index.html','w').write(index)

PDESC='Stowmap keeps your scans on your Mac. No account, no telemetry, and no analytics or cookies on this website.'
privacy = head('Privacy — Stowmap', PDESC, 'privacy/', '../') + f'''<link rel="stylesheet" href="../assets/style.css">
</head>
<body>
{header('../', False)}<main id="main" tabindex="-1"><div class="wrap"><article class="page">
  <h1>Privacy</h1>
  <p class="lede">Stowmap reads your drives to measure them. What it finds stays on your Mac.</p>
  <h2>The app</h2>
  <ul>
    <li>Scans, results and the saved index of each drive are stored on your Mac only.</li>
    <li>There is no account and no telemetry.</li>
    <li>Stowmap checks for new versions so it can update itself. That check does not include anything about your files.</li>
    <li>Items you collect are moved to the Trash on your Mac. Stowmap does not upload or copy them anywhere.</li>
  </ul>
  <h2>This website</h2>
  <ul>
    <li>This site has no analytics and sets no cookies. It loads no third-party scripts or fonts.</li>
    <li>The site is hosted on GitHub Pages and downloads come from GitHub Releases. GitHub may log your IP address when you load a page or download a file, as described in <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">GitHub's privacy statement</a>.</li>
  </ul>
  <h2>Questions</h2>
  <p>Open an issue on <a href="{SRC}/issues">GitHub</a>.</p>
  <p>Last updated November 17, 2026.</p>
</article></div></main>
{footer('../')}</body>
</html>
'''
open(DOCS+'/privacy/index.html','w').write(privacy)

B='/stowmap/'
nf = head('Page not found — Stowmap', 'Page not found.', '404.html', B, index=False).replace('<link rel="canonical" href="'+SITE+'404.html">\n','') + f'''<link rel="stylesheet" href="{B}assets/style.css">
</head>
<body>
{header(B, False)}<main id="main" tabindex="-1"><div class="wrap"><article class="page">
  <p class="eyebrow">404</p>
  <h1>That page doesn't exist.</h1>
  <p class="lede">The link you followed is wrong or out of date. The home page has the download and the install steps.</p>
  <div class="actions" style="justify-content:flex-start"><a class="btn" href="{B}">Go to the home page</a><a class="btn ghost" href="{DMG}">Download for Mac</a></div>
</article></div></main>
{footer(B)}</body>
</html>
'''
open(DOCS+'/404.html','w').write(nf)
open(DOCS+'/robots.txt','w').write(f'User-agent: *\nAllow: /\nDisallow: /stowmap/_src/\nDisallow: /stowmap/_qa/\nSitemap: {SITE}sitemap.xml\n')
open(DOCS+'/sitemap.xml','w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:video="http://www.google.com/schemas/sitemap-video/1.1">
<url><loc>{SITE}</loc><lastmod>2026-11-17</lastmod><changefreq>weekly</changefreq><priority>1.0</priority>
<video:video><video:thumbnail_loc>{SITE}assets/video/stowmap-hero-poster.jpg</video:thumbnail_loc><video:title>Stowmap in 16 seconds</video:title><video:description>A scan of a Mac startup disk in Stowmap: the map appears, two clicks go into the home folder, three hidden folders are collected and moved to the Trash.</video:description><video:content_loc>{SITE}assets/video/stowmap-hero.mp4</video:content_loc><video:duration>16</video:duration></video:video></url>
<url><loc>{SITE}privacy/</loc><lastmod>2026-11-17</lastmod><changefreq>yearly</changefreq><priority>0.3</priority></url>
</urlset>
''')
open(DOCS+'/site.webmanifest','w').write(json.dumps({"name":"Stowmap","short_name":"Stowmap","description":"A free disk space analyzer for Mac.","start_url":"./","display":"browser","background_color":"#08080d","theme_color":"#12121a","icons":[{"src":"assets/img/icon-192.png","sizes":"192x192","type":"image/png"},{"src":"assets/img/icon-512.png","sizes":"512x512","type":"image/png"}]},indent=1)+'\n')
open(DOCS+'/.nojekyll','w').write('')
open(DOCS+'/llms.txt','w').write(f'''# Stowmap

> Stowmap is a free, native disk space analyzer for macOS 13 or later (Apple Silicon and Intel), made by Troy Meekhof of Mid-July Media. It scans startup, internal, external and network drives and shows what is taking up space as a clickable donut map.

## Canonical facts
- Name: Stowmap. Category: disk space analyzer / storage utility for Mac. Built with SwiftUI.
- Price: free. No account. Updates itself.
- Requires: macOS 13 or later. Runs on Apple Silicon and Intel.
- Download: {DMG}
- Source: {SRC}
- Website: {SITE}
- Maker: Troy Meekhof, Mid-July Media (https://troymeekhof.com).

## What it does
- The sidebar lists every drive: startup SSD, internal drives, external drives (USB, Thunderbolt, SD cards) and network shares or NAS volumes (SMB, AFP, NFS), each with a live used and free bar. Any folder can be scanned too, by button or drag and drop.
- Scans run in parallel and several drives can scan at once. A typical internal SSD takes well under a minute.
- Map tab: a donut chart of the current folder. Hover a slice for name, size and percent, click to go inside, breadcrumbs to go back. A ranked list with size bars sits beside it.
- Tree tab: an expandable folder hierarchy with sizes and percent bars.
- File Types tab: space by category (Video, Images, Audio, Documents, Code & Data, Archives, Apps, System) and by extension, with file counts.
- Largest Files tab: the 250 biggest files on the drive.
- Hidden files and folders are included and marked, with a toggle to fold them away. Space no scan can read (snapshots, purgeable space, protected system data) is shown as its own slice so totals match Finder.
- Collector: add items to a cleanup list, see the total you would reclaim, then move them to the Trash in one step. Items stay recoverable until the Trash is emptied.
- Every row can be opened or revealed in Finder, its path copied, or previewed with Quick Look.
- The last scan of each drive is saved and reopens instantly. Rescan any time.
- Private: everything stays on the Mac. No account, no telemetry.

## Installing
- Stowmap is not notarized, so on first launch macOS needs one approval: System Settings > Privacy & Security > Open Anyway.
- Full Disk Access is optional and gives complete results.

## Pages
- [Home]({SITE}): features, install steps and FAQ
- [Privacy]({SITE}privacy/)
''')
print('ok', len(index))
