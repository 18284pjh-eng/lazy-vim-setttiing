#!/usr/bin/env bash
# 打离线发布包。产出（dist/ 下）:
#   lazyvim-offline-<ver>.7z    主发布物（7z，目标机需 7z 解压）
#   lazyvim-offline-<ver>.run   自解压回退包（目标机只要有 tar+gzip 即可）
#   SHA256SUMS
# 用法: ./scripts/build-release.sh [版本号]   # 默认 v<日期>-<git描述>
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GIT_DESC="$(git describe --tags --always --dirty 2>/dev/null || echo nogit)"
VERSION="${1:-v$(date +%Y%m%d)-${GIT_DESC}}"
STAGING="$REPO_ROOT/dist/staging"
OUT="$REPO_ROOT/dist"
NAME="lazyvim-offline-${VERSION}"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> 版本: $VERSION"

echo "==> 1/5 构建/刷新 payload（从本机收集二进制与数据）"
./scripts/build-payload.sh

echo "==> 2/5 组装发布目录"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a payload "$STAGING/payload"
cp -a config "$STAGING/config"
cp -a installer "$STAGING/installer"
cp -a README.md "$STAGING/"
cp -a docs/INSTALL-ONLINE.md "$STAGING/INSTALL.md" 2>/dev/null || true

# 注入版本号
sed -i "s|__RELEASE_VERSION__|${VERSION} (${GIT_DESC}, 打包于 ${RUN_STAMP})|" \
    "$STAGING/installer/install.sh"
cp payload/manifest.txt "$STAGING/payload/manifest.txt"

# 记录全部符号链接：部分 7z 版本会拒绝/解引用相对符号链接，
# install.sh 启动时依据本清单修复（见 repair_symlinks）。
( cd "$STAGING" && find payload -type l -printf '%p\t%l\n' | sort > payload/symlinks.tsv )
echo "    符号链接清单: $(wc -l < "$STAGING/payload/symlinks.tsv") 条"

echo "==> 3/5 生成 7z 主发布包"
# -snl: 保留符号链接（mason/bin 下是相对符号链接，解引用会破坏 node 工具的模块解析）
( cd "$STAGING" && 7z a -mx=7 -snl -bd -bso0 -bsp0 "$OUT/${NAME}.7z" . )
echo "    $(du -h "$OUT/${NAME}.7z" | cut -f1)  $OUT/${NAME}.7z"

echo "==> 4/5 生成自解压 .run 回退包（目标机无需 7z，仅需 tar+gzip）"
TARBALL="$OUT/.${NAME}.payload.tar.gz"
tar -C "$STAGING" --owner=0 --group=0 -czf "$TARBALL" .
{
    cat "$REPO_ROOT/scripts/selfextract-stub.sh"
    cat "$TARBALL"
} > "$OUT/${NAME}.run"
chmod 0755 "$OUT/${NAME}.run"
rm -f "$TARBALL"
echo "    $(du -h "$OUT/${NAME}.run" | cut -f1)  $OUT/${NAME}.run"

echo "==> 5/5 git bundle 与校验和"
CHECKSUMS="${NAME}.SHA256SUMS"
if git diff --quiet && git diff --cached --quiet \
    && [ -z "$(git ls-files --others --exclude-standard)" ] \
    && git bundle create "$OUT/${NAME}.repo.bundle" --all 2>/dev/null; then
    ( cd "$OUT" && sha256sum "${NAME}.7z" "${NAME}.run" "${NAME}.repo.bundle" > "$CHECKSUMS" )
    echo "    已附带 git bundle（离线源码溯源）"
else
    ( cd "$OUT" && sha256sum "${NAME}.7z" "${NAME}.run" > "$CHECKSUMS" )
    echo "    git bundle 跳过（工作区未提交或无提交历史；包内 config 仍为完整安装源）"
fi

rm -rf "$STAGING"
echo
echo "发布物就绪:"
ls -lh "$OUT" | grep -v '^total'
echo
echo "离线传输到内网后安装:"
echo "  7z 包 : 7z x ${NAME}.7z -olazyvim-offline && cd lazyvim-offline && ./installer/install.sh"
echo "  .run  : chmod +x ${NAME}.run && ./${NAME}.run [--keep-config] [--keep-data]"
