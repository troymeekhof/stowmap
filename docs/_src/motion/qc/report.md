## QC Report: stowmap 1.3 update (copy, duplicates, hero, scan), 2026-11-17

Renderer: seek(t) page + Playwright (Chromium) + ffmpeg, 30 fps, H.264 yuv420p (CRF 24) and VP9 WebM (CRF 40; copy at 46 so it stays smaller than its MP4). No audio by design.

| File | Size | Frames | Duration | MP4 / WebM |
|---|---|---|---|---|
| stowmap-copy (new) | 1200x994 | 378 | 12.6 s | 760 KB / 627 KB |
| stowmap-duplicates (new) | 1200x994 | 270 | 9.0 s | 357 KB / 314 KB |
| stowmap-hero (web cut, from 2.2 s) | 1920x1080 | 594 | 19.8 s | 2.04 MB / 1.67 MB |
| stowmap-launch.mp4 (full, with title card) | 1920x1080 | 660 | 22.0 s | 2.07 MB |
| stowmap-scan (re-rendered, new camera) | 1000x1198 | 285 | 9.5 s | 427 KB / 386 KB |

drill and collect were not re-rendered: their camera is the main pane only, so the sidebar change does not show.

Timestamps inspected
- copy (rendered stills): 0.5, 1.65, 4, 7, 8.6, 10.5; (from the encoded MP4) 1.65, 1.80, 1.95, 7.40, 7.50, 9.45, 9.50, 9.62, 9.80, 11.75, 11.90, 12.10, 12.55 (`copy-boundaries.png`); first and last frame compared for the seam.
- duplicates (rendered): 0.5, 1.6, 3, 5, 7.8; (encoded) 0.95, 2.05, 2.15, 2.4, 3.65, 3.8, 5.85, 5.95, 7.05, 7.3, 8.6, 8.97 (`dups-boundaries.png`).
- hero (rendered): 9.3, 15.8, 17.5, 19.4, 20.2, 20.9, 21.2; (encoded web cut) 12.60, 13.00, 13.15, 13.30, 14.10, 14.25, 14.40, 16.75, 16.90, 17.50, 17.80, 18.10, 19.20, 19.45, 19.75 (`hero-boundaries.png`).
- scan (rendered): 0.3, 4, 6.5, 6.8.
- 1 fps contact sheet of every new encode (`contact-*.png`); ffprobe on every file: size, fps, frame count and pixel format as in the table.
- On the page (Chromium, 390, 1440 and 2560 wide): all six clips reach readyState 4 and advance; with reduced motion they stay paused on the poster with controls.

Issues found and fixes applied
- Stills were clipped at 1100 px once the scan clip grew to 1198 px. The render viewport is now 1300 px tall.
- Copy: the second destination read "Verified 1,132 of 1,204" while the ring said 100%. Both lanes now end at 100%.
- Copy and hero: the done view said the checksum lists are "saved in each destination", which the app has not confirmed. The label is now "Checksum lists" (design and clips).
- Hero end card: the window sat whole in the frame with air on every side. It now runs off the right and bottom edges.
- Duplicates: six rows left a blank band under the list. A seventh set fills it.
- Copy WebM came out larger than its MP4 at CRF 40. Re-encoded at 46 and checked at full size.

Remaining concerns
- The Duplicates loop opens on a "nothing found yet" pane that is not in the interface design (the design only has the results state). It is built from the same parts; the app may show something else there.
- Copy and Duplicates reset by a fade of the pane (Duplicates) or by clicking New Copy (Copy). The Duplicates reset has no on-screen cause.
- Scan: the map view in this camera cuts the tab strip and the header pills at the right edge, as before. The loop-point tick on Archive 8TB is unchanged from the first report.
- Pass 3 (phone size): unchanged. The hero is the whole window and its UI text is about 4 px tall in a 390 px column; the pane clips are cropped by CSS on phones.
- Speeds, sizes and counts in the window are sample data. Nothing on the page states a speed.
- Text is set in Inter (stand-in for SF Pro on the Linux render host). No audio, so Pass 5 sync checks do not apply.

Gate A (storyboard) and Gate B (reference approval) were not put to a person; the renders were requested in one unattended pass.
Human approval: PENDING

---

## QC Report: stowmap-launch, all cuts, 2026-11-17

Renderer: seek(t) page + Playwright (Chromium) + ffmpeg, 30 fps, H.264 yuv420p (CRF 18) and VP9 WebM (CRF 34). No audio by design (the page plays them muted).

| File | Size | Frames | Duration |
|---|---|---|---|
| stowmap-launch.mp4 (full, with title card) | 1920x1080 | 540 | 18.0 s |
| stowmap-hero.mp4 / .webm (web cut, from 2.2 s) | 1920x1080 | 474 | 15.8 s |
| stowmap-scan.mp4 / .webm | 1200x1000 | 285 | 9.5 s |
| stowmap-drill.mp4 / .webm | 1200x994 | 270 | 9.0 s |
| stowmap-collect.mp4 / .webm | 1200x994 | 255 | 8.5 s |

Timestamps inspected
- hero (rendered stills): 1.2, 3.4, 4.0, 5.4, 6.2, 6.9, 7.6, 8.6, 9.6, 11.3, 13.2, 14.3, 14.9, 16.8
- hero (from the encoded MP4, boundaries): 2.25, 2.5, 2.8, 5.03, 5.13, 5.3, 7.27, 7.36, 8.3, 8.44, 11.1, 11.3, 14.05, 14.25, 14.45, 15.4, 15.7, 16.0, 17.7, 17.97 (`hero-boundaries.png`)
- scan: 0, 2, 4, 6.5, 6.8; drill: 1.5, 2.5, 5.0, 7.6; collect: 1.3, 3.4, 4.45, 6.0
- 1 fps contact sheet of every encoded file (`contact-*.png`); first and last frame of each loop compared for the seam.
- ffprobe on every MP4: size, fps, frame count and pixel format as in the table.

Issues found and fixes applied
- First build used an invented window layout. Replaced with a port of the app's interface design (`design/interface.css` copied verbatim, `design/build.py` ported to `stowmap-ui.js`), then all scenes re-rendered.
- OG card: the overlay class collided with the stage class and shifted the frame 64 px. Renamed the overlay class; headline no longer touches the window.
- Drill loop: pointer covered the breadcrumb label it clicks. Aim moved to the end of the word.
- Collect: collapsing rows stayed legible while squeezed. Opacity now falls faster than height.
- Web hero: the title card repeated the page h1 directly above it. The page now plays a cut that starts as the window arrives.

Remaining concerns
- Loop seams: drill and collect match first to last frame apart from compression noise. Scan differs in one place: the "scanned" tick on Archive 8TB is present at the end and absent at the start, so it disappears at the loop point.
- The collect loop resets under a 0.3 s fade of the list, not from an on-screen action.
- Pass 3 (phone size): the hero is the whole 1386 px window, so its UI text is about 4 px tall in a 390 px column. The loops are cropped by CSS on phones to stay near 8 px. A separate phone cut was not made.
- "Users" is 518.2 GB in the root list while its contents add up to 520.1 GB. That gap is in the design's sample data.
- Text is set in Inter (stand-in for SF Pro on the Linux render host).
- No audio, so Pass 5 sync checks do not apply.

Gate A (storyboard) and Gate B (reference approval) were not put to a person; the renders were requested in one unattended pass.
Human approval: PENDING
