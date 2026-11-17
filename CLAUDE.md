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

## Build

- `./build.sh --install` / `./build.sh --package` (same as Pulse; assembles in `$TMPDIR/stowmap-build`).
- CI: `.github/workflows/build.yml` builds the universal DMG on every push to main and uploads it as an artifact.
- `GlassCapsule` uses macOS 26 Liquid Glass behind `#if compiler(>=6.2)` so older Xcode still builds.

## Updates & releases (free, no Apple Developer Program)

- Repo must stay **public** so Sparkle can fetch `appcast.xml` and release assets anonymously.
- Sparkle 2 via SwiftPM. Feed: `appcast.xml` on main (raw.githubusercontent). Daily check; the user
  is prompted (`SUAutomaticallyUpdate` is false). Gear menu and app menu both have "Check for Updates…".
- `SUPublicEDKey` is the **same key as Pulse**: Sparkle keeps one EdDSA key in Troy's login Keychain,
  and `sign_update` uses it for both apps. Losing it means installed copies can never update.
- **Ship an update:** `./release.sh 1.1 "notes"` on a clean main. Bumps Info.plist, builds universal,
  zips + DMG, signs, creates the GitHub release, prepends the appcast item, pushes.
  First release: `./release.sh 1.0 "First release."`
- Ad-hoc signed: first install needs "Open Anyway" once. Because the signature changes every build,
  macOS forgets the Full Disk Access grant after each update; users re-tick it. A Developer ID
  ($99/yr) would fix both; set `SIGN_IDENTITY` and add notarization to release.sh.

## Website

`docs/` is served by GitHub Pages (Settings → Pages → main, /docs). Static, no build step.

## Possible follow-ups

- Privileged helper to read protected folders without Full Disk Access; list/delete local snapshots.
- Duplicate finder, growth-over-time comparison between scans, age filter.
- `getattrlistbulk` for faster SMB scans.
