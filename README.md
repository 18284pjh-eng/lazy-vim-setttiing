# lazyvim-offline — LazyVim 离线迁移与部署

把本机（Debian 13 x86_64）的完整 LazyVim 环境——nvim 本体、全部插件、mason LSP/formatter、
treesitter parser、node/rg/fd 工具链——打成一个 7z 离线包，部署到**无 sudo 权限**的纯净
内网 Debian 13 机器上，全程无需联网、无需 root。

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
# 1. 在本机正常使用/修改 nvim 配置（:Lazy、mason 装新包等）
nvim   # ...

# 2. 同步配置进仓库并提交（git 管理每次变更）
./scripts/sync-config.sh

# 3. 打新发布包（自动重新收集 payload，含新增 mason 包/插件）
./scripts/build-release.sh            # 或指定版本号: ./scripts/build-release.sh v1.1.0

# 4. 验证发布包（干净环境 headless 启动测试）
./scripts/verify-release.sh dist/lazyvim-offline-*.7z

# 5. 打 git tag 并传输
git add -A && git commit -m "release: <版本>"
git tag <版本>
# 将 dist/lazyvim-offline-<版本>.7z（及 SHA256SUMS）拷入内网
```

## 内网机器安装（无 sudo）

```bash
# 方式 A: 有 7z
7z x lazyvim-offline-<版本>.7z -o lazyvim-offline
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
- **可复现**：`lazy-lock.json` 固定插件版本；payload 带版本与 sha256 清单（manifest.txt）；
  发布物附 git bundle 供离线溯源。

## 注意事项

- 离线包仅支持 x86_64 + glibc ≥ 2.31（Debian 13 满足）。
- avante / leetcode 等 AI、刷题插件需网络/API 网关才可用；离线环境不影响其余功能。
- `markdown-preview.nvim` 的浏览器预览依赖 GUI 浏览器；纯终端下 `render-markdown.nvim` 可用。
- 换了新 mason 包或新插件后，务必重跑 `build-release.sh`，payload 会重新收集。
