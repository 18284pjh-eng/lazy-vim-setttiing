#!/usr/bin/env bash
# Generate compile_commands.json from compiler commands printed by Rake.
# This intentionally supports only visible compiler commands; hdlmgr/SDK
# integrations that hide their command line need an explicit adapter.
set -euo pipefail

usage() {
    cat <<'EOF'
用法: compiledb-rake [rake 任务或选项...]

以 rake --build-all --verbose 执行构建，解析输出中可见的 GCC/Clang 命令，
并在当前项目根生成 compile_commands.json。

构建失败时仍会保留可解析的部分数据库，并返回原始 rake 退出码。
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

command -v compiledb >/dev/null 2>&1 || {
    echo "错误: 找不到 compiledb；请从 LazyVim 离线包的 nvim 包装器启动，或把 tools/bin 加入 PATH" >&2
    exit 127
}
command -v rake >/dev/null 2>&1 || {
    echo "错误: 找不到 rake；请安装项目所需的 Ruby/Rake 运行时" >&2
    exit 127
}

build_log="$(mktemp "${TMPDIR:-/tmp}/compiledb-rake.XXXXXX.log")"
trap 'rm -f "$build_log"' EXIT

set +e
rake --build-all --verbose "$@" 2>&1 | tee "$build_log"
rake_status=${PIPESTATUS[0]}
set -e

set +e
compiledb --full-path --overwrite --build-dir "$PWD" --parse "$build_log"
parse_status=$?
set -e

if [ "$rake_status" -ne 0 ]; then
    exit "$rake_status"
fi
exit "$parse_status"
