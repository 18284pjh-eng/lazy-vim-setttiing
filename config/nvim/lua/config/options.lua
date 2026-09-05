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

-- Use the X11 clipboard through xclip.
vim.opt.clipboard = "unnamedplus"
vim.g.clipboard = "xclip"

-- 禁用比例字体，强制等宽
vim.cmd([[
  set nowrap  " 不换行，避免宽度错乱
  set listchars=tab:→\ ,trail:·,nbsp:␣  " 显示不可见字符，验证等宽
]])
