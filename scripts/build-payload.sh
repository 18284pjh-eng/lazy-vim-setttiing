#!/usr/bin/env bash
# 从本机收集离线部署所需的全部二进制与数据到 payload/（git 忽略，不入库）。
# 可重复执行（幂等）。用法: ./scripts/build-payload.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$REPO_ROOT/payload"

NVIM_BIN="${NVIM_BIN:-$(command -v nvim)}"
NVIM_RUNTIME_DIR="${NVIM_RUNTIME_DIR:-$(dirname "$(dirname "$NVIM_BIN")")/share/nvim/runtime}"
NODE_BIN="${NODE_BIN:-$(command -v node)}"
DATA_DIR="${NVIM_DATA_DIR:-$HOME/.local/share/nvim}"

err() { echo "错误: $*" >&2; exit 1; }

[ -x "$NVIM_BIN" ] || err "找不到可执行 nvim (可用 NVIM_BIN=... 指定)"
[ -d "$NVIM_RUNTIME_DIR" ] || err "找不到 nvim runtime 目录: $NVIM_RUNTIME_DIR"
[ -x "$NODE_BIN" ] || err "找不到 node (mason 中 pyright 等依赖它)"
[ -d "$DATA_DIR/lazy" ] || err "找不到插件目录 $DATA_DIR/lazy"

echo "==> 1/5 nvim 本体与 runtime"
mkdir -p "$P/nvim/bin"
install -m 0755 "$NVIM_BIN" "$P/nvim/bin/nvim"
rsync -a --delete "$NVIM_RUNTIME_DIR/" "$P/nvim/runtime/"

echo "==> 2/5 独立工具 (rg/fd/node)"
mkdir -p "$P/tools/bin"
for t in rg fd; do
    src="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$src" ] || err "缺少工具 $t (LazyVim 搜索依赖)"
    install -m 0755 "$src" "$P/tools/bin/$t"
done
install -m 0755 "$NODE_BIN" "$P/tools/bin/node"

echo "==> 3/5 插件 (lazy) / treesitter parser (site) / mason 包"
for d in lazy site mason; do
    [ -d "$DATA_DIR/$d" ] || { echo "  跳过 $d (不存在)"; continue; }
    mkdir -p "$P/data/nvim/$d"
    rsync -a --delete "$DATA_DIR/$d/" "$P/data/nvim/$d/"
done

echo "==> 4/5 清理 payload 中的临时/缓存文件"
find "$P" -type d \( -name '__pycache__' -o -name '.pytest_cache' \) -prune -exec rm -rf {} + 2>/dev/null || true

echo "==> 5/5 生成清单 manifest.txt"
{
    echo "lazyvim-offline payload manifest"
    echo "构建时间: $(date -Is)"
    echo "构建主机: $(uname -srm) / $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "nvim: $($P/nvim/bin/nvim --version | awk 'NR==1')"
    echo "node: $($P/tools/bin/node --version)"
    echo "rg:   $($P/tools/bin/rg --version | awk 'NR==1')"
    echo "fd:   $($P/tools/bin/fd --version)"
    echo "插件数: $(ls "$P/data/nvim/lazy" 2>/dev/null | wc -l)"
    echo "mason 包: $(ls "$P/data/nvim/mason/packages" 2>/dev/null | tr '\n' ' ')"
    echo "treesitter parser: $(ls "$P/data/nvim/site/parser"/*.so 2>/dev/null | wc -l) 个 .so"
    echo "--- sha256 ---"
    (cd "$P" && sha256sum nvim/bin/nvim tools/bin/* 2>/dev/null) || true
} > "$P/manifest.txt"
cat "$P/manifest.txt"

echo "==> payload 构建完成: $P ($(du -sh "$P" | cut -f1))"
