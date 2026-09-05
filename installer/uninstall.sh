#!/usr/bin/env bash
# 卸载 lazyvim-offline，并可选择恢复最近的备份。
# 用法: ./uninstall.sh [--restore-backups]
set -euo pipefail
MARKER='.lazyvim-offline-managed'
RESTORE=0
[ "${1:-}" = "--restore-backups" ] && RESTORE=1

PREFIX="${LAZYVIM_OFFLINE_PREFIX:-$HOME/.local/opt/lazyvim-offline}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
BIN="$HOME/.local/bin/nvim"

remove_managed() {
    [ -e "$1" ] || return 0
    if [ -f "$1/$MARKER" ] || [ -f "$1.$MARKER" ]; then
        rm -rf "$1"
        echo "已删除 $1"
    else
        echo "跳过 $1 (非本安装器管理)"
    fi
}

remove_managed "$PREFIX"
remove_managed "$DATA_DIR"
remove_managed "$CFG_DIR"
[ -e "$BIN" ] && [ -f "$BIN.$MARKER" ] && rm -f "$BIN" "$BIN.$MARKER" && echo "已删除 $BIN"

if [ "$RESTORE" = 1 ]; then
    for p in "$DATA_DIR" "$CFG_DIR" "$BIN"; do
        latest="$(ls -1dt "${p}".backup-* 2>/dev/null | head -1 || true)"
        if [ -n "$latest" ]; then
            mv "$latest" "$p"
            echo "已恢复 $latest -> $p"
        fi
    done
fi
echo "卸载完成。"
