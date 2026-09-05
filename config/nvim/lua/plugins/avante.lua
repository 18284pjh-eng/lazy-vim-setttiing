return {
  {
    "yetone/avante.nvim",
    opts = {
      provider = "openai",
      providers = {
        openai = {
          endpoint = vim.env.OPENAI_BASE_URL,
          model = vim.env.OPENAI_MODEL,
          use_response_api = vim.env.OPENAI_WIRE_API == "responses",
          -- This gateway does not reliably retain function calls by response ID.
          support_previous_response_id = false,
        },
      },
    },
  },
}
