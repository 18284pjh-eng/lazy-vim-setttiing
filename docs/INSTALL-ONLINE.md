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
./installer/install.sh

# 方式 B: 无 7z（自解压包，只需 tar + gzip）
chmod +x lazyvim-offline-<版本>.run
./lazyvim-offline-<版本>.run
```

安装脚本会：

1. 把 nvim 本体、runtime、rg/fd/node 工具装到 `~/.local/opt/lazyvim-offline/`
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
./installer/install.sh --keep-config   # 不动已有 ~/.config/nvim
./installer/install.sh --keep-data     # 不动已有 ~/.local/share/nvim
./installer/install.sh --prefix DIR    # 自定义安装前缀
```

重复运行 install.sh 即为升级/修复（受管理的目录会增量同步并清理脏文件）。

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

- 启动报错先看 `~/.local/bin/nvim` 是否存在且指向本包；
- `:checkhealth` 查看运行环境；
- 若冒烟测试失败，日志在 `/tmp/lazyvim-offline-smoke.log`。
- 不要在内网运行 `:Lazy sync`、`:MasonUpdate` 或 `:TSUpdate`。离线包不会自动下载缺失组件；
  请在构建机补齐后重新打包。
