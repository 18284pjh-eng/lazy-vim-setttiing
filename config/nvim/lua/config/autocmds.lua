-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 关闭拼写检查：删除 LazyVim 对文本类文件开启 spell 的 autocmd，
-- 重新只保留自动换行（wrap），不再开 spell。
vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("wrap_no_spell", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = false
  end,
})

-- 保存前删除行尾多余空格（保持光标位置不变）
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("strip_trailing_whitespace", { clear = true }),
  callback = function(args)
    local save = vim.fn.winsaveview()
    vim.cmd([[keepjumps keeppatterns silent! %s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})

