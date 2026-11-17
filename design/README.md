# Interface design

`interface.html` is the visual source of truth for the SwiftUI views (built with the stageshow-ui
method: realistic fidelity, one row component per list, fixed column tracks, one icon family).

- Regenerate: `python3 build.py` (reads `interface.css`, inlines `icons/`, which are Phosphor fill glyphs, MIT).
- View one state: `interface.html?s=map` (also `tree`, `types`, `largest`, `scanning`, `idle`, `search`, `duplicates`, `copy-setup`, `copy-running`, `copy-pace`, `copy-done`, `check-copy`).
- `shots/` holds 2x renders of each state at the default 1200×780 window. Re-render: `NODE_PATH=$(npm root -g) node shoot.js` (Playwright).
- `build.py` loads the app icon from `../Resources/icon_preview.png` (git-ignored; run `Resources/make_icon.py` or copy it in).

In the app the glyphs are SF Symbols; Inter stands in here for SF Pro.

Decisions the app follows:
- Window: 250 px sidebar, 22 px content inset, 14 px between blocks, cards 16 px radius.
- Rows are one line on shared fixed tracks: dot · icon · name · meter · size · percent · actions.
- Hidden items carry an eye-slash glyph, not a word. Collector button appears on hover or when collected; the Finder button is always there.
- Hovering a slice grows it 8 px and dims the others to 55%; the centre label switches to that slice.
- Never-scanned and scanning states are a two-card split, so the pane is never an empty box.
- Accent use: violet→cyan gradient only on the selected drive, the primary button and progress rings.

## 1.3: sidebar, Search, Duplicates, Copy & Verify

All sizes are points at 1x. Colours: violet `#8C5CFF`, cyan `#40D9FF`, green `#59E699`, amber `#FFC74D`, red `#FF6666`.
Text greys are white at 55% (secondary), 45% (paths), 35% (placeholders). Smallest text anywhere is 10.5.

### Sidebar (every state), top to bottom
- Brand, then the search box: 30 high, 10 side margin, radius 9, white 7% fill, 12 px text "Search all drives", ⌘F hint at the right in 10.5/600.
  Focused or holding a query: white 10% fill, 1.5 px cyan ring at 65%, a clear button at the right. While searching, a 2 px violet→cyan bar runs along the bottom edge inside the box (not drawn in a shot).
- Tool rows, Duplicates then Copy & Verify, built from the drive row: 32 px tile (radius 9), name 12.5/600, then one status line 10/regular. Idle: "Find matching folders" / "Copy with checksums" in the secondary grey. Working: a 4 px solid cyan bar above a cyan status line ("Verifying 64% · 10 Brand Film", "Copying 41% · 412 MB/s"). Finished: no bar, a green result line ("412.6 GB to free in 14 folders", "1,204 files verified"), amber when something needs attention ("4 missing, 2 different").
  The selected row gets the same white 9% plate and gradient tile as a selected drive. 4 px between the two rows, 10 px before the first group label.
- Drive groups as before. Row padding is now 7/8, rows 3 px apart.
- A drive that is scanning swaps its 4 px capacity bar for a 6 px violet→cyan progress bar and its sub line for a cyan status ("Scanning 58% · 862K files"); the spinner stays at the right of the name. A network share has no percent: a 34%-wide segment slides along the 6 px track and the line reads "Scanning · 213 GB mapped". A queued drive keeps its capacity bar in grey (white 30%) and reads "Waiting to scan".
- Footer, 10 px top padding, 12 sides and bottom, 8 px gap: "Scan All Drives" is a full-width 32 px quiet capsule with the drives glyph. Running, the same slot is a cyan-tinted capsule (cyan 10% fill, 16% ring) with "Scanning 3 drives, 2 waiting" in cyan 10.5/600 and a small red "Stop" pill at its right. Under it, "Scan a Folder…" and the gear as before.

### Shared parts
- Tool header: title 26/700, sub line 12 secondary, controls at the right on the title's centre line. No capacity bar under it.
- Capsule switch (All · Folders · Files, Copy · Check a Copy, Quick · Full): 3 px padding, segments 12/600 with 7×16 padding, the active one uses the tab fill (cyan 30→20%).
- Drive badge: 17 high, radius 5, white 8% fill, a 10 px drive glyph in the drive's colour, then the name in 10.5/600. Drive colours: Macintosh HD cyan `#40D9FF`, Footage SSD `#B380FF`, Archive 8TB `#FFC74D`, Studio NAS `#59EBA6`, folders `#FF8CB3` (assign from the palette in sidebar order).
  A location is always badge + path (11, white 45%, the path inside the drive, middle-truncated in the app).
- Icon tile in lists: 28 px, radius 8, white 7%, 14 px glyph in the kind colour.

### Search
- Head: "Search", sub "38 results for “lakeshore” · 4 drives", the All/Folders/Files switch at the right.
- "Based on:" is one 11.5 line under the head (label in white 80%, the rest secondary), truncated at the end if it runs long.
- Result row, 46 high, tracks: `28 tile · 1fr name over location · 96 size bar · 72 size · 24 · 24 · 24` with 10 px gaps (the three buttons sit 6 px apart). Name 12.5/600 with the match in cyan. The size bar takes the drive's colour and is scaled to the largest result. Buttons: collect, show on map, reveal.

### Duplicates
- Head: sub line "14 matching folders · 412.6 GB to free · one copy of everything always stays". Right: scope menu ("All drives"), Filters menu, gradient "Find Duplicates".
- One block per set of matching folders: radius 12, white 3.5% (6% when open), 6 px apart. Tracks: `12 caret · 28 tile · 1fr body · 150 stats · 158 verify slot · 24 ignore`, 10 px gaps, 10 px vertical padding.
  Body: folder name 13/600, then one 22 px line per location (badge, path, a 22 px collect button; amber when that side is in the collector).
  Stats, right-aligned: "212.4 GB to free" 13/600 over "682 files · 212.4 GB per copy" 11 secondary.
  Verify slot, right-aligned, one of: quiet "Verify" button; a 6 px cyan bar + percent in cyan 11.5/600 + small "Stop"; green pill "Verified identical".
- Open set: file rows indented 60 from the block edge, hairline between rows, tracks `18 icon · 1fr name · 150 "2 copies · 6.48 GB each" · 102 pill · 68 size`. The amber pill reads "Samples match".
- The collector bar is the same component as on the map; its chip says which side was collected.

### Copy & Verify
- Head right: the Copy · Check a Copy switch. While a copy runs the switch is replaced by Pause and Stop (Stop in the red quiet style).
- **Setup.** Two equal cards, 14 px apart, filling the height above the options card. Card head: "From"/"To" 15/700 with a 11.5 count beside it; "Add…" small button at the right of From.
  Source row tracks: `28 tile · 1fr name over location · 76 size over file count · 22 remove`. A dashed drop zone (1.5 px dash, white 16%, radius 12) takes the rest of the card.
  Destination: an inner plate (white 4.5%, radius 12, 14 px padding): 32 tile in the drive colour, name 12.5/600 + path, an 8 px free-space bar (used space white 28%, then this copy in violet→cyan), under it "548.1 GB free" left and "236.1 GB after this copy" in cyan right, 10.5. The third slot is a dashed zone "Add Destination…".
  Options card: five cells spread across one row, label 11/500 secondary over the control: three menus (Checksum, Verify, If a file exists) and two switches (34×20, cyan when on).
  Last row: summary 15/700 "1,204 files · 312 GB to 2 destinations" over "Needs 624 GB. Both destinations have room." 12 secondary; "Start Copy" at the right: gradient capsule, 46 high, 34 side padding, 15/600, shadow `0 6 20 violet 45%`.
- **Running** (`copy-running`). Blocks top to bottom, 14 px apart: hero card, [pace note], destination lanes, file list (takes the rest, fades at the bottom).
  - Hero card: padding 22, ring at the left, 28 px gap, then the right column.
  - Ring: 260×260. Outer track = copied: radius 116, width 16, violet→cyan gradient at 135°, round caps. Inner track = verified: radius 97, width 8, green. Both start at 12 o'clock and run clockwise over a white 7% track. 7 px of air between the tracks; the centre is 186 px clear.
    Centre: percent 60/700, tracking −0.04em, with the "%" at 28/600 in secondary; 6 px under it the phase ("Copying", then "Verifying") 13/600 cyan. The percent is bytes copied; once copying is done it switches to bytes verified.
  - Right column: speed 56/700 with "MB/s" 18/600 secondary on the same baseline; a key at the top right (8 px dots: "Copied 41%" gradient, "Verified 29%" green, 11/500).
    Sparkline: full column width × 124, 10 px above and 16 below. Smooth line (Catmull-Rom), 2.5 px, round caps, violet at the left to cyan at the right; area under it cyan 30% fading to 0; hairlines at 200 and 400 MB/s (white 6%) and a baseline (white 10%); the newest point is a 4 px cyan dot with an 8 px cyan 22% halo. Y range 0 to about 1.15× the peak.
    Stats: four equal cells split by a hairline, each label 11/500 secondary, value 17/700, note 11 white 45%: Copied "128.4 GB / of 312 GB", Files "480 / of 1,204", Time left "12 min / with verifying", Elapsed "5:31 / started 2:16 PM".
  - Lanes card, one row per destination, hairline between: tracks `32 tile · 150 name over path · 1fr bars · 150 state`, 12 px gaps, 8 px vertical padding. Bars: copy 6 px violet→cyan above verify 4 px green, 5 px apart. State, right-aligned: "Writing 412 MB/s" 12/600 over "Verified 452 of 480" 11/500 green.
  - File list: title row "Files" with "480 of 1,204" at the right. Tracks `18 icon · 1fr name · 250 folder · 68 size · 70 checksum · 14 state`, 10 px gaps, rows 28 high.
    Current file: white 6% plate, name 600, a 5 px cyan bar in the folder track, percent in cyan in the checksum track, spinner in the state track.
    Finished file: folder path 11 white 40%, the first 8 characters of the checksum in JetBrains Mono (SF Mono in the app) 11/500 secondary, green check. A problem row puts a word in the checksum track in amber ("Skipped") or red and a warning glyph in the state track.
  - Pace note (`copy-pace`): one 12 px amber line with a 13 px warning glyph, no plate, between the hero card and the lanes; the slow lane's "Writing" line turns amber. Absent when the drive is at its usual speed. The numbers in that shot are only there to show the placement.
- **Done** (`copy-done`). Same hero card and ring geometry with both tracks full and green; a 96 px green check in the centre. Right column: "All 1,204 files verified" 30/700, one 13 px sentence, three stat cells (Copied, Time, Average), then "Show in Finder", "Open Checksum List" (quiet) and "New Copy" (gradient). With problems the title reads "1,201 verified, 3 need attention" and the file list starts with those rows.
  Below: a 372 px card (Destinations, each with a green "Verified" pill; then the checksum lists with a reveal button) beside the file list (same rows without the folder track).
- **Check a Copy** (`check-copy`). Setup card on one row: Original and Copy wells (label 11/500, 32 tile, folder name 12.5/600 over its location), an arrow between them, the Quick · Full switch under a one-line caption, then "Check Again" (the gradient "Start" before the first run).
  Four counter cards in a row, 14 px apart, padding 14/16: 36 px tile with an 18 px glyph, number 26/700, label 11.5. Match green, Missing from the copy red, Different amber, Only in the copy cyan.
  Result list in that order of sections (Match is not listed). Row tracks `14 state · 18 icon · 1fr name · 110 folder · 190 reason · 64 size · 24 reveal`; the reason takes the section colour ("Not on Studio NAS", "Incomplete: 2.11 of 3.31 GB", "Same size, checksum differs", "Not in the original").
  Bottom bar (collector component): amber warning glyph, "4 files are missing and 2 are different on Studio NAS", gradient "Copy the missing files".

Sample data: the copy is 6 folders (1,204 files, 312 GB) from Footage SSD to Archive 8TB and Studio NAS. "11 Lakeshore Wedding" is 682 files and 212.4 GB wherever it appears.

Not checked here: motion (the mock is static), light mode (the app is dark only), widths below 960 px.
