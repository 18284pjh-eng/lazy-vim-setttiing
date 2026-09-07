#!/usr/bin/env bash
# lazyvim-offline 离线安装器（目标机无需 sudo / root）
#
# 用法:
#   ./install.sh                  # 默认安装/刷新到 ~/.local
#   ./install.sh --keep-config    # 不动目标机已有的 ~/.config/nvim
#   ./install.sh --keep-data      # 不动目标机已有的 ~/.local/share/nvim
#   ./install.sh --prefix DIR     # 自定义安装前缀（默认 ~/.local/opt/lazyvim-offline）
#   ./install.sh --help
set -euo pipefail

RELEASE_VERSION='__RELEASE_VERSION__'
MARKER='.lazyvim-offline-managed'
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(dirname "$SELF_DIR")"
# 防止被 sh/dash 执行导致路径解析错乱
[ -n "$SELF_DIR" ] && [ "$SELF_DIR" != "." ] || die "请用 bash 执行: bash install.sh"

KEEP_CONFIG=0
KEEP_DATA=0
PREFIX="${LAZYVIM_OFFLINE_PREFIX:-$HOME/.local/opt/lazyvim-offline}"
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-config) KEEP_CONFIG=1 ;;
        --keep-data)   KEEP_DATA=1 ;;
        --prefix)      shift; PREFIX="${1:?--prefix 需要参数}";;
        --help|-h)     sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数: $1 (见 --help)" >&2; exit 2 ;;
    esac
    shift
done

log()  { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }
die()  { echo "错误: $*" >&2; exit 1; }

ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || die "本离线包仅支持 x86_64，当前为 $ARCH"
GLIBC_MAJMIN="$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}' | cut -d. -f1-2)"
[ -n "$GLIBC_MAJMIN" ] || die "无法识别 glibc 版本"
IFS=. read -r GLIBC_MAJOR GLIBC_MINOR <<< "$GLIBC_MAJMIN"
if [ "$GLIBC_MAJOR" -lt 2 ] || { [ "$GLIBC_MAJOR" -eq 2 ] && [ "$GLIBC_MINOR" -lt 34 ]; }; then
    die "本离线包需要 glibc >= 2.34，当前为 $GLIBC_MAJMIN"
fi
log "目标机: x86_64, glibc $GLIBC_MAJMIN, PREFIX=$PREFIX"

ts() { date +%Y%m%d-%H%M%S; }

# 修复包内符号链接：部分 7z 版本拒绝提取相对符号链接（或解引用成坏文件）
repair_symlinks() {
    local manifest="$PKG_ROOT/payload/symlinks.tsv"
    [ -f "$manifest" ] || return 0
    local n=0
    while IFS=$'\t' read -r link target; do
        [ -n "$link" ] || continue
        local dest="$PKG_ROOT/$link"
        rm -f "$dest"
        mkdir -p "$(dirname "$dest")"
        ln -s "$target" "$dest"
        n=$((n + 1))
    done < "$manifest"
    log "已修复包内符号链接 $n 条"
}
repair_symlinks

refresh_tree() {
    local source="$1" destination="$2" replacement
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$source/" "$destination/"
        return
    fi
    replacement="${destination}.new-$(ts)"
    rm -rf "$replacement"
    cp -a "$source" "$replacement"
    rm -rf "$destination"
    mv "$replacement" "$destination"
}

log "[1/6] 安装 nvim 本体与 runtime"
mkdir -p "$PREFIX"
rm -rf "$PREFIX/nvim"
cp -a "$PKG_ROOT/payload/nvim" "$PREFIX/nvim"
touch "$PREFIX/nvim/$MARKER"

log "[2/6] 安装离线工具 (rg/fd/node)"
mkdir -p "$PREFIX"
rm -rf "$PREFIX/tools"
cp -a "$PKG_ROOT/payload/tools" "$PREFIX/tools"
touch "$PREFIX/tools/$MARKER"
"$PREFIX/tools/bin/rg" --version >/dev/null || die "包内 rg 无法运行"

log "[3/6] 安装插件/mason/treesitter 数据"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
if [ "$KEEP_DATA" = 1 ] && [ -e "$DATA_DIR" ]; then
    log "  --keep-data: 保留现有 $DATA_DIR（离线工具与 mason 包请自行核对）"
elif [ -e "$DATA_DIR" ] && [ ! -f "$DATA_DIR/$MARKER" ]; then
    b="${DATA_DIR}.backup-$(ts)"
    mv "$DATA_DIR" "$b"
    warn "目标机已有旧数据，已整体备份 -> $b"
    mkdir -p "$(dirname "$DATA_DIR")"
    cp -a "$PKG_ROOT/payload/data/nvim" "$DATA_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$DATA_DIR/$MARKER"
elif [ -d "$DATA_DIR" ]; then
    log "  已是本安装器管理的数据目录，刷新并清理脏文件"
    refresh_tree "$PKG_ROOT/payload/data/nvim" "$DATA_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$DATA_DIR/$MARKER"
else
    mkdir -p "$(dirname "$DATA_DIR")"
    cp -a "$PKG_ROOT/payload/data/nvim" "$DATA_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$DATA_DIR/$MARKER"
fi

log "[4/6] 安装配置到 ~/.config/nvim"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ "$KEEP_CONFIG" = 1 ] && [ -e "$CFG_DIR" ]; then
    log "  --keep-config: 保留现有 $CFG_DIR"
elif [ -e "$CFG_DIR" ] && [ ! -f "$CFG_DIR/$MARKER" ]; then
    b="${CFG_DIR}.backup-$(ts)"
    mv "$CFG_DIR" "$b"
    warn "已有配置已备份 -> $b (含旧 lazy-lock/lazyvim.json 可手动合并)"
    cp -a "$PKG_ROOT/config/nvim" "$CFG_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$CFG_DIR/$MARKER"
elif [ -d "$CFG_DIR" ]; then
    log "  刷新本安装器管理的配置 (--keep-config 可跳过)"
    refresh_tree "$PKG_ROOT/config/nvim" "$CFG_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$CFG_DIR/$MARKER"
else
    mkdir -p "$(dirname "$CFG_DIR")"
    cp -a "$PKG_ROOT/config/nvim" "$CFG_DIR"
    echo "installed-by=$RELEASE_VERSION" > "$CFG_DIR/$MARKER"
fi

log "[5/6] 写入启动包装器 ~/.local/bin/nvim"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
if [ -e "$BIN_DIR/nvim" ] && [ ! -f "$BIN_DIR/nvim.$MARKER" ]; then
    b="$BIN_DIR/nvim.backup-$(ts)"
    mv "$BIN_DIR/nvim" "$b"
    warn "原有 $BIN_DIR/nvim（可能是旧版 nvim）已备份 -> $b"
fi
sed "s|__INSTALL_PREFIX__|$PREFIX|g" "$PKG_ROOT/installer/nvim-wrapper.sh" > "$BIN_DIR/nvim"
chmod 0755 "$BIN_DIR/nvim"
touch "$BIN_DIR/nvim.$MARKER"

# 确保 ~/.local/bin 在 PATH 中（Debian 默认 .profile 已含，缺则补）
PATH_SNIPPET='export PATH="$HOME/.local/bin:$PATH"  # added by lazyvim-offline'
if ! printf '%s' "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    for rc in "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$rc" ] && ! grep -q 'added by lazyvim-offline' "$rc"; then
            printf '\n%s\n' "$PATH_SNIPPET" >> "$rc"
            warn "已在 $rc 追加 PATH（新 shell 生效）"
        fi
    done
fi

log "[6/6] 冒烟测试"
if ! timeout 120 "$BIN_DIR/nvim" --headless '+lua vim.api.nvim_command("qa!")' >/tmp/lazyvim-offline-smoke.log 2>&1; then
    warn "headless 启动失败，日志: /tmp/lazyvim-offline-smoke.log"
    warn "请运行: $BIN_DIR/nvim 查看具体报错"
else
    log "启动成功: $("$BIN_DIR/nvim" --version | awk 'NR==1')"
fi

cat <<EOF

安装完成 (release: $RELEASE_VERSION)
  启动命令 : ~/.local/bin/nvim   (优先于系统旧 nvim，前提 ~/.local/bin 在 PATH 前部)
  安装前缀 : $PREFIX
  配置目录 : $CFG_DIR
  数据目录 : $DATA_DIR

说明:
  - 全程无需 sudo；所有 LSP/formatter (mason 包) 已随包内置，离线可用。
  - pyright 等依赖 node 的工具使用包内 node ($PREFIX/tools/bin/node)。
  - avante/leetcode 等 AI/联网插件需有网络与 API 网关才可用，离线不影响其他功能。
  - 再次运行本脚本可刷新/升级（受管理的目录会 --delete 增量同步）。
EOF
