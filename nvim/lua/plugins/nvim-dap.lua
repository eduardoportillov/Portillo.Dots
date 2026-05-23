local function get_args(config)
  local args = type(config.args) == "function" and (config.args() or {}) or config.args or {}
  local args_str = type(args) == "table" and table.concat(args, " ") or args
  config = vim.deepcopy(config)
  config.args = function()
    local new_args = vim.fn.expand(vim.fn.input("Run with args: ", args_str))
    if config.type and config.type == "java" then
      return new_args
    end
    return require("dap.utils").splitstr(new_args)
  end
  return config
end

local function close_dap_floats()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

return {
  {
    "mfussenegger/nvim-dap",
    recommended = true,
    desc = "Debugging support. Requires language specific adapters to be configured. (see lang extras)",

    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {},
      },
    },

    keys = {
      { "<leader>d", "", desc = "+debug", mode = { "n", "v" } },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "Breakpoint Condition" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Run/Continue" },
      { "<leader>da", function() require("dap").continue({ before = get_args }) end, desc = "Run with Args" },
      { "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to Cursor" },
      { "<leader>dg", function() require("dap").goto_() end, desc = "Go to Line (No Execute)" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
      { "<leader>dj", function() require("dap").down() end, desc = "Down" },
      { "<leader>dk", function() require("dap").up() end, desc = "Up" },
      { "<leader>dl", function() require("dap").run_last() end, desc = "Run Last" },
      { "<leader>do", function() require("dap").step_out() end, desc = "Step Out" },
      { "<leader>dO", function() require("dap").step_over() end, desc = "Step Over" },
      { "<leader>dp", function() require("dap").pause() end, desc = "Pause" },
      { "<leader>dr", function() require("dap").restart() end, desc = "Restart" },
      { "<leader>ds", function() require("dap").session() end, desc = "Session" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
      { "<leader>dw", function() require("dap.ui.widgets").hover() end, desc = "Widgets" },
    },

    config = function()
      local dap = require("dap")

      local function get_python_path()
        local venv_paths = {
          vim.fn.getcwd() .. "/.venv/bin/python",
          vim.fn.getcwd() .. "/venv/bin/python",
          vim.fn.getcwd() .. "/env/bin/python",
        }
        for _, path in ipairs(venv_paths) do
          if vim.fn.filereadable(path) == 1 then
            return path
          end
        end
        return "python3"
      end

      local ok, dap_python = pcall(require, "dap-python")
      if ok then
        dap_python.setup(get_python_path())
        vim.keymap.set("n", "<leader>dPt", function() dap_python.test_method() end, { desc = "Debug Python Test Method" })
        vim.keymap.set("n", "<leader>dPc", function() dap_python.test_class() end, { desc = "Debug Python Test Class" })
      end

      if LazyVim.has("mason-nvim-dap.nvim") then
        require("mason-nvim-dap").setup(LazyVim.opts("mason-nvim-dap.nvim"))
      end

      vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

      if LazyVim and LazyVim.config and LazyVim.config.icons and LazyVim.config.icons.dap then
        for name, sign in pairs(LazyVim.config.icons.dap) do
          sign = type(sign) == "table" and sign or { sign }
          vim.fn.sign_define(
            "Dap" .. name,
            { text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
          )
        end
      end

      local vscode = require("dap.ext.vscode")
      local ok_json, json = pcall(require, "plenary.json")
      if ok_json then
        vscode.json_decode = function(str)
          return vim.json.decode(json.json_strip_comments(str))
        end
      end

      local function load_env_variables()
        local variables = {}
        for k, v in pairs(vim.fn.environ()) do
          variables[k] = v
        end
        local env_file_path = vim.fn.getcwd() .. "/.env"
        local env_file = io.open(env_file_path, "r")
        if env_file then
          for line in env_file:lines() do
            for key, value in string.gmatch(line, "([%w_]+)=([%w_]+)") do
              variables[key] = value
            end
          end
          env_file:close()
        end
        return variables
      end

      for _, config in pairs(dap.configurations.go or {}) do
        config.env = load_env_variables
      end

      local breakpoints = require("dap.breakpoints")

      local function get_breakpoints_path()
        return vim.fn.getcwd() .. "/.nvim/dap-breakpoints.json"
      end

      local function save_breakpoints()
        local bps = breakpoints.get()
        if not bps then
          bps = {}
        end

        local out = {}
        for bufnr, buf_bps in pairs(bps) do
          local fname = vim.api.nvim_buf_get_name(bufnr)
          if fname and fname ~= "" then
            out[fname] = {}
            for _, bp in ipairs(buf_bps) do
              table.insert(out[fname], {
                line = bp.line,
                condition = bp.condition,
                hitCondition = bp.hitCondition,
                logMessage = bp.logMessage,
              })
            end
          end
        end

        local path = get_breakpoints_path()
        local dir = vim.fn.fnamemodify(path, ":h")
        if vim.fn.isdirectory(dir) == 0 then
          vim.fn.mkdir(dir, "p")
        end

        local f = io.open(path, "w")
        if f then
          f:write(vim.json.encode(out))
          f:close()
        end
      end

      local function restore_breakpoints_for_buf(bufnr)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        if not fname or fname == "" then
          return
        end

        local f = io.open(get_breakpoints_path(), "r")
        if not f then
          return
        end
        local content = f:read("*a")
        f:close()
        if not content or content == "" then
          return
        end

        local ok, decoded = pcall(vim.json.decode, content)
        if not ok or not decoded or not decoded[fname] then
          return
        end

        for _, bp in ipairs(decoded[fname]) do
          if bp and bp.line then
            breakpoints.set({
              condition = bp.condition,
              hit_condition = bp.hitCondition,
              log_message = bp.logMessage,
            }, bufnr, tonumber(bp.line))
          end
        end
      end

      local function load_all_project_breakpoints()
        local json_path = get_breakpoints_path()
        local f = io.open(json_path, "r")
        if not f then
          return
        end
        local content = f:read("*a")
        f:close()
        if not content or content == "" then
          return
        end

        local ok, decoded = pcall(vim.json.decode, content)
        if not ok or not decoded then
          return
        end

        for fname, buf_bps in pairs(decoded) do
          if buf_bps and #buf_bps > 0 then
            local bufnr = vim.fn.bufnr(fname)
            if bufnr == -1 then
              bufnr = vim.fn.bufadd(fname)
              vim.fn.bufload(bufnr)
            end
            if bufnr ~= -1 then
              for _, bp in ipairs(buf_bps) do
                if bp and bp.line then
                  breakpoints.set({
                    condition = bp.condition,
                    hit_condition = bp.hitCondition,
                    log_message = bp.logMessage,
                  }, bufnr, tonumber(bp.line))
                end
              end
            end
          end
        end
      end

      vim.api.nvim_create_user_command("DapClearBreakpointsFile", function()
        local fname = vim.api.nvim_buf_get_name(0)
        if not fname or fname == "" then
          return
        end

        local path = get_breakpoints_path()
        local f = io.open(path, "r")
        if not f then
          return
        end
        local content = f:read("*a")
        f:close()
        if not content or content == "" then
          return
        end

        local ok, decoded = pcall(vim.json.decode, content)
        if not ok or not decoded then
          return
        end

        decoded[fname] = nil
        f = io.open(path, "w")
        if f then
          f:write(vim.json.encode(decoded))
          f:close()
        end
      end, { desc = "Clear breakpoints for current file from .nvim/dap-breakpoints.json" })

      vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function()
          restore_breakpoints_for_buf(vim.api.nvim_get_current_buf())
        end,
      })

      load_all_project_breakpoints()

      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = save_breakpoints,
      })

      local original_toggle = dap.toggle_breakpoint
      dap.toggle_breakpoint = function(...)
        original_toggle(...)
        vim.schedule(save_breakpoints)
      end

      local original_set = dap.set_breakpoint
      dap.set_breakpoint = function(...)
        original_set(...)
        vim.schedule(save_breakpoints)
      end
    end,
  },

  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "nvim-neotest/nvim-nio" },
    keys = {
      { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle DAP UI" },
      { "<leader>dub", function() close_dap_floats(); require("dapui").float_element("breakpoints", { enter = true }) end, desc = "Breakpoints" },
      { "<leader>duw", function() close_dap_floats(); require("dapui").float_element("watches", { enter = true }) end, desc = "Watches" },
      { "<leader>dus", function() close_dap_floats(); require("dapui").float_element("stacks", { enter = true }) end, desc = "Stacks" },
      { "<leader>duc", function()
  close_dap_floats()
  require("dapui").float_element("console", { enter = true })
  vim.schedule(function()
    local keys = { "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "r", "R" }
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, "<NOP>", { buffer = true })
    end
  end)
end, desc = "Console" },
      { "<leader>dur", function() close_dap_floats(); require("dapui").float_element("repl", { enter = true }) end, desc = "REPL" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Eval", mode = { "n", "v" } },
    },
    opts = {
      layouts = {
        {
          elements = {
            { id = "scopes", size = 1.0 },
          },
          size = 15,
          position = "bottom",
        },
      },
      controls = {
        enabled = false,
      },
      floating = {
        max_height = 0.9,
        max_width = 0.9,
        border = "rounded",
        mappings = { close = { "q" } },
      },
      render = { indent = 2, max_value_lines = 100 },
      mappings = {
        expand = { "<2-LeftMouse>" },
        open = { "o", "<CR>" },
      },
    },
    config = function(_, opts)
      local dap = require("dap")
      local dapui = require("dapui")
      dapui.setup(opts)

      local original_float_element = dapui.float_element
      dapui.float_element = function(name, fopts)
        fopts = fopts or {}
        fopts.position = "center"
        if not fopts.width then
          fopts.width = math.floor(vim.o.columns * 0.9)
        end
        if not fopts.height then
          fopts.height = math.floor(vim.o.lines * 0.9)
        end
        return original_float_element(name, fopts)
      end

      local original_eval = dapui.eval
      dapui.eval = function(expression, eopts)
        eopts = eopts or {}
        eopts.position = "center"
        return original_eval(expression, eopts)
      end

      local dapui_util = require("dapui.util")
      local original_open_buf = dapui_util.open_buf
      dapui_util.open_buf = function(bufnr, line, column)
        local result = original_open_buf(bufnr, line, column)
        if not result then
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.api.nvim_win_get_config(win).relative == "" then
              vim.api.nvim_set_current_win(win)
              break
            end
          end
          vim.cmd("edit " .. vim.api.nvim_buf_get_name(bufnr))
          if line then
            vim.api.nvim_win_set_cursor(0, { line, column })
          end
          return true
        end
        return result
      end

      -- Abre sidebar solo al pausar en breakpoint
      dap.listeners.after.event_stopped["dapui_config"] = function()
        dapui.open({})
      end
      
      -- Cierra sidebar cuando continúa la ejecución
      dap.listeners.after.event_continued["dapui_config"] = function()
        dapui.close({})
      end
      
      -- Cierra al terminar
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close({})
      end
      
      -- Cierra al salir
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close({})
      end

    end,
  },

  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = "mason.nvim",
    cmd = { "DapInstall", "DapUninstall" },
    opts = {
      automatic_installation = true,
      handlers = {},
      ensure_installed = {},
    },
    config = function() end,
  },
}
