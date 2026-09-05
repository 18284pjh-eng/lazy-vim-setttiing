#!/usr/bin/env bash
# 对已构建的 7z 发布包做冒烟验证：
#   1) 解压完整性  2) 关键文件存在  3) 干净 HOME 下完整插件加载
# 用法: ./scripts/verify-release.sh dist/lazyvim-offline-<ver>.7z
set -euo pipefail
PKG="${1:?用法: verify-release.sh <dist/*.7z>}"
WORK="$(mktemp -d /tmp/verify-lazyvim-offline.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

log() { echo "==> $*"; }

log "解压 $PKG（新版 7z 会因拒绝相对符号链接报 ERROR/exit=2，属预期，由安装器修复）"
rc=0
7z x -y -bd -bso0 -bsp0 -o"$WORK/pkg" "$PKG" >"$WORK/7z.log" 2>&1 || rc=$?
[ "$rc" -le 2 ] || { echo "7z 解压失败 (rc=$rc):" >&2; tail -20 "$WORK/7z.log" >&2; exit 1; }
[ -f "$WORK/pkg/payload/symlinks.tsv" ] || { echo "缺失 symlinks.tsv" >&2; exit 1; }
echo "--- manifest ---"
cat "$WORK/pkg/payload/manifest.txt"

for f in payload/nvim/bin/nvim payload/nvim/runtime/doc/nvim.txt \
         payload/tools/bin/rg payload/tools/bin/fd payload/tools/bin/node \
         payload/data/nvim/lazy config/nvim/init.lua \
         installer/install.sh installer/nvim-wrapper.sh; do
    [ -e "$WORK/pkg/$f" ] || { echo "缺失: $f" >&2; exit 1; }
done
log "关键文件齐全"

log "模拟全新用户（干净 HOME）端到端安装"
mkdir -p "$WORK/home/.local/bin" "$WORK/home/.config/nvim" "$WORK/home/.local/share/nvim/lazy"
echo "junk" > "$WORK/home/.config/nvim/init.lua"
echo "junk" > "$WORK/home/.local/share/nvim/lazy/old-broken-plugin"
printf '#!/bin/sh\necho old-nvim\n' > "$WORK/home/.local/bin/nvim"
chmod +x "$WORK/home/.local/bin/nvim"
export HOME="$WORK/home"
bash "$WORK/pkg/installer/install.sh" > "$WORK/install.log" 2>&1 \
    || { echo "install.sh 失败:" >&2; tail -20 "$WORK/install.log" >&2; exit 1; }
tail -3 "$WORK/install.log"

BIN="$HOME/.local/bin/nvim"
[ -L "$HOME/.local/share/nvim/mason/bin/pyright" ] || { echo "pyright 不是符号链接" >&2; exit 1; }
[ ! -e "$HOME/.local/share/nvim/lazy/old-broken-plugin" ] || { echo "脏旧数据未被清理" >&2; exit 1; }
ls -d "$HOME"/.local/share/nvim.backup-* >/dev/null 2>&1 || { echo "旧数据未备份" >&2; exit 1; }

log "mason node 工具（依赖包内 node，模拟 wrapper 的 PATH 隔离）"
PREFIX_DIR="$HOME/.local/opt/lazyvim-offline"
( export PATH="$PREFIX_DIR/tools/bin:$PATH"
  "$HOME/.local/share/nvim/mason/bin/pyright" --version || { echo "pyright 不可用" >&2; exit 1; }
) || exit 1

log "干净 HOME 下完整插件启动"
mkdir -p "$HOME/.cache" "$HOME/.local/state"
timeout 300 "$BIN" --headless '+lua vim.defer_fn(function()
    local plug = require("lazy.core.config").plugins or {}
    local n = 0
    for _, _ in pairs(plug) do n = n + 1 end
    print("插件注册: " .. n)
    print("rg: " .. (vim.fn.executable("rg") == 1 and "ok" or "MISSING"))
    vim.api.nvim_command("qa!")
end, 20000)' 2>&1 | tail -3

log "全部通过 ✓"
