#!/usr/bin/env bash
# Offline regression tests for Make and visible-Rake compilation databases.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="$REPO_ROOT/third_party/compiledb-go/v1.7.1/compiledb-linux-amd64.txz"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/compiledb-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "失败: $*" >&2; exit 1; }
contains() { rg -F -- "$1" "$2" >/dev/null || fail "数据库缺少: $1"; }

tar -xJf "$ARCHIVE" -C "$WORK"
COMPILEDB="$WORK/compiledb"
[ -x "$COMPILEDB" ] || fail "无法解出 compiledb"

PROJECT="$WORK/project"
mkdir -p "$PROJECT/bin" "$PROJECT/include" "$PROJECT/src"
touch "$PROJECT/src/rv.c" "$PROJECT/src/arm.c"
for compiler in riscv64-unknown-elf-gcc aarch64-none-elf-gcc; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$PROJECT/bin/$compiler"
    chmod 0755 "$PROJECT/bin/$compiler"
done

printf '%s\n' \
    'all: build/rv.o build/arm.o' \
    'build/rv.o: src/rv.c' \
    $'\triscv64-unknown-elf-gcc -march=rv32imac -mabi=ilp32 -Iinclude -DRV_TARGET=1 -c src/rv.c -o build/rv.o' \
    'build/arm.o: src/arm.c' \
    $'\taarch64-none-elf-gcc -mcpu=cortex-a76 -Iinclude -DARM_TARGET=1 -c src/arm.c -o build/arm.o' \
    > "$PROJECT/Makefile"

(
    cd "$PROJECT"
    PATH="$PROJECT/bin:$PATH" "$COMPILEDB" --full-path --overwrite --no-build make -B
)
MAKE_DB="$PROJECT/compile_commands.json"
for flag in -march=rv32imac -mabi=ilp32 -mcpu=cortex-a76 -Iinclude -DRV_TARGET=1 -DARM_TARGET=1; do
    contains "$flag" "$MAKE_DB"
done
contains "$PROJECT/bin/riscv64-unknown-elf-gcc" "$MAKE_DB"
contains "$PROJECT/bin/aarch64-none-elf-gcc" "$MAKE_DB"
echo "Make: ok"

cp "$COMPILEDB" "$PROJECT/bin/compiledb"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "rake args: %s\n" "$*"' \
    'printf "%s\n" "riscv64-unknown-elf-gcc -march=rv32imac -mabi=ilp32 -Iinclude -DRV_TARGET=1 -c src/rv.c -o build/rv.o"' \
    'printf "%s\n" "aarch64-none-elf-gcc -mcpu=cortex-a76 -Iinclude -DARM_TARGET=1 -c src/arm.c -o build/arm.o"' \
    'for arg in "$@"; do [ "$arg" = fail ] && exit 23; done' \
    'exit 0' \
    > "$PROJECT/bin/rake"
chmod 0755 "$PROJECT/bin/rake"

(
    cd "$PROJECT"
    PATH="$PROJECT/bin:$PATH" "$REPO_ROOT/scripts/compiledb-rake.sh" target > "$WORK/rake-success.log"
)
contains 'rake args: --build-all --verbose target' "$WORK/rake-success.log"
for flag in -march=rv32imac -mabi=ilp32 -mcpu=cortex-a76 -Iinclude -DRV_TARGET=1 -DARM_TARGET=1; do
    contains "$flag" "$PROJECT/compile_commands.json"
done

set +e
(
    cd "$PROJECT"
    PATH="$PROJECT/bin:$PATH" "$REPO_ROOT/scripts/compiledb-rake.sh" fail > "$WORK/rake-failure.log"
)
rake_status=$?
set -e
[ "$rake_status" -eq 23 ] || fail "Rake 失败状态未保留: $rake_status"
contains -DRV_TARGET=1 "$PROJECT/compile_commands.json"
echo "Rake: ok"
