# Stowmap — project notes for Claude Code

Native SwiftUI **disk-space analyzer** for macOS 13+ (universal). Owner: Troy Meekhof (Mid-July Media).
Sibling of Pulse (`troymeekhof/pulse`): same stack, same visual language, same release flow.
Separate product. Original name, icon and UI; never borrow another app's name, look or assets.

Troy prefers brief, actionable answers. Don't over-explain; ask only on real decisions.

## Layout

See the Files table in README.md. Key types:
- `FileNode` (Model.swift): the scan tree. Built on worker threads; each folder node is mutated only
  by the worker that owns it. Kinds: folder, file, smallFiles (per-folder roll-up of files < 128 KB),
  hiddenSpace (volume-used minus scanned, added at the root).
- `ScanContext` / `DiskScanner` (DiskScanner.swift): OperationQueue + DispatchGroup walker.
  Folders shallower than `parallelDepth` get their own worker. Dedupe by (dev, inode) for hard links
  and directories (firmlinks). On the startup disk `/System/Volumes` is walked last.
- `ScanSession` (AppModel.swift): one per sidebar entry: phase, result, focus folder, collector.
- `ScanStore`: per-volume saved index in `~/Library/Application Support/Stowmap/Index` (JSON + lzfse,
  entries under ~1 MB rolled up).

## Features (as of 1.3)

Sidebar: search across scanned drives, Duplicates, Copy & Verify, drive list, Scan All Drives, Leave Feedback.
- Maps (Map / Tree / File Types / Largest Files), Collector → Trash, or confirmed permanent delete on
  volumes without a Trash. A network share's map shows only that share's contents.
- Duplicates (Tools.swift): same length → sampled fingerprint → optional full verify. Results are rolled
  up into matching folders. Filters: minimum size, skip system/app files (default on), ignored folders.
  `SystemPaths.isProtected` blocks collecting macOS's own files everywhere.
- Copy & Verify (Transfer.swift, TransferModel.swift, Views/TransferViews.swift): up to three
  destinations, xxHash64/MD5/SHA-256, temp-name writes then rename, conflict policies, MHL + plain
  checksum lists, pause/stop. Check a Copy compares two folders.
- Queue (TransferModel.swift `QueueJob`): copies and checks run one after another; Queue tab shows overall
  and per-job bars, the running job in full, and results of finished jobs. `DockProgress` draws the queue
  bar on the Dock icon. Copy planning and Check a Copy list folders with `DirLister.bulk`, a level at a time
  in parallel; Check a Copy reads both sides at once.
- Pace.swift: what each drive/link should manage; quiet notes only when a job is well under that.
- Network shares are listed with `getattrlistbulk` (DirLister.bulk), falling back to readdir + stat.
- `design/` is the visual source of truth (stageshow-ui mocks; see design/README.md).

## Build, test, release

- `./build.sh --install` / `./build.sh --package` on a Mac (assembles in `$TMPDIR/stowmap-build`).
- **Self-test:** `Stowmap.app/Contents/MacOS/Stowmap --selftest` checks checksums against reference
  values, runs real copies in a temp folder (verify, mismatch, conflicts, lists), Check a Copy, and the
  bulk folder listing. CI runs it on every build; a release cannot publish unless it passes. Extend
  SelfTest.swift whenever the copy engine or scanner listing changes.
- **CI** (`.github/workflows/`): `build.yml` on every push to main; `release.yml` is run by hand
  (inputs: version, notes, runner). It builds, self-tests, publishes the GitHub release, signs with the
  repo secret `SPARKLE_PRIVATE_KEY` and prepends appcast.xml. Use runner `macos-15`; `macos-14` is
  retired and `macos-latest` never gets a machine. GitHub's Mac queue can take 1–15 minutes and
  sometimes cancels; re-run it. Building on Troy's Mac avoids the queue.
- `pages.yml` publishes `docs/` to the `gh-pages` branch, which GitHub Pages serves.
- The update feed is cached for five minutes, so the app sees a release a few minutes after it publishes.
- `GlassCapsule` uses macOS 26 Liquid Glass behind `#if compiler(>=6.2)` so older Xcode still builds.

## Updates (free, no Apple Developer Program)

- Repo must stay **public** so Sparkle can fetch `appcast.xml` and release assets anonymously.
- Sparkle 2 via SwiftPM. Daily check; the user is prompted (`SUAutomaticallyUpdate` is false).
- `SUPublicEDKey` is the **same key as Pulse**. The private key is in Troy's login Keychain and in the
  repo secret. Losing it means installed copies can never update.
- `release.sh` still works for releasing from a Mac.
- Ad-hoc signed: first install needs "Open Anyway" once, and macOS forgets Full Disk Access after each
  update. A Developer ID ($99/yr) would fix both.

## Working with Troy

- He tests every release on real drives (Mac SSD, externals, a multi-share NAS on a 1 Gb link) and
  sends screenshots. Nothing has been run by anyone else.
- Say plainly what was compiled, what the self-test covered, and what has never been run.
- Don't publish changes he asked to hold; a queued release builds whatever is newest on main.
- Feedback form: set `StowmapFeedbackEmail` in Info.plist once he gives an address; until then it opens
  a GitHub issue.

## Website

`docs/` is published to GitHub Pages by `pages.yml` (via the `gh-pages` branch). Static, no build step.
Copy must pass the `banned` skill; no competitor names (`docs/_src/check.py` enforces it).

## Possible follow-ups

- Suggest near-copy folders automatically (Check a Copy needs both folders picked by hand).
- File Types rows that open the largest files of that type.
- Phone-sized cuts of the site videos.
- Privileged helper for protected folders; list/delete local snapshots.
- Growth over time between scans; age filter.
