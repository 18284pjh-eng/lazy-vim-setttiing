-- Render-markdown.nvim 本体由 lang.markdown 扩展提供（<leader>um = 渲染开/关切换）。
-- 这里只补充"彻底开/关"的键位，仅在 markdown 类文件里生效。
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    keys = {
      { "<leader>uM", "<cmd>RenderMarkdown enable<cr>", desc = "Markdown Render: Enable", ft = { "markdown", "norg", "rmd", "org", "codecompanion" } },
      { "<leader>uo", "<cmd>RenderMarkdown disable<cr>", desc = "Markdown Render: Disable", ft = { "markdown", "norg", "rmd", "org", "codecompanion" } },
    },
  },
}
