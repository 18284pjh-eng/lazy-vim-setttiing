#!/usr/bin/env bash
# Generate a local, project-relative file list without changing build files.
set -euo pipefail

usage() {
    cat <<'EOF'
用法: nvim-filelist [--root DIR] [--ext c,h,cc,cpp,cxx,hh,hpp] -- DIR...

在项目根生成 tree_t.f；DIR 相对于项目根，也可以是绝对路径。
递归扫描指定目录，保留相对路径，排序去重；成功后整体替换旧清单。
Git 项目自动写入本地 info/exclude，不修改 .gitignore 或索引。
新增或删除文件后重新执行本命令。不会运行构建或上传清单。
EOF
}
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
project_root="$PWD"
extensions='c,h,cc,cpp,cxx,hh,hpp'
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root) [ "$#" -ge 2 ] || die '--root 缺少目录'; project_root="$2"; shift 2 ;;
        --ext) [ "$#" -ge 2 ] || die '--ext 缺少后缀列表'; extensions="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --) shift; break ;;
        -*) die "未知选项: $1" ;;
        *) break ;;
    esac
done
[ "$#" -gt 0 ] || die '至少指定一个扫描目录（用 -- 分隔选项与目录）'
for tool in find realpath sort mktemp; do
    command -v "$tool" >/dev/null || die "缺少系统工具: $tool"
done
[[ "$project_root" != *$'\n'* && "$project_root" != *$'\r'* ]] || die '项目根不能包含换行或回车'
project_root="$(cd -- "$project_root" && pwd -P)" || die '项目根不存在'
cd -- "$project_root"
[ ! -L tree_t.f ] || die 'tree_t.f 是符号链接，请选择普通文件作为清单'
[ ! -e tree_t.f ] || [ -f tree_t.f ] || die 'tree_t.f 不是普通文件'

exclude_file=''
exclude_rule=''
if command -v git >/dev/null && git rev-parse --show-toplevel >/dev/null 2>&1; then
    if git ls-files --error-unmatch -- tree_t.f >/dev/null 2>&1; then
        die 'tree_t.f 已被 Git 跟踪；本地排除无法取消跟踪，请先自行处理索引'
    fi
    git_root="$(git rev-parse --show-toplevel)"
    exclude_file="$(git rev-parse --path-format=absolute --git-path info/exclude)"
    relative_list="$(realpath -ms --relative-to="$git_root" -- "$project_root/tree_t.f")"
    # Escape Git ignore pattern metacharacters, including spaces at line end.
    exclude_rule="/${relative_list//\\/\\\\}"
    for char in '*' '?' '[' ']' ' '; do
        exclude_rule="${exclude_rule//"$char"/\\$char}"
    done
fi

[[ "$extensions" =~ ^[[:alnum:]_+]+(,[[:alnum:]_+]+)*$ ]] || die '--ext 使用逗号分隔后缀，不含点号或通配符'
IFS=, read -r -a suffixes <<< "$extensions"
expression=()
for suffix in "${suffixes[@]}"; do
    [ "${#expression[@]}" -eq 0 ] || expression+=(-o)
    expression+=(-name "*.$suffix")
done
directories=()
for directory in "$@"; do
    [[ "$directory" != *$'\n'* && "$directory" != *$'\r'* ]] || die '扫描目录不能包含换行或回车'
    directory="$(realpath -ms -- "$directory")"
    [ -d "$directory" ] || die "扫描目录不存在: $directory"
    directories+=("$directory")
done

# Same filesystem as the destination: rename never exposes a partial file.
work="$(mktemp -d "$project_root/.nvim-filelist.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
find -H "${directories[@]}" -name .git -prune -o \
    \( -type f -o -xtype f \) \( "${expression[@]}" \) -print0 > "$work/found" \
    || die '目录扫描失败，保留原清单'
while IFS= read -r -d '' file; do
    [[ "$file" != *$'\n'* && "$file" != *$'\r'* ]] || die '文件名包含换行或回车，保留原清单'
    realpath -ms --relative-to="$project_root" -- "$file"
done < "$work/found" > "$work/paths"
LC_ALL=C sort -u -- "$work/paths" > "$work/tree_t.f"
[ -s "$work/tree_t.f" ] || die '没有匹配文件，保留原清单'
if [ -n "$exclude_file" ]; then
    mkdir -p -- "$(dirname -- "$exclude_file")"
    if [ ! -f "$exclude_file" ] || ! grep -Fxq -- "$exclude_rule" "$exclude_file"; then
        printf '\n%s\n' "$exclude_rule" >> "$exclude_file"
    fi
    git check-ignore -q -- tree_t.f || die '本地 Git 排除未生效，保留原清单'
fi
mv -- "$work/tree_t.f" "$project_root/tree_t.f"
printf '已生成 %s/tree_t.f（%s 个文件）\n' "$project_root" "$(wc -l < tree_t.f)"
