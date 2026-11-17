# Stowmap — see what's filling every drive on your Mac

Native SwiftUI disk-space analyzer for macOS 13+ (Apple Silicon + Intel). Internal SSDs, external
drives and NAS shares, each drawn as a map you can click through. It costs nothing, and the only
thing it sends over the network is its own update check.

**Website:** https://troymeekhof.github.io/stowmap/

## Download

**[Download Stowmap.dmg](https://github.com/troymeekhof/stowmap/releases/latest/download/Stowmap.dmg)** — macOS 13 Ventura or newer.

1. Open the DMG and drag **Stowmap** into **Applications**, then open it.
2. First launch only: macOS will warn that it can't verify the app. Click **Done**, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
3. Optional, for complete results: **System Settings → Privacy & Security → Full Disk Access** →
   turn on Stowmap, then rescan. Without it macOS hides Mail, Messages, Safari and parts of
   `~/Library` from every app.

Stowmap checks for a new version once a day. Gear menu → **Check for Updates…** checks right away.

## What it does

- **Every drive in one sidebar.** Startup disk, other internal volumes, USB / Thunderbolt / SD
  drives and network shares (SMB, AFP, NFS), each with a live used/free bar. Drives appear and
  disappear as you plug them in. Any folder can be scanned too (button, ⌘O, or drag it onto the window).
- **Map.** A donut chart of the current folder: the biggest items as slices, a ranked list beside
  it. Hover to read sizes, click to go in, breadcrumbs or ⌘↑ to come back.
- **Hidden items included.** Dot-folders and Finder-hidden items are scanned and labelled. One
  toggle folds them away.
- **Hidden space.** The gap between what macOS reports as used and what a scan can reach
  (snapshots, purgeable data, protected system files) is shown as its own entry, so totals match Finder.
- **Finder shortcuts on every row.** Open the folder, reveal the file, Quick Look, copy path,
  open in Terminal (right-click).
- **Tree.** The whole hierarchy as an expandable outline with sizes and percent bars, plus search by name.
- **File Types.** Space by category (Video, Images, Audio, Documents, Code & Data, Archives,
  Apps, System) and by extension, with file counts.
- **Largest Files.** The 250 biggest files on the drive, filterable, with a jump to their folder on the map.
- **Collector.** Add items to a list, see what you'd reclaim, move them to the Trash in one step.
  Nothing is deleted permanently; put-back works until you empty the Trash.
- **Saved index.** The last scan of each drive reopens instantly. Rescan with ⌘R.
- **CSV export** of any folder's breakdown.
- **Stays on your Mac.** No account and no telemetry. The update check is the only network request.

## Build from source

```bash
./build.sh --install     # release build → /Applications → launch
./build.sh --package     # universal app → ~/Downloads/Stowmap.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## How it measures

- Walks the volume with `readdir` + `fstatat` on a worker pool (no Foundation enumerator), and
  never crosses onto another volume.
- Sizes are **allocated** size (blocks on disk), the same basis Finder uses for "on disk".
  iCloud files that aren't downloaded count as zero.
- Hard-linked files are counted once. On the startup disk, the Data volume's firmlinked folders
  (`/Users`, `/Applications`, `/Library`…) are counted once, where you expect to see them.
- Files under 128 KB are grouped per folder as "N small files" to keep memory flat on drives with
  millions of files. Their space is still counted.
- APFS clones (duplicated files that share blocks) are counted at full size each, so a folder full
  of clones can read larger than the space it frees.

## Files

```
Package.swift                         SwiftPM, macOS 13, Sparkle 2
Sources/Stowmap/StowmapApp.swift      @main, window, menu commands, Sparkle updater
Sources/Stowmap/Model.swift           FileNode tree, file-type table, Volume, formatters
Sources/Stowmap/DiskScanner.swift     parallel walker, type stats, largest-files tracking
Sources/Stowmap/AppModel.swift        volume discovery, ScanSession (scan/navigate/collect), saved index, Finder actions
Sources/Stowmap/Views/Theme.swift     colours, Card, buttons, GlassTabs, row pieces
Sources/Stowmap/Views/MainViews.swift window, sidebar, header, idle/scanning states, collector bar
Sources/Stowmap/Views/Tabs.swift      donut chart, Map / Tree / File Types / Largest Files
Resources/                            Info.plist, Stowmap.icns, make_icon.py
build.sh / release.sh / appcast.xml   build, ship an update, update feed
docs/                                 website (GitHub Pages)
```
