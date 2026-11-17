# Interface design

`interface.html` is the visual source of truth for the SwiftUI views (built with the stageshow-ui
method: realistic fidelity, one row component per list, fixed column tracks, one icon family).

- Regenerate: `python3 build.py` (reads `interface.css`, inlines `icons/`, which are Phosphor fill glyphs, MIT).
- View one state: `interface.html?s=map` (also `tree`, `types`, `largest`, `scanning`, `idle`).
- `shots/` holds 2x renders of each state at the default 1200×780 window.

In the app the glyphs are SF Symbols; Inter stands in here for SF Pro.

Decisions the app follows:
- Window: 250 px sidebar, 22 px content inset, 14 px between blocks, cards 16 px radius.
- Rows are one line on shared fixed tracks: dot · icon · name · meter · size · percent · actions.
- Hidden items carry an eye-slash glyph, not a word. Collector button appears on hover or when collected; the Finder button is always there.
- Hovering a slice grows it 8 px and dims the others to 55%; the centre label switches to that slice.
- Never-scanned and scanning states are a two-card split, so the pane is never an empty box.
- Accent use: violet→cyan gradient only on the selected drive, the primary button and progress rings.

Not checked here: motion (the mock is static), light mode (the app is dark only), widths below 960 px.
