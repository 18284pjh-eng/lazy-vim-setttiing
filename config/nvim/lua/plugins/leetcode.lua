-- 1. 必须注释掉或删掉这一行，否则配置不生效！
-- if true then return {} end

return {
  -- 添加 leetcode.nvim 插件
  {
    "kawre/leetcode.nvim",
    build = ":TSUpdate html",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-treesitter/nvim-treesitter",
      "rcarriga/nvim-notify",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      -- 这里是你希望使用的编程语言
      lang = "python3",

      -- 如果你在中国区（leetcode.cn），请务必配置以下各项
      cn = {
        enabled = false,
        translator = true,
        translate_problems = true,
      },

      -- 也可以在这里设置自动保存等
      storage = {
        home = vim.fn.stdpath("data") .. "/leetcode", -- 题目保存路径
      },
    },
  },

  -- 下面可以保留你原来的其他插件配置，比如 gruvbox 等
  -- { "ellisonleao/gruvbox.nvim" },
  -- {
  --   "LazyVim/LazyVim",
  --   opts = {
  --     colorscheme = "gruvbox",
  --   },
  -- },
}
