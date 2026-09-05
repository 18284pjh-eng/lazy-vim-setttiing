#!/usr/bin/env bash
# 对已构建的 7z 发布包做冒烟验证：
#   1) 解压完整性  2) 关键文件存在  3) 干净 HOME 下完整插件加载
# 用法: ./scripts/verify-release.sh dist/lazyvim-offline-<ver>.7z
set -euo pipefail
PKG="${1:?用法: verify-release.sh <dist/*.7z>}"
WORK="$(mktemp -d /tmp/verify-lazyvim-offline.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

log() { echo "==> $*"; }

log "解压 $PKG"
7z x -bd -bso0 -bsp0 -o"$WORK/pkg" "$PKG"
echo "--- manifest ---"
cat "$WORK/pkg/payload/manifest.txt"

for f in payload/nvim/bin/nvim payload/nvim/runtime/doc/nvim.txt \
         payload/tools/bin/rg payload/tools/bin/fd payload/tools/bin/node \
         payload/data/nvim/lazy config/nvim/init.lua \
         installer/install.sh installer/nvim-wrapper.sh; do
    [ -e "$WORK/pkg/$f" ] || { echo "缺失: $f" >&2; exit 1; }
done
log "关键文件齐全"

log "模拟全新用户（干净 HOME）完整启动"
mkdir -p "$WORK/home"
export HOME="$WORK/home"
export XDG_DATA_HOME="$WORK/home/.local/share"
export XDG_CONFIG_HOME="$WORK/home/.config"
export XDG_STATE_HOME="$WORK/home/.local/state"
export XDG_CACHE_HOME="$WORK/home/.cache"
export PATH="$WORK/pkg/payload/tools/bin:$PATH"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
cp -a "$WORK/pkg/payload/data/nvim" "$XDG_DATA_HOME/nvim"
cp -a "$WORK/pkg/config/nvim" "$XDG_CONFIG_HOME/nvim"

RTP_ADD="$WORK/pkg/payload/nvim/runtime"
# --cmd 阶段: 注入 runtime; 稍后延迟退出, 给 lazy.nvim 足够时间恢复插件
timeout 300 "$WORK/pkg/payload/nvim/bin/nvim" --headless \
    --cmd "set rtp^=$RTP_ADD" \
    --cmd "set rtp^=$XDG_DATA_HOME/nvim/lazy/lazy.nvim" \
    '+lua vim.defer_fn(function()
        local plug = require("lazy.core.config").plugins or {}
        local ok, disabled = 0, {}
        for name, p in pairs(plug) do
            if p._.loaded then ok = ok + 1 else disabled[#disabled+1] = name end
        end
        print(string.format("插件加载: %d 已加载 / %d 按需(未加载)", ok, #disabled))
        vim.api.nvim_command("qa!")
    end, 20000)' 2>&1 | tail -5

log "全部通过 ✓"
