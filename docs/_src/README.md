# How this site works

- **`docs/` is the website.** GitHub Pages serves it from the `troymeekhof/stowmap` repo at https://troymeekhof.github.io/stowmap/. Plain static files, no build step on Pages (`.nojekyll`).
- **Pages:** `index.html` (landing page), `privacy/index.html`, `404.html`. Shared `assets/style.css` and `assets/site.js`. `robots.txt`, `sitemap.xml`, `llms.txt`, `site.webmanifest`.
- **Paths are relative** so the site works under `/stowmap/`. The one exception is `404.html`, which GitHub serves at any depth, so it uses `/stowmap/...`. If the site moves to a custom domain, change those to `/...`, add a `CNAME` file, and replace `https://troymeekhof.github.io/stowmap/` in the canonical, Open Graph, JSON-LD, `robots.txt`, `sitemap.xml` and `llms.txt`.
- **Edit pages by hand**, smallest change possible. `_src/build_pages.py` is the script that wrote the first version of the three pages (it keeps the FAQ and its JSON-LD in one list). It is a record, not a generator: if you rerun it, hand edits to those pages are lost.
- **Check before pushing:** `python3 _src/check.py` (links, anchors, JSON-LD, FAQ parity, one h1, image alt and sizes, sitemap, banned phrases, competitor names).
- **Copy rules:** short and plain, no competitor names, facts only from the app. Run new copy through the banned list.
- Add one line to `_src/CHANGELOG.md` with each change.

## Faux UI, stills and videos (`_src/motion/`)

Everything that looks like the app is drawn from the app's interface design (`design/interface.html` and `design/interface.css` in the repo root). `interface.css` here is a verbatim copy; `stowmap-ui.js` is a JavaScript port of `design/build.py` so the same markup can be animated. If the design changes, copy the CSS again, update the port, and re-render.

- `campaign.json`: brand, copy and sample data. `scenes.js`: the four scenes, each a pure function of time. `stage.html`: the page that draws one frame (`window.seek(t)`).
- Render (needs Playwright and ffmpeg):

      python3 -m http.server 8777 -d docs &
      export NODE_PATH=$(npm root -g)
      node docs/_src/motion/render.js hero out/hero        # also: scan, drill, collect  -> out/<name>.mp4
      node docs/_src/motion/still.js og docs/assets/img/og.png
      node docs/_src/motion/still.js hero poster.png --t 9.3 --nocursor 1

  WebM copies: `ffmpeg -i x.mp4 -c:v libvpx-vp9 -crf 34 -b:v 0 -an x.webm`.
- The four tab stills in `assets/img/view-*.webp` are the design's own renders (`design/shots/*.png`), resized.
- `qc/` holds the contact sheets and the QC report for the current renders.
- Icons are Phosphor (fill), MIT.

`_qa/` holds review screenshots and can be deleted.
