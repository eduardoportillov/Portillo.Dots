-- This file contains the configuration for disabling specific Neovim plugins.
return {{
    --  muestra pistas visuales de hacia dónde irán tus movimientos con j, k, w, b, e, etc.
    "tris203/precognition.nvim",
    enabled = true
}, {
    -- añade una animación suave al cursor cuando se mueve.
    "sphamba/smear-cursor.nvim",
    enabled = true
}, {
    "CopilotC-Nvim/CopilotChat.nvim",
    enabled = true
}, {
    -- URL: https://github.com/greggh/claude-code.nvim
    "coder/claudecode.nvim",
    enabled = false
}, {
    "NickvanDyke/opencode.nvim",
    enabled = false
}}
