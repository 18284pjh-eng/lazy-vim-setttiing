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
# Published manifests must also restore nested plugin/Mason entrypoints, while
# leaving ordinary data files and --keep-data installations alone.
data="$pkg/payload/data/nvim"
mkdir -p "$data/mason/packages/test server" "$data/mason/bin"
printf '#!/bin/sh\nexec "$(dirname "$0")/helper"\n' > "$data/mason/packages/test server/server"
cp /bin/true "$data/mason/packages/test server/helper"
chmod 0755 "$data/mason/packages/test server/"*
touch "$data/README.md"
ln -s '../packages/test server/server' "$data/mason/bin/server"
printf '%s\0' 'data/nvim/mason/packages/test server/server' \
    'data/nvim/mason/packages/test server/helper' > "$pkg/payload/executables.list"
chmod 0644 "$data/mason/packages/test server/"*
env -i HOME="$test_home" PATH=/usr/bin:/bin bash "$pkg/installer/install.sh" > "$work/manifest.log" 2>&1 \
    || { cat "$work/manifest.log" >&2; exit 1; }
installed_data="$test_home/.local/share/nvim"
[ -x "$installed_data/mason/bin/server" ] || { echo 'Mason entrypoint lost execute permission' >&2; exit 1; }
"$installed_data/mason/packages/test server/server"
[ ! -x "$installed_data/README.md" ]
[ ! -x "$data/mason/packages/test server/server" ]
chmod 0644 "$installed_data/mason/packages/test server/server"
env -i HOME="$test_home" PATH=/usr/bin:/bin bash "$pkg/installer/install.sh" --keep-data > "$work/keep.log" 2>&1
[ ! -x "$installed_data/mason/bin/server" ]
printf 'manifest restores nested executables, preserves data files and respects --keep-data: OK\n'
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
