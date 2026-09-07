-- This configuration is distributed as an air-gapped package. Missing runtime
-- components are caught by scripts/check-offline-prereqs.sh on the build host.
-- Do not turn the automatic installers back on for an offline target.
local offline_servers = {
  "bashls",
  "clangd",
  "lua_ls",
  "marksman",
  "pyright",
  "ruff",
  "verible",
}

return {
  {
    "saghen/blink.cmp",
    opts = {
      fuzzy = {
        implementation = "lua",
        prebuilt_binaries = { download = false },
      },
    },
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.registry_cache = vim.tbl_deep_extend("force", opts.registry_cache or {}, { refresh = false })
      opts.ui = vim.tbl_deep_extend("force", opts.ui or {}, { check_outdated_packages_on_open = false })
    end,
    config = function(_, opts)
      opts.ensure_installed = {}
      require("mason").setup(opts)
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      for _, server in ipairs(offline_servers) do
        opts.servers[server] = opts.servers[server] or {}
        opts.servers[server].mason = false
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
