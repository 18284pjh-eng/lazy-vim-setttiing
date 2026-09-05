-- Verilog (.v) / SystemVerilog (.sv) support: verible LSP + treesitter parser.
-- Diagnostics (syntax errors + lint rules) come from verible-verilog-ls, which
-- pushes them live as you type.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      -- verible-ls supports both push and pull diagnostics; neovim would show
      -- every diagnostic twice (neovim#29927). Drop the capability so only the
      -- server's push diagnostics are used.
      opts.servers.verible = {}
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("verible_no_pull_diagnostics", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.name == "verible" then
            client.server_capabilities.diagnosticProvider = nil
          end
        end,
      })
    end,
  },

  -- Mason package "verible" provides verible-verilog-ls / -lint / -format.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "verible" })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- The main-branch parser list has no "verilog" grammar; the systemverilog
      -- grammar (a Verilog superset) covers plain .v files too.
      vim.treesitter.language.register("systemverilog", "verilog")
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "systemverilog" })
    end,
  },

  -- .v/.sv use 3-space indentation, never tabs.
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("verilog_indent", { clear = true }),
        pattern = { "verilog", "systemverilog" },
        callback = function(args)
          vim.bo[args.buf].expandtab = true
          vim.bo[args.buf].shiftwidth = 3
          vim.bo[args.buf].softtabstop = 3
          vim.bo[args.buf].tabstop = 3
        end,
      })
    end,
  },
}
