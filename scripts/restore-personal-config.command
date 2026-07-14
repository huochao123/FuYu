#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HERE/配置"

pkill -x FuYu 2>/dev/null || true
mkdir -p "$HOME/Library/Application Support/FuYu" "$HOME/Library/Preferences"

if [[ -d "$SOURCE/FuYu" ]]; then
    ditto "$SOURCE/FuYu" "$HOME/Library/Application Support/FuYu"
    chmod 700 "$HOME/Library/Application Support/FuYu"
    [[ ! -f "$HOME/Library/Application Support/FuYu/credentials.json" ]] || chmod 600 "$HOME/Library/Application Support/FuYu/credentials.json"
fi

if [[ -f "$SOURCE/ai.fuyu.desktop.plist" ]]; then
    cp "$SOURCE/ai.fuyu.desktop.plist" "$HOME/Library/Preferences/ai.fuyu.desktop.plist"
fi

osascript -e 'display dialog "浮屿个人配置已恢复。现在可以从“应用程序”打开浮屿。" buttons {"好"} default button 1 with icon note'

