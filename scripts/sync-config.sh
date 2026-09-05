#!/usr/bin/env bash
# 把本机 ~/.config/nvim 的最新配置同步到仓库 config/nvim/（git 管理）。
# 用法: ./scripts/sync-config.sh [--no-commit]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${NVIM_CONFIG_SRC:-$HOME/.config/nvim}"
DST="$REPO_ROOT/config/nvim"

[ -d "$SRC" ] || { echo "错误: 找不到源配置 $SRC" >&2; exit 1; }

mkdir -p "$DST"
rsync -a --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    "$SRC/" "$DST/"

echo "已同步 $SRC -> $DST"
echo "变更文件:"
git -C "$REPO_ROOT" status --short config/ || true

if [ "${1:-}" != "--no-commit" ]; then
    if ! git -C "$REPO_ROOT" diff --quiet -- config/ || \
       ! git -C "$REPO_ROOT" diff --cached --quiet -- config/ || \
       [ -n "$(git -C "$REPO_ROOT" status --porcelain config/)" ]; then
        git -C "$REPO_ROOT" add config/
        git -C "$REPO_ROOT" commit -m "config: 同步本机 nvim 配置 $(date +%F' '%H:%M)"
        echo "已提交配置变更。"
    else
        echo "配置无变化，无需提交。"
    fi
fi
