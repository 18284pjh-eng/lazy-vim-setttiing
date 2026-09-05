return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      -- Keep navigation and diagnostics, but show only compact signs/underlines.
      opts.diagnostics = opts.diagnostics or {}
      opts.diagnostics.virtual_text = false
      local signs = type(opts.diagnostics.signs) == "table" and opts.diagnostics.signs or {}
      local underline = type(opts.diagnostics.underline) == "table" and opts.diagnostics.underline or {}
      opts.diagnostics.signs = vim.tbl_deep_extend(
        "force",
        signs,
        { severity = { min = vim.diagnostic.severity.WARN } }
      )
      opts.diagnostics.underline = vim.tbl_deep_extend(
        "force",
        underline,
        { severity = { min = vim.diagnostic.severity.WARN } }
      )

      for _, server in ipairs({ "pyright", "ruff" }) do
        opts.servers[server] = opts.servers[server] or {}
        opts.servers[server].enabled = true
      end
    end,
  },
}
