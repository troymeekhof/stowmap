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
