#!/bin/sh
# lazyvim-offline 自解压安装包头部（后面紧跟一个 tar.gz）
# 用法: ./lazyvim-offline-<ver>.run [--keep-config] [--keep-data] [--prefix DIR]
set -eu
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lazyvim-offline.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

OFFSET="$(awk '/^__PAYLOAD_BELOW__$/{print NR+1; exit}' "$0")"
[ -n "$OFFSET" ] || { echo "损坏的安装包: 找不到 payload 标记" >&2; exit 1; }

echo "==> 解压到 $TMP ..."
tail -n +"$OFFSET" "$0" | tar -xzf - -C "$TMP"

echo "==> 开始安装 ..."
if command -v bash >/dev/null 2>&1; then
    bash "$TMP/installer/install.sh" "$@"
else
    echo "错误: 需要 bash 才能安装" >&2
    exit 1
fi

# 该标记行之后紧跟 tar.gz 载荷，不要手动编辑本行以下内容
__PAYLOAD_BELOW__
