# lazyvim-offline — LazyVim 离线迁移与部署

把构建机（Debian 12+ x86_64）的完整 LazyVim 环境——nvim 本体、全部插件、Mason
LSP/formatter、Treesitter parser、node/rg/fd 工具链——打成一个 7z 离线包，部署到**无
sudo 权限**的纯净内网 Debian 12+ 机器上。安装与日常使用不需要联网、也不需要 root。

## 仓库结构

```
├── config/nvim/              # nvim 用户配置（git 管理，唯一事实来源）
├── installer/
│   ├── install.sh            # 目标机安装器（无 sudo、幂等、自动备份旧数据）
│   ├── uninstall.sh          # 卸载器（可恢复备份）
│   └── nvim-wrapper.sh       # 启动包装器模板（PATH 隔离）
├── scripts/
│   ├── sync-config.sh        # 本机 ~/.config/nvim -> 仓库 config/（并提交 git）
│   ├── build-payload.sh      # 从本机收集二进制/数据 -> payload/（幂等）
│   ├── build-release.sh      # 打包: 7z 主发布物 + .run 自解压回退 + git bundle
│   ├── verify-release.sh     # 对 7z 做干净 HOME 冒烟测试
│   └── selfextract-stub.sh   # .run 自解压头部
├── payload/                  # 构建产物（git 忽略），由 build-payload.sh 生成
└── dist/                     # 发布物（git 忽略）：*.7z / *.run / SHA256SUMS / *.repo.bundle
```

## 日常维护流程（配置有更新时）

```bash
# 1. 仅在可联网的构建机正常使用/修改 nvim 配置，并显式安装新增依赖
nvim   # ...

# 2. 同步配置进仓库并提交（git 管理每次变更）
./scripts/sync-config.sh

# 3. 打新发布包（先检查插件、Mason、Treesitter 是否完整，再收集 payload）
./scripts/build-release.sh            # 或指定版本号: ./scripts/build-release.sh v1.1.0

# 4. 分别验证 7z 与 .run 包（干净环境 headless 启动测试）
./scripts/verify-release.sh dist/lazyvim-offline-*.7z
./scripts/verify-release.sh dist/lazyvim-offline-*.run

# 5. 打 git tag 并传输
git add -A && git commit -m "release: <版本>"
git tag <版本>
# 将 .7z、.run 与 <版本>.SHA256SUMS 一起拷入内网
```

## 内网机器安装（无 sudo）

```bash
# 方式 A: 有 7z
7z x lazyvim-offline-<版本>.7z -olazyvim-offline
cd lazyvim-offline && bash ./installer/install.sh

# 方式 B: 无 7z（自解压）
chmod +x lazyvim-offline-<版本>.run
./lazyvim-offline-<版本>.run

# 常用选项
bash ./installer/install.sh --keep-config   # 保留目标机已有 ~/.config/nvim，只装运行时
bash ./installer/install.sh --keep-data     # 保留目标机已有 ~/.local/share/nvim
```

安装后用 `~/.local/bin/nvim` 启动（包装器已把离线包工具链与 `~/.local/bin`
置于 PATH 最前，天然屏蔽系统旧 nvim 与脏依赖）。

## 鲁棒性设计

- **不碰 root/系统目录**：一切装入 `~/.local/opt/lazyvim-offline`、`~/.config`、`~/.local/share`。
- **启动路径隔离**：`~/.local/bin/nvim` 是包装脚本，运行时把包内 `tools/bin`（rg/fd/node）
  与 `~/.local/bin` 前置到 PATH——mason 里 pyright 等依赖 node 的工具自动用包内 node，
  与目标机上旧的系统依赖完全隔离。
- **旧数据安全**：安装器通过标记文件（`.lazyvim-offline-managed`）识别自家产物：
  - 目标机已有**外来**的 nvim/配置/数据 → 自动带时间戳备份（`*.backup-<ts>`）后再安装；
  - 已是自家管理的目录 → `rsync --delete` 增量刷新，自动清掉脏的/过期的 mason 包与旧 parser。
- **幂等**：重复运行 install.sh 即升级/修复；`uninstall.sh [--restore-backups]` 可回滚。
- **解压权限恢复**：v6.2.2 起记录包内原始可执行文件清单，安装时在目标目录恢复执行位，
  覆盖 nvim、工具、Mason 和插件；普通数据文件不加执行位。用 `bash` 启动安装器，避免它自身
  因解压丢失执行位而无法启动。`--keep-data` 保留的数据目录不做权限修改。
- **可复现**：`lazy-lock.json` 固定插件版本；payload 带版本与 sha256 清单（manifest.txt）。
  仅当构建工作区无未提交修改时，发布物才附带与包内配置一致的 git bundle 供离线溯源。
- **不在内网自动下载**：lazy.nvim 缺失时直接报错；插件、Mason、Treesitter 的自动安装和
  更新检查均关闭。构建机会在复制 payload 前检查所有锁定插件的提交，以及本配置要求的运行时。

## C/C++ 文件清单导航

在项目根生成本机专用的 `tree_t.f`，指定要导航的源码和 SDK 目录：

```bash
~/.local/opt/lazyvim-offline/tools/bin/nvim-filelist \
  --root "$PWD" -- src include ../sdk/include
```

目录相对于 `--root`，也可以使用绝对路径；必须显式指定扫描目录。默认后缀为
`c,h,cc,cpp,cxx,hh,hpp`，可用 `--ext c,h` 调整。自定义安装前缀时替换上述路径；
在 Neovim 内可执行 `:!nvim-filelist --root /path/to/project -- src include`。

- `gd`：字面量 include 优先在清单内找头文件；重名时显示候选路径和预览。函数、结构体等
  符号先查询 LSP，失败或等待 2 秒后显示清单内的同名文本候选。
- `gr`：先查询 LSP 语义引用；无结果时显示“文本匹配（非语义引用）”。
- `<Space>uJ`：切换 **Filelist 直接文本匹配**，在 LazyVim 的 `<Space>u` 菜单显示开关状态。
  默认关闭；开启后 C/C++ 的 `gd/gr` 直接搜索清单内文本，不发起 LSP 定义/引用请求，也不等待超时。
  include 仍优先按清单定位头文件；清单缺失或为空时提示，不转回 LSP。再次按下恢复 LSP 优先。
- `:FilelistGrep` / `:FilelistGrep shared`：直接在清单内按完整词搜索光标下标识符或指定词。
- `:FilelistUse /path/to/tree_t.f`：当前标签页选用清单，适用于单独打开共享 SDK；路径按原文输入，
  空格不加引号，`$`、`%` 不展开。无参数执行 `:FilelistUse` 恢复自动选择。
- `Ctrl-o`：返回跳转前的位置。开关关闭且没有清单时沿用原有 LSP 导航；Python/Verilog 行为不变。

开关在当前 Neovim 会话全局生效，重启默认关闭；若希望默认开启，在
`lua/config/options.lua` 加入 `vim.g.filelist_text_only = true`。切换会取消本模块正在等待的 LSP
导航请求，防止旧结果突然跳转；补全、诊断等其他 LSP 功能继续工作。

生成器只在 Git 的本地 `info/exclude` 添加排除规则，不改 `.gitignore`，不提交清单；
已被 Git 跟踪的 `tree_t.f` 会报错。支持外部 SDK、空格路径、worktree；扫描失败保留旧清单。
新增、删除文件或 SDK 路径变化后，重新执行生成命令；已有文件只改内容不需重建清单。
每次导航重新读取清单，跳过失效条目，空清单不会扩大为全项目搜索。

清单不包含编译参数，不能取代 `compile_commands.json`，也不能确定真实的 include 搜索顺序。
LSP 结果可位于清单之外；文本候选可能是注释、调用或声明，读取磁盘内容，不保证反映未保存修改。
完整规则见 [文件清单导航说明](docs/filelist-navigation.md)。

## C/C++ 语义跳转与搜索

- 没有文件清单时，`gd` 跳转光标下的定义，`gr` 查找语义引用，include 由 clangd 定位。
  有清单时采用上面的优先级；不额外绑定 F12。
- clangd 自动识别项目根目录、`build/`、`cmake-build-*`、`out/build/` 内已有的
  `compile_commands.json`。CMake 项目在项目根执行：

  ```bash
  cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  ```

  生成后重开 C/C++ 文件或重启 Neovim，使 clangd 重新启动并读取数据库。该 `build/` 是可删除、不可提交的生成物。
- Makefile 项目在项目根执行（`[参数]` 例如 `-j8`、目标名或变量赋值）：

  ```bash
  compiledb --full-path --overwrite --no-build make [参数]
  ```

  该命令只让 Make 发现编译命令，不实际编译；会把 `-march`、`-mabi`、`-mcpu`、`-I` 和 `-D`
  原样写入根目录的 `compile_commands.json`。
- Rakefile 项目可执行：

  ```bash
  compiledb-rake [任务]
  ```

  它会以 `rake --build-all --verbose` 执行真实构建，解析输出中可见的 GCC/Clang 命令，并在构建失败时
  仍返回原始 Rake 退出码。首版只支持可见编译命令；hdlmgr/SDK 若隐藏或包装命令，等提供实际日志后再加入适配。
- 搜索一段文本时，先用视觉模式选中它，再按 `<Space>sw`；`yy` 只写入寄存器，不会自动成为搜索词。

## 复制与粘贴

- 即使没有图形剪贴板，`yy`、`p` 和其他 Neovim 寄存器操作也可正常工作；`"+`/`"*`
  寄存器也会使用当前 Neovim 会话内的后备存储，不会调用缺失的外部程序。后备存储无法和其他应用或
  下次启动的 Neovim 共享内容。
- 在图形桌面中，配置会自动启用系统剪贴板：Wayland 需要 `wl-copy` 和 `wl-paste`
  （通常由 `wl-clipboard` 提供）；X11 需要 `xclip` 或 `xsel`。这些是目标机图形会话的系统
  依赖，不随 x86_64 离线包捆绑；请由内网软件源或管理员安装。

## 注意事项

- 离线包仅支持 x86_64 + glibc ≥ 2.34（Debian 12/13 满足）；安装器会在不满足时停止。
- 构建机需要 `bash`、`git`、`7z`、`tar`、`gzip`、`node`、`rg`，以及 `fd` 或 Debian 的
  `fdfind`。生成清单还使用 Debian 自带的 GNU find/coreutils（`find`、`realpath`、`sort`、`mktemp`）。
  先运行 `./scripts/check-offline-prereqs.sh` 可只检查缓存完整性。
- 若预检提示插件提交不匹配，在构建机执行 `:Lazy restore`；提示缺少组件时按所列名称显式
  补齐，再重新运行预检和打包。
- 内网目标机不要运行 `:Lazy sync`、`:MasonUpdate` 或 `:TSUpdate`；这些是构建机联网维护时
  才使用的命令。若包缺组件，请回到构建机补齐后重新打包。
- avante / leetcode 等 AI、刷题插件需网络/API 网关才可用；离线环境不影响其余功能。
- `markdown-preview.nvim` 的浏览器预览依赖 GUI 浏览器；纯终端下 `render-markdown.nvim` 可用。
- 换了新 mason 包或新插件后，务必重跑 `build-release.sh`，payload 会重新收集。
