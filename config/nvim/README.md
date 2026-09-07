# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Avante + OpenAI

Avante 已配置为使用 OpenAI provider，配置文件位于
`lua/plugins/avante.lua`。它会复用 Codex 的配置：

- API key：`~/.codex/auth.json` 中的 `OPENAI_API_KEY`
- API 地址和模型：`~/.codex/config.toml` 中的 `base_url` 和 `model`
- API 协议：`~/.codex/config.toml` 中的 `wire_api`（当前为 Responses API）
- 工具调用：发送完整工具调用历史，不依赖网关保存 `previous_response_id`

真实的 API key 不会复制到 Bash 配置或本仓库中。

### 配置 API key

`~/.bashrc` 已配置为从 `~/.codex/auth.json` 自动读取 `OPENAI_API_KEY`，并
从 `~/.codex/config.toml` 自动读取 `OPENAI_BASE_URL`、`OPENAI_MODEL` 和
`OPENAI_WIRE_API`。
打开一个新终端，或执行：

```bash
source ~/.bashrc
```

如果需要确认变量已经生效，可以执行：

```bash
printf '%s\n' "${OPENAI_API_KEY:+OPENAI_API_KEY is set}"
printf 'OPENAI_BASE_URL=%s\n' "$OPENAI_BASE_URL"
printf 'OPENAI_MODEL=%s\n' "$OPENAI_MODEL"
```

其中第一条命令只显示 key 是否存在，不会打印真实 key。

### 构建机应用配置

以下命令仅可在**可联网的构建机**上使用，用来补齐或更新插件。离线内网机器不要运行
`:Lazy sync`、`:MasonUpdate` 或 `:TSUpdate`；离线包已关闭自动下载，缺少组件时应回到构建机
补齐并重新打包。

重启 Neovim 后执行：

```vim
:Lazy sync
```

然后再次重启 Neovim。使用以下任一命令打开 Avante 时，它会调用 OpenAI：

```vim
:AvanteAsk
:AvanteChat
:AvanteToggle
```

如果之前的会话已经留下失败的工具调用记录，先执行 `:AvanteChatNew`
新建会话，再重新测试。

模型默认跟随 `~/.codex/config.toml` 中的 `model`，可以使用以下命令查看
或切换 Avante 当前模型：

```vim
:AvanteModels
```

如果 API key 缺失或无效，请确认 `jq` 已安装，并检查启动 Neovim 的同一个
终端中的环境变量：

```bash
command -v jq
printf '%s\n' "${OPENAI_API_KEY:+OPENAI_API_KEY is set}"
```
