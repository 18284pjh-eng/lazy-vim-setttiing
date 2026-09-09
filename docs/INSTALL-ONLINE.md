# 安装指南（内网机器 · 无 sudo）

## 前提

- Linux x86_64，glibc ≥ 2.34（Debian 12/13 均可）
- 普通用户账号即可，无需 root/sudo
- 可选工具：`7z`（无它就用自解压 `.run` 包）

## 安装步骤

```bash
# 方式 A: 有 7z
7z x lazyvim-offline-<版本>.7z -olazyvim-offline
cd lazyvim-offline
bash ./installer/install.sh

# 方式 B: 无 7z（自解压包，只需 tar + gzip）
chmod +x lazyvim-offline-<版本>.run
./lazyvim-offline-<版本>.run
```

安装脚本会：

1. 把 nvim 本体、runtime、rg/fd/node/compiledb/nvim-filelist 工具装到 `~/.local/opt/lazyvim-offline/`
2. 把全部插件、mason LSP、treesitter parser 装到 `~/.local/share/nvim/`
3. 把配置装到 `~/.config/nvim/`
4. 写启动包装器 `~/.local/bin/nvim`（PATH 隔离，屏蔽系统旧版本与脏依赖）
5. 自动备份目标机上已存在的旧配置/旧数据（`*.backup-<时间戳>`）
6. headless 冒烟测试

## 启动

```bash
~/.local/bin/nvim        # 或确保 ~/.local/bin 在 PATH 后直接 nvim
```

若 `~/.local/bin` 不在 PATH，安装器会向 `~/.bashrc`/`~/.profile` 追加一行（重新登录生效）。

## 选项

```bash
bash ./installer/install.sh --keep-config   # 不动已有 ~/.config/nvim
bash ./installer/install.sh --keep-data     # 不动已有 ~/.local/share/nvim
bash ./installer/install.sh --prefix DIR    # 自定义安装前缀
```

重复运行 install.sh 即为升级/修复（受管理的目录会增量同步并清理脏文件）。

## C/C++ 本地文件清单

在项目根执行（目录名替换为实际源码与 SDK 路径）：

```bash
~/.local/opt/lazyvim-offline/tools/bin/nvim-filelist --root "$PWD" -- src include ../sdk/include
```

使用 `--prefix DIR` 安装时，命令为 `DIR/tools/bin/nvim-filelist`。Neovim 内可运行
`:!nvim-filelist --root /path/to/project -- src include`。需要系统自带 GNU find/coreutils；
默认扫描 C/C++ 后缀，可用 `--ext c,h,cpp,hpp` 调整。普通终端使用完整命令路径即可。

清单 `tree_t.f` 只在本机生成，通过 Git 本地排除规则保持未跟踪（支持 worktree），不改项目
`.gitignore`；如果已经被跟踪，生成器停止，需自行处理。新增/删除文件后重新生成；每次导航
自动重读清单，不需重启。扫描失败保留原清单。

`gd` 定位 include 或优先使用 LSP 跳转定义，`gr` 优先查语义引用。进入清单搜索后，`gd`
优先显示符号定义候选，找不到时提示并回退全部文本；`gr` 排除识别出的定义位置，保留其余文本。
支持函数、结构体及成员、数组、变量、宏、类型别名和枚举；无初始化的 `extern`、函数原型和
结构体前置声明不当作定义，赋值和访问仍是引用候选。筛选复用包内 C/C++ Tree-sitter，不启动 LSP、不需要编译数据库。
声明、注释等仍可能出现在 `gr`，不等于真实语义引用。`:FilelistGrep` 始终搜索全部同名文本，`Ctrl-o` 返回。
按 `<Space>uJ` 切换“Filelist 直接文本匹配”（在 `<Space>u` 菜单显示状态）：开启后 C/C++ 的
`gd/gr` 不请求 LSP，直接使用清单，include 仍按清单定位；清单缺失/为空时提示。再次按下恢复
LSP 优先。开关作用于当前会话，默认关闭；在 `lua/config/options.lua` 设置
`vim.g.filelist_text_only = true` 可默认开启。其他 LSP 功能继续工作。
`:FilelistUse /path/to/tree_t.f` 在当前标签页选用清单；路径按原文输入，空格不加引号，
无参数恢复自动选择。清单不替代编译数据库，文本匹配不等于语义定义或完整引用，且读取磁盘内容。
开关关闭且没有清单时保留原有导航。更多规则见包内 `docs/filelist-navigation.md`。

## 卸载 / 回滚

```bash
./installer/uninstall.sh                    # 仅卸载本安装器管理的部分
./installer/uninstall.sh --restore-backups  # 卸载并恢复最近的备份
```

## 校验（可选）

```bash
sha256sum -c lazyvim-offline-<版本>.SHA256SUMS
```

## 故障排查

- 第 1/2 步报 `Permission denied` 时，安装尚未完成，`~/.local/bin/nvim` 可能还没有生成。
  先在解压目录检查源文件与安装目标的权限：

  ```bash
  stat -c '%A %a %U:%G %n' ./payload/tools/bin/rg "$HOME/.local/opt/lazyvim-offline/tools/bin/rg"
  findmnt -T "$HOME/.local/opt/lazyvim-offline/tools/bin/rg" -no TARGET,OPTIONS
  namei -l "$HOME/.local/opt/lazyvim-offline/tools/bin/rg"
  ```

  若文件缺少执行位（例如 `644`），旧包可以在解压目录执行以下命令后重装；需修复源文件，
  因为重装会用 `cp -a` 重新覆盖目标权限：

  ```bash
  chmod u+x ./payload/nvim/bin/nvim ./payload/tools/bin/{rg,fd,node,compiledb,compiledb-rake,nvim-filelist}
  bash ./installer/install.sh
  hash -r
  "$HOME/.local/bin/nvim" --version
  ```

  v6.2.2 起，发布包包含 `payload/executables.list`（NUL 分隔的原始可执行文件路径），
  安装器在目标目录恢复执行位，覆盖 nvim、工具、Mason 与插件中的可执行文件，
  不给普通数据文件添加执行位；`--keep-data` 保留的数据不修改。通过 `bash` 启动安装器，
  即使安装器本身丢失执行位也可运行。旧包不含此清单，建议换用 v6.2.2 或更新包。

  已核验 v6.2.1 原始 `.7z` 中 `rg` 的权限是 `755`，本机 7-Zip 25.01 和 p7zip 16.02
  解压均保留执行位。若解压后是 `644`，说明归档的 Unix 权限未被保留；仅凭 `7z x`
  命令无法确定是哪一环节，可用 `7z i` 查看实现/版本、`findmnt -T .` 检查解压位置，
  并对照 SHA256SUMS 确认传输的包未变化。新版安装器无需依赖解压器保留执行位。

  若文件已有 `x` 权限但仍被拒绝，
  检查父目录权限、挂载选项中的 `noexec` 以及内网执行管控；`chmod` 不能解除这些限制，
  应由管理员确认获准执行的安装位置。也可在目标 Linux 机器直接使用原始 `.run` 包安装，
  由 tar 解压，避免先经其他系统解压后再拷贝散文件。
- 启动报错先看 `~/.local/bin/nvim` 是否存在且指向本包；
- `:checkhealth` 查看运行环境；
- 若冒烟测试失败，安装器会显示独立日志路径（通常为 `/tmp/lazyvim-offline-smoke.*.log`）。
- Makefile 项目可使用 `compiledb --full-path --overwrite --no-build make [参数]` 生成
  `compile_commands.json`；Rakefile 项目使用 `compiledb-rake [任务]`。两者都要从项目根运行。
- 不要在内网运行 `:Lazy sync`、`:MasonUpdate` 或 `:TSUpdate`。离线包不会自动下载缺失组件；
  请在构建机补齐后重新打包。
