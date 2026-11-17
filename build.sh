#!/bin/bash
# Builds Stowmap.app and optionally installs it or packages it for sharing.
# Usage:  ./build.sh            → builds ./Stowmap.app (Apple Silicon)
#         ./build.sh --install  → builds, copies to /Applications, launches it
#         ./build.sh --package  → builds a universal app (Apple Silicon + Intel if possible)
#                                 and creates ~/Downloads/Stowmap.dmg to send to someone
# Env:    SIGN_IDENTITY  codesign identity (default "-" = ad-hoc; set to "Developer ID Application: …" later)
#         DMG_OUT        where --package writes the DMG (default ~/Downloads/Stowmap.dmg)
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Installing…"
  xcode-select --install || true
  echo "Re-run ./build.sh after the install finishes."
  exit 1
fi

echo "▸ Compiling (release, Apple Silicon)…"
swift build -c release --arch arm64 2>&1 | grep -v "^\[" || true
ARM=".build/arm64-apple-macosx/release/Stowmap"
[ -x "$ARM" ] || ARM=".build/release/Stowmap"
[ -x "$ARM" ] || { echo "Build failed — binary not found."; exit 1; }
BIN="$ARM"

if [ "$MODE" == "--package" ]; then
  echo "▸ Compiling Intel version…"
  swift build -c release --arch x86_64 2>&1 | grep -v "^\[" || true
  X86=".build/x86_64-apple-macosx/release/Stowmap"
  if [ -x "$X86" ] && lipo -create "$ARM" "$X86" -output .build/Stowmap-universal 2>/dev/null; then
    BIN=".build/Stowmap-universal"
    echo "▸ Universal binary: $(lipo -archs "$BIN")"
  else
    echo "▸ Intel build not available — packaging Apple Silicon only (M1/M2/M3/M4 Macs)."
  fi
fi

# Assemble outside the project: ~/Documents syncs via iCloud, whose file attributes
# make codesign fail ("resource fork, Finder information, or similar detritus").
STAGE_DIR="${TMPDIR:-/tmp}/stowmap-build"
APP="$STAGE_DIR/Stowmap.app"
rm -rf "$APP" Stowmap.app
mkdir -p "$STAGE_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Stowmap"
# Sparkle (auto-updates). The SwiftPM xcframework slice is already universal.
ditto "$(dirname "$ARM")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Icon: let Apple's iconutil build it from the PNG set; fall back to the prebuilt file.
if [ -d Resources/Stowmap.iconset ] && iconutil -c icns Resources/Stowmap.iconset -o "$APP/Contents/Resources/Stowmap.icns" 2>/dev/null; then
  echo "▸ Icon built with iconutil"
elif [ -f Resources/Stowmap.icns ]; then
  cp Resources/Stowmap.icns "$APP/Contents/Resources/Stowmap.icns"
fi
xattr -cr "$APP" 2>/dev/null || true

# Sign inside-out (Sparkle's helpers first, then the app). Ad-hoc by default so macOS lets
# it run. Hardened runtime only with a real identity — with
# ad-hoc signing, library validation would refuse to load Sparkle.framework.
IDENTITY="${SIGN_IDENTITY:--}"
CS=(codesign --force --sign "$IDENTITY")
[ "$IDENTITY" != "-" ] && CS+=(--options runtime --timestamp)
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${CS[@]}" "$SPK/XPCServices/Installer.xpc"
"${CS[@]}" --preserve-metadata=entitlements "$SPK/XPCServices/Downloader.xpc"
"${CS[@]}" "$SPK/Autoupdate"
"${CS[@]}" "$SPK/Updater.app"
"${CS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${CS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "▸ Built and signed $APP"

if [ "$MODE" == "--install" ]; then
  pkill -x Stowmap >/dev/null 2>&1 || true
  rm -rf "/Applications/Stowmap.app"
  cp -R "$APP" /Applications/
  echo "▸ Installed to /Applications/Stowmap.app"
  open -a /Applications/Stowmap.app
  echo "▸ Stowmap is running."
fi

if [ "$MODE" == "--package" ]; then
  STAGE="$(mktemp -d)/Stowmap"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cat > "$STAGE/How to open Stowmap.txt" <<'TXT'
STOWMAP — see what is filling every drive on your Mac

INSTALL
1. Drag Stowmap into the Applications folder (in this window).
2. Open Applications and double-click Stowmap.

FIRST LAUNCH (one time only)
Stowmap isn't from the App Store, so macOS will warn you the first time.
  • Click "Done" (or "OK") on the warning.
  • Open System Settings → Privacy & Security.
  • Scroll down to the message about "Stowmap" and click "Open Anyway".
  • Confirm with your password or Touch ID, then click "Open".
After that it opens normally.

USING IT
Pick a drive in the sidebar and click Scan. Click a slice to go into a
folder. The folder button on any row opens it in Finder.

FOR COMPLETE RESULTS
System Settings → Privacy & Security → Full Disk Access → turn on Stowmap,
then rescan. Without it macOS hides Mail, Messages, Safari and some
Library folders from every app.

UPDATES
Stowmap checks once a day. Gear menu → "Check for Updates…" checks now.

Requires macOS 13 Ventura or newer.
TXT
  OUT="${DMG_OUT:-$HOME/Downloads/Stowmap.dmg}"
  rm -f "$OUT"
  hdiutil create -volname "Stowmap" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
  rm -rf "$(dirname "$STAGE")"
  echo "▸ Created $OUT ($(du -h "$OUT" | cut -f1))"
  if [ -z "${DMG_OUT:-}" ]; then open -R "$OUT"; fi
fi
