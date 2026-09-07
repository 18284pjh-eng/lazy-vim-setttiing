#!/usr/bin/env bash
# 对已构建的 7z 或 .run 发布包做冒烟验证：
#   1) 解压/自解压完整性  2) 关键文件存在  3) 干净 HOME 下完整插件加载
# 用法: ./scripts/verify-release.sh dist/lazyvim-offline-<ver>.7z|.run
set -euo pipefail
PKG="${1:?用法: verify-release.sh <dist/*.7z|*.run>}"
WORK="$(mktemp -d /tmp/verify-lazyvim-offline.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

log() { echo "==> $*"; }

log "模拟全新用户（干净 HOME）端到端安装"
mkdir -p "$WORK/home/.local/bin" "$WORK/home/.config/nvim" "$WORK/home/.local/share/nvim/lazy"
echo "junk" > "$WORK/home/.config/nvim/init.lua"
echo "junk" > "$WORK/home/.local/share/nvim/lazy/old-broken-plugin"
printf '#!/bin/sh\necho old-nvim\n' > "$WORK/home/.local/bin/nvim"
chmod +x "$WORK/home/.local/bin/nvim"
export HOME="$WORK/home"

case "$PKG" in
    *.7z)
        log "解压 $PKG（部分 7z 会拒绝相对符号链接；安装器会依据清单修复）"
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
        bash "$WORK/pkg/installer/install.sh" > "$WORK/install.log" 2>&1 \
            || { echo "install.sh 失败:" >&2; tail -20 "$WORK/install.log" >&2; exit 1; }
        ;;
    *.run)
        [ -x "$PKG" ] || { echo ".run 不可执行: $PKG" >&2; exit 1; }
        bash "$PKG" > "$WORK/install.log" 2>&1 \
            || { echo ".run 安装失败:" >&2; tail -20 "$WORK/install.log" >&2; exit 1; }
        ;;
    *)
        echo "只支持 .7z 或 .run: $PKG" >&2
        exit 2
        ;;
esac
tail -3 "$WORK/install.log"

BIN="$HOME/.local/bin/nvim"
[ ! -e "$HOME/.local/share/nvim/lazy/old-broken-plugin" ] || { echo "脏旧数据未被清理" >&2; exit 1; }
ls -d "$HOME"/.local/share/nvim.backup-* >/dev/null 2>&1 || { echo "旧数据未备份" >&2; exit 1; }

MASON_PACKAGES=(
    bash-language-server clangd lua-language-server markdown-toc markdownlint-cli2
    marksman pyright ruff shellcheck shfmt stylua verible
)
MASON_BINARIES=(
    bash-language-server clangd lua-language-server markdown-toc markdownlint-cli2
    marksman pyright ruff shellcheck shfmt stylua verible-verilog-ls
)
MASON_CHECK_ARGS=(
    --version --version --version /dev/null --version
    --version --version --version --version --version --version --version
)
for package in "${MASON_PACKAGES[@]}"; do
    [ -d "$HOME/.local/share/nvim/mason/packages/$package" ] \
        || { echo "缺少 Mason 包: $package" >&2; exit 1; }
done
for parser in cpp git_config ninja rst systemverilog; do
    [ -f "$HOME/.local/share/nvim/site/parser/$parser.so" ] \
        || { echo "缺少 Treesitter parser: $parser" >&2; exit 1; }
done

log "全部 Mason 启动器（模拟 wrapper 的 PATH 隔离）"
PREFIX_DIR="$HOME/.local/opt/lazyvim-offline"
for i in "${!MASON_BINARIES[@]}"; do
    binary="${MASON_BINARIES[$i]}"
    check_arg="${MASON_CHECK_ARGS[$i]}"
    ( export PATH="$PREFIX_DIR/tools/bin:$PATH"
      "$HOME/.local/share/nvim/mason/bin/$binary" "$check_arg" >/dev/null \
        || { echo "Mason 启动器不可用: $binary" >&2; exit 1; }
    ) || exit 1
done

log "干净 HOME 下完整插件启动"
mkdir -p "$HOME/.cache" "$HOME/.local/state"
timeout 300 "$BIN" --headless '+lua vim.defer_fn(function()
    local plug = require("lazy.core.config").plugins or {}
    local n = 0
    for _, _ in pairs(plug) do n = n + 1 end
    local expected_runtime = vim.env.HOME .. "/.local/opt/lazyvim-offline/nvim/runtime"
    assert(vim.env.VIMRUNTIME == expected_runtime, "VIMRUNTIME 未指向包内 runtime: " .. vim.env.VIMRUNTIME)
    assert(n >= 48, "LazyVim 插件未完整加载，注册数: " .. n)
    assert(vim.fn.executable("rg") == 1, "rg 不可用")
    assert(vim.fn.executable("fd") == 1, "fd 不可用")
    local rg_version = vim.fn.system({ "rg", "--version" })
    assert(vim.v.shell_error == 0 and #rg_version > 0, "rg 无法启动")
    assert(vim.o.clipboard == "", "无图形会话时不应强制系统剪贴板")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "clipboard-check" })
    vim.cmd("normal! gg0yy")
    assert(vim.fn.getreg("0") == "clipboard-check\n", "内部复制失败")
    vim.fn.setreg("+", "clipboard-check")
    assert(vim.fn.getreg("+") == "clipboard-check", "+ 寄存器后备复制失败")
    print("插件注册: " .. n)
    print("rg/fd/clipboard: ok")
    vim.api.nvim_command("qa!")
end, 20000)' 2>&1 | tail -3

log "C 缓冲区 clangd 附着"
mkdir -p "$WORK/workspace"
touch "$WORK/workspace/test.c"
timeout 90 "$BIN" --headless "$WORK/workspace/test.c" '+lua vim.defer_fn(function()
    local attached = false
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      attached = attached or client.name == "clangd"
    end
    assert(attached, "clangd 未附着到 C 缓冲区")
    print("clangd: attached")
    vim.cmd("qa!")
end, 12000)' 2>&1 | tail -3

log "全部通过 ✓"
