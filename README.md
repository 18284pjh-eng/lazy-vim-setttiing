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
cd lazyvim-offline && ./installer/install.sh

# 方式 B: 无 7z（自解压）
chmod +x lazyvim-offline-<版本>.run
./lazyvim-offline-<版本>.run

# 常用选项
./installer/install.sh --keep-config   # 保留目标机已有 ~/.config/nvim，只装运行时
./installer/install.sh --keep-data     # 保留目标机已有 ~/.local/share/nvim
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
- **可复现**：`lazy-lock.json` 固定插件版本；payload 带版本与 sha256 清单（manifest.txt）。
  仅当构建工作区无未提交修改时，发布物才附带与包内配置一致的 git bundle 供离线溯源。
- **不在内网自动下载**：lazy.nvim 缺失时直接报错；插件、Mason、Treesitter 的自动安装和
  更新检查均关闭。构建机会在复制 payload 前检查所有锁定插件的提交，以及本配置要求的运行时。

## C/C++ 语义跳转与搜索

- 在 C/C++ 文件中，`gd` 跳转光标下的定义，`gr` 查找语义引用。`#include "header.h"` 也通过
  clangd 的 definition 请求跳转；不额外绑定 F12。
- clangd 自动识别项目根目录、`build/`、`cmake-build-*`、`out/build/` 内已有的
  `compile_commands.json`。CMake 项目在项目根执行：

  ```bash
  cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  ```

  生成后重开 C/C++ 文件或重启 Neovim，使 clangd 重新启动并读取数据库。该 `build/` 是可删除、不可提交的生成物。
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
  `fdfind`。先运行 `./scripts/check-offline-prereqs.sh` 可只检查缓存完整性。
- 若预检提示插件提交不匹配，在构建机执行 `:Lazy restore`；提示缺少组件时按所列名称显式
  补齐，再重新运行预检和打包。
- 内网目标机不要运行 `:Lazy sync`、`:MasonUpdate` 或 `:TSUpdate`；这些是构建机联网维护时
  才使用的命令。若包缺组件，请回到构建机补齐后重新打包。
- avante / leetcode 等 AI、刷题插件需网络/API 网关才可用；离线环境不影响其余功能。
- `markdown-preview.nvim` 的浏览器预览依赖 GUI 浏览器；纯终端下 `render-markdown.nvim` 可用。
- 换了新 mason 包或新插件后，务必重跑 `build-release.sh`，payload 会重新收集。
