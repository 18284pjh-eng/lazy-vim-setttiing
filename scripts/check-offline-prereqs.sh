#!/usr/bin/env bash
# Validate the cached Neovim runtime before an offline payload is copied.
# The lists below mirror config/nvim/lazyvim.json and lua/plugins/*.lua.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${NVIM_DATA_DIR:-$HOME/.local/share/nvim}"
LOCK_FILE="$REPO_ROOT/config/nvim/lazy-lock.json"

MASON_PACKAGES=(
    bash-language-server clangd lua-language-server markdown-toc markdownlint-cli2
    marksman pyright ruff shellcheck shfmt stylua verible
)
# Keep this list aligned with MASON_PACKAGES.  A package directory alone is
# not useful in an air-gapped install if its launcher is absent or broken.
MASON_BINARIES=(
    bash-language-server clangd lua-language-server markdown-toc markdownlint-cli2
    marksman pyright ruff shellcheck shfmt stylua verible-verilog-ls
)
MASON_CHECK_ARGS=(
    --version --version --version /dev/null --version
    --version --version --version --version --version --version --version
)
PARSERS=(
    bash c cpp diff git_config html javascript jsdoc json lua luadoc luap markdown
    markdown_inline ninja printf python query regex rst systemverilog toml tsx typescript
    vim vimdoc xml yaml
)

missing=0
fail() {
    printf '  - %s\n' "$*" >&2
    missing=1
}

[ -f "$LOCK_FILE" ] || { echo "错误: 找不到 $LOCK_FILE" >&2; exit 1; }
[ -d "$DATA_DIR/lazy" ] || fail "缺少插件目录: $DATA_DIR/lazy"
[ -d "$DATA_DIR/mason" ] || fail "缺少 Mason 目录: $DATA_DIR/mason"
[ -d "$DATA_DIR/site/parser" ] || fail "缺少 Treesitter parser 目录: $DATA_DIR/site/parser"

if [ -d "$DATA_DIR/lazy" ]; then
    mapfile -t LOCKED_PLUGINS < <(
        sed -nE 's/^[[:space:]]*"([^"[:space:]]+)"[[:space:]]*:[[:space:]]*\{.*"commit"[[:space:]]*:[[:space:]]*"([0-9a-f]+)".*/\1\t\2/p' "$LOCK_FILE"
    )
    [ "${#LOCKED_PLUGINS[@]}" -gt 0 ] || fail "lazy-lock.json 中没有可验证的插件提交"
    for locked in "${LOCKED_PLUGINS[@]}"; do
        IFS=$'\t' read -r plugin expected_commit <<< "$locked"
        plugin_dir="$DATA_DIR/lazy/$plugin"
        [ -d "$plugin_dir" ] || { fail "缺少锁定插件: $plugin"; continue; }
        actual_commit="$(git -C "$plugin_dir" rev-parse HEAD 2>/dev/null || true)"
        [ "$actual_commit" = "$expected_commit" ] \
            || fail "插件提交不匹配: $plugin（期望 $expected_commit，实际 ${actual_commit:-无 git 元数据}）"
    done
fi

if [ -d "$DATA_DIR/mason/packages" ]; then
    for i in "${!MASON_PACKAGES[@]}"; do
        package="${MASON_PACKAGES[$i]}"
        binary="${MASON_BINARIES[$i]}"
        check_arg="${MASON_CHECK_ARGS[$i]}"
        [ -d "$DATA_DIR/mason/packages/$package" ] || fail "缺少 Mason 包: $package"
        launcher="$DATA_DIR/mason/bin/$binary"
        [ -x "$launcher" ] || { fail "缺少或不可执行的 Mason 启动器: $binary（包: $package）"; continue; }
        "$launcher" "$check_arg" >/dev/null 2>&1 \
            || fail "Mason 启动器无法运行: $binary"
    done
else
    fail "缺少 Mason package 目录: $DATA_DIR/mason/packages"
fi

if [ -d "$DATA_DIR/site/parser" ]; then
    for parser in "${PARSERS[@]}"; do
        [ -f "$DATA_DIR/site/parser/$parser.so" ] || fail "缺少 Treesitter parser: $parser"
    done
fi

if [ "$missing" -ne 0 ]; then
    cat >&2 <<EOF

离线 payload 未生成。请仅在可联网的构建机补齐以上项目，再重新运行本检查。
插件提交不匹配时先执行 :Lazy restore；缺插件、Mason 包或 parser 时按上方名称显式安装。
内网目标机不要运行 :Lazy sync、:MasonUpdate 或 :TSUpdate。
EOF
    exit 1
fi

echo "离线运行时预检通过: plugins=$(find "$DATA_DIR/lazy" -mindepth 1 -maxdepth 1 -type d | wc -l), mason=${#MASON_PACKAGES[@]}, parsers=${#PARSERS[@]}"
