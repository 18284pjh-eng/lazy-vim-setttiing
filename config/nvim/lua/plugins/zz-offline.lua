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

local function clangd_command(base_cmd, dispatchers, config)
  local cmd = vim.deepcopy(base_cmd)
  local root = config.root_dir
  if root then
    local dirs = {
      root,
      vim.fs.joinpath(root, "build"),
      vim.fs.joinpath(root, "cmake-build-debug"),
      vim.fs.joinpath(root, "cmake-build-release"),
      vim.fs.joinpath(root, "out", "build"),
    }
    for _, path in ipairs(vim.fn.glob(vim.fs.joinpath(root, "cmake-build-*", "compile_commands.json"), false, true)) do
      dirs[#dirs + 1] = vim.fs.dirname(path)
    end
    for _, dir in ipairs(dirs) do
      if vim.uv.fs_stat(vim.fs.joinpath(dir, "compile_commands.json")) then
        cmd[#cmd + 1] = "--compile-commands-dir=" .. dir
        break
      end
    end
  end
  return vim.lsp.rpc.start(cmd, dispatchers, { cwd = root })
end

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
      local clangd = opts.servers.clangd or {}
      local base_cmd = type(clangd.cmd) == "table" and vim.deepcopy(clangd.cmd) or { "clangd" }
      clangd.cmd = function(dispatchers, config)
        return clangd_command(base_cmd, dispatchers, config)
      end
      clangd.root_markers = clangd.root_markers or {}
      if not vim.tbl_contains(clangd.root_markers, "CMakeLists.txt") then
        clangd.root_markers[#clangd.root_markers + 1] = "CMakeLists.txt"
      end
      opts.servers.clangd = clangd
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
