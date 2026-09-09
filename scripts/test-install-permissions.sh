#!/usr/bin/env bash
# Regression: extraction drops executable bits, install restores known tools.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/lazyvim-install-permissions.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
pkg="$work/pkg"
test_home="$work/home"
prefix="$test_home/.local/opt/lazyvim-offline"
mkdir -p "$pkg/installer" "$pkg/config/nvim" "$pkg/payload/data/nvim" \
    "$pkg/payload/nvim/bin" "$pkg/payload/tools/bin" "$test_home"
cp "$REPO_ROOT/installer/install.sh" "$REPO_ROOT/installer/nvim-wrapper.sh" "$pkg/installer/"
# Stand-ins keep this test about install permissions, without a plugin runtime.
cp /bin/true "$pkg/payload/nvim/bin/nvim"
for tool in rg fd node compiledb compiledb-rake nvim-filelist; do
    cp /bin/true "$pkg/payload/tools/bin/$tool"
done
chmod 0644 "$pkg/payload/nvim/bin/nvim" "$pkg/payload/tools/bin/"*
if ! env -i HOME="$test_home" PATH=/usr/bin:/bin bash "$pkg/installer/install.sh" > "$work/install.log" 2>&1; then
    cat "$work/install.log" >&2
    exit 1
fi
for file in "$prefix/nvim/bin/nvim" "$prefix/tools/bin/"* "$test_home/.local/bin/nvim"; do
    [ -x "$file" ] || { printf 'Not executable: %s\n' "$file" >&2; exit 1; }
    "$file" --version >/dev/null
done
# No need to mutate the extracted source permissions to repair the install.
[ "$(stat -c '%a' "$pkg/payload/tools/bin/rg")" = 644 ]
printf 'install restores executable permissions and creates a working wrapper: OK\n'
# An executable may still be rejected by the OS; report evidence and stop.
cat > "$pkg/payload/tools/bin/rg" <<'EOF'
#!/bin/sh
echo 'Permission denied (test fixture)' >&2
exit 126
EOF
rc=0
env -i HOME="$test_home" PATH=/usr/bin:/bin bash "$pkg/installer/install.sh" > "$work/rejected.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ]
grep -q '退出码 126' "$work/rejected.log"
grep -q 'noexec' "$work/rejected.log"
if grep -q '^安装完成' "$work/rejected.log"; then
    echo 'Rejected binary incorrectly reported a successful install' >&2
    exit 1
fi
printf 'execution rejection reports permissions/mount diagnostics and fails: OK\n'
