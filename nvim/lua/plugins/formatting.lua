return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },

        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },

        json = { "prettier" },
        jsonc = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },

        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },

        python = { "ruff_format" },
        go = { "gofumpt", "gofmt" },
        java = { "google-java-format" },
        kotlin = { "ktlint" },
        sql = { "sqlfluff" },
        toml = { "taplo" },
      },
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      run_on_start = true,
      auto_update = false,
      start_delay = 0,
      ensure_installed = {
        "prettier",
        "stylua",
        "shfmt",
        "ruff",
        "gofumpt",
        "google-java-format",
        "ktlint",
        "sqlfluff",
        "taplo",
        "markdownlint-cli2",
      },
    },
  },
}
