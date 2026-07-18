#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/outputs/浮屿.app"
CONFIGURATION="${CONFIGURATION:-release}"
ICONSET_DIR="$ROOT_DIR/work/AppIcon.iconset"

DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"
for old_path in "$APP_DIR" "$ICONSET_DIR"; do
    [[ ! -e "$old_path" ]] || /usr/bin/trash "$old_path"
done
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$ICONSET_DIR"
cp "$ROOT_DIR/.build/$CONFIGURATION/MiMoMac" "$APP_DIR/Contents/MacOS/FuYu"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/fuyu_feishu_bridge.py" "$APP_DIR/Contents/Resources/fuyu_feishu_bridge.py"
ditto "$ROOT_DIR/Resources/MacSkills" "$APP_DIR/Contents/Resources/MacSkills"
ditto "$ROOT_DIR/Resources/Personas" "$APP_DIR/Contents/Resources/Personas"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR/Vendor/DustyCleanerEngine/LICENSE" "$APP_DIR/Contents/Resources/DustyCleanerEngine-LICENSE.txt"

rsvg-convert -w 16 -h 16 -o "$ICONSET_DIR/icon_16x16.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 32 -h 32 -o "$ICONSET_DIR/icon_16x16@2x.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 32 -h 32 -o "$ICONSET_DIR/icon_32x32.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 64 -h 64 -o "$ICONSET_DIR/icon_32x32@2x.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 128 -h 128 -o "$ICONSET_DIR/icon_128x128.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 256 -h 256 -o "$ICONSET_DIR/icon_128x128@2x.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 256 -h 256 -o "$ICONSET_DIR/icon_256x256.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 512 -h 512 -o "$ICONSET_DIR/icon_256x256@2x.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 512 -h 512 -o "$ICONSET_DIR/icon_512x512.png" "$ROOT_DIR/Resources/AppIcon.svg"
rsvg-convert -w 1024 -h 1024 -o "$ICONSET_DIR/icon_512x512@2x.png" "$ROOT_DIR/Resources/AppIcon.svg"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
