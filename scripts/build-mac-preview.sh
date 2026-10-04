#!/usr/bin/env bash
# Local preview build with Command Line Tools; Xcode remains the release build path.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo 'This build requires macOS.' >&2; exit 1; fi
if [ "$#" -ne 1 ]; then echo 'Usage: bash scripts/build-mac-preview.sh /absolute/output/directory' >&2; exit 1; fi
PREVIEW_OUTPUT="$1"
case "$PREVIEW_OUTPUT" in /*) ;; *) echo 'An absolute output path is required.' >&2; exit 1 ;; esac
mkdir -p "$PREVIEW_OUTPUT"
PREVIEW_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/coucou-preview.XXXXXX")"
trap 'rm -rf "$PREVIEW_BUILD"' EXIT
PREVIEW_APP="$PREVIEW_BUILD/Coucou Preview.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
PREVIEW_ARCH="$(uname -m)"
[ "$PREVIEW_ARCH" != x86_64 ] || PREVIEW_ARCH=x86_64
swiftc -parse-as-library -swift-version 6 -target "$PREVIEW_ARCH-apple-macos15.0" \
  -module-cache-path "$PREVIEW_BUILD/module-cache" -module-name Coucou \
  NotchBuddy/Sources/App/*.swift -o "$PREVIEW_APP/Contents/MacOS/Coucou"
cp -R NotchBuddy/Resources/sounds "$PREVIEW_APP/Contents/Resources/sounds"
cp NotchBuddy/Assets.xcassets/MenuBarIcon.imageset/menubar.png "$PREVIEW_APP/Contents/Resources/MenuBarIcon.png"
cp NotchBuddy/Assets.xcassets/MenuBarIcon.imageset/menubar@2x.png "$PREVIEW_APP/Contents/Resources/MenuBarIcon@2x.png"
mkdir -p "$PREVIEW_BUILD/AppIcon.iconset"
cp NotchBuddy/Assets.xcassets/AppIcon.appiconset/*.png "$PREVIEW_BUILD/AppIcon.iconset/"
iconutil --convert icns "$PREVIEW_BUILD/AppIcon.iconset" --output "$PREVIEW_APP/Contents/Resources/AppIcon.icns"
python3 - "$PREVIEW_APP/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
info = plistlib.loads(Path('NotchBuddy/Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='Coucou', CFBundleDevelopmentRegion='fr', CFBundleName='Coucou Preview',
            CFBundleDisplayName='Coucou Preview', CFBundleIconFile='AppIcon', LSMinimumSystemVersion='15.0',
            CFBundleShortVersionString='0.2.2', CFBundleVersion='3')
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - --options runtime --entitlements NotchBuddy/Resources/Coucou.entitlements "$PREVIEW_APP"
codesign --verify --strict "$PREVIEW_APP"
# Produce a single downloadable bundle; never install or launch as part of building.
ditto -c -k --keepParent "$PREVIEW_APP" "$PREVIEW_OUTPUT/Coucou-Preview-macOS.zip"
echo "Created $PREVIEW_OUTPUT/Coucou-Preview-macOS.zip"
