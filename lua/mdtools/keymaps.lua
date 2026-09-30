local config = require("mdtools.config")

local M = {}

local FORMAT_KEYS = {
  { key = "i", fmt = "italic", desc = "Italic" },
  { key = "b", fmt = "bold", desc = "Bold" },
  { key = "s", fmt = "strike", desc = "Strikethrough" },
  { key = "c", fmt = "code", desc = "Inline code" },
  { key = "h", fmt = "highlight", desc = "Highlight" },
}

function M.attach(buf)
  local km = config.options.keymaps
  if not km.enabled then
    return
  end
  local P = km.prefix
  local function map(mode, lhs, rhs, desc, opts)
    opts = vim.tbl_extend("force", { buffer = buf, desc = "mdtools: " .. desc, silent = true }, opts or {})
    vim.keymap.set(mode, lhs, rhs, opts)
  end

  for _, f in ipairs(FORMAT_KEYS) do
    local format = require("mdtools.format")
    map("n", P .. f.key, function()
      return format.expr_normal(f.fmt)
    end, "Toggle " .. f.desc:lower(), { expr = true })
    map("x", P .. f.key, function()
      return format.expr_operator(f.fmt)
    end, "Toggle " .. f.desc:lower(), { expr = true })
    -- operator version: <P>I{motion}, <P>B{motion}, ...  [OPEN] key choice
    map("n", P .. f.key:upper(), function()
      return format.expr_operator(f.fmt)
    end, f.desc .. " (operator)", { expr = true })
  end

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({ { P, group = "markdown", buffer = buf, mode = { "n", "x" } } })
  end
end

return M
