return {
  "sphamba/smear-cursor.nvim",
  opts = {
    -- Disable smear in terminal and dap buffers to avoid E565 conflict
    -- when dap-ui opens its console (termopen inside nvim_buf_call)
    filetypes_disabled = { "dap-repl", "dapui_console", "terminal" },
  },
}
