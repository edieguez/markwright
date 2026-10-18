-- Minimal init for headless tests:
--   nvim --headless -u tests/minimal_init.lua -c "lua dofile('tests/format_spec.lua')"
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false
vim.g.mapleader = " "
vim.cmd("runtime plugin/markwright.lua")
-- usage counts (on by default) go to a temporary file, never the real one
require("markwright.usage")._default_file = vim.fn.tempname() .. "-usage.json"
require("markwright").setup({})
