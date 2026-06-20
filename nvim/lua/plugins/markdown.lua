local markdownlint_config = vim.fn.expand("~/.markdownlint.jsonc")

if vim.fn.filereadable(markdownlint_config) == 0 then
  markdownlint_config = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":h:h:h:h")
    .. "/.markdownlint.jsonc"
end

return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", markdownlint_config, "-" },
        },
      },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" }, -- if you use the mini.nvim suite
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      heading = {
        enabled = true,
        sign = true,
        style = nil,
        icons = { "① ", "② ", "③ ", "④ ", "⑤ ", "⑥ " },
        left_pad = 1,
      },
      bullet = {
        enabled = true,
        icons = { "●", "○", "◆", "◇" },
        right_pad = 1,
        highlight = "render-markdownBullet",
      },
      checkbox = {
        enabled = true,
        unchecked = {
          icon = "󰄱     ",
          highlight = "RenderMarkdownUnchecked",
        },
        checked = {
          icon = "󰱒     ",
          highlight = "RenderMarkdownChecked",
        },
        custom = {
          todo = { raw = "[-]", rendered = "󰥔     ", highlight = "RenderMarkdownTodo" },
        },
      },
    },
  },
}
