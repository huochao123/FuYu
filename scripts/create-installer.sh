#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/outputs"
DMG_STAGE="$ROOT_DIR/work/dmg-stage"
BACKUP_STAGE="$ROOT_DIR/work/personal-backup"
DMG_PATH="$OUTPUT_DIR/浮屿安装包.dmg"
BACKUP_PATH="$OUTPUT_DIR/浮屿个人配置备份.zip"

"$ROOT_DIR/scripts/package-app.sh"

rm -rf "$DMG_STAGE" "$BACKUP_STAGE" "$DMG_PATH" "$BACKUP_PATH"
mkdir -p "$DMG_STAGE" "$BACKUP_STAGE/配置" "$OUTPUT_DIR"

ditto "$OUTPUT_DIR/浮屿.app" "$DMG_STAGE/浮屿.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT_DIR/INSTALL.md" "$DMG_STAGE/安装说明.md"

hdiutil create \
    -volname "浮屿安装" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -d "$HOME/Library/Application Support/FuYu" ]]; then
    ditto "$HOME/Library/Application Support/FuYu" "$BACKUP_STAGE/配置/FuYu"
fi
if [[ -f "$HOME/Library/Preferences/ai.fuyu.desktop.plist" ]]; then
    cp "$HOME/Library/Preferences/ai.fuyu.desktop.plist" "$BACKUP_STAGE/配置/ai.fuyu.desktop.plist"
fi
cp "$ROOT_DIR/scripts/restore-personal-config.command" "$BACKUP_STAGE/恢复浮屿配置.command"
cp "$ROOT_DIR/INSTALL.md" "$BACKUP_STAGE/请先阅读.md"
chmod 700 "$BACKUP_STAGE/恢复浮屿配置.command"

ditto -c -k --sequesterRsrc --keepParent "$BACKUP_STAGE" "$BACKUP_PATH"
chmod 600 "$BACKUP_PATH"

echo "$DMG_PATH"
echo "$BACKUP_PATH"
