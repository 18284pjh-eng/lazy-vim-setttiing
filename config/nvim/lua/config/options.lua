-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
-- vim.opt.guifont = "JetBrainsMono Nerd Font Mono:h14" -- GUI 模式生效
vim.opt.guifont = "Maple Mono NF CN" -- GUI 模式生效
vim.opt.ambiwidth = "single" -- 统一字符宽度（等宽核心）
vim.opt.tabstop = 4 -- Tab 占 4 个字符（等宽对齐）
vim.opt.shiftwidth = 4 -- 缩进占 4 个字符
vim.opt.expandtab = true -- Tab 转为空格，保证等宽对齐
vim.opt.termguicolors = true -- 确保字体颜色和符号正常显示
vim.g.autoformat = false -- 保存时不自动格式化，避免自动修改代码布局

-- Only use the system clipboard when the current graphical session can
-- actually serve it.  Forcing xclip makes every `yy` fail on a Wayland,
-- SSH, or minimal offline host where xclip is unavailable.
local has = vim.fn.executable
local wayland_clipboard = vim.env.WAYLAND_DISPLAY and has("wl-copy") == 1 and has("wl-paste") == 1
local x11_clipboard = vim.env.DISPLAY and (has("xclip") == 1 or has("xsel") == 1)
if wayland_clipboard or x11_clipboard then
  vim.opt.clipboard = "unnamedplus"
else
  -- Keep yy/p working through Neovim's normal registers without spawning an
  -- unavailable external clipboard provider.  The explicit + and * registers
  -- use an in-memory fallback so Nvim will not auto-detect and invoke xclip.
  vim.opt.clipboard = ""
  local memory_clipboard = {
    ["+"] = { {}, "v" },
    ["*"] = { {}, "v" },
  }
  local function copy(register)
    return function(lines, regtype)
      memory_clipboard[register] = { vim.deepcopy(lines), regtype }
    end
  end
  local function paste(register)
    return function()
      return vim.deepcopy(memory_clipboard[register])
    end
  end
  vim.g.clipboard = {
    name = "in-memory (no system clipboard)",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
  }
end

-- 禁用比例字体，强制等宽
vim.cmd([[
  set nowrap  " 不换行，避免宽度错乱
  set listchars=tab:→\ ,trail:·,nbsp:␣  " 显示不可见字符，验证等宽
]])
