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

  -- links
  local links = require("mdtools.links")
  local lopts = config.options.links
  map("n", P .. "l", links.expr_normal, "Link: create / convert URL / remove", { expr = true })
  map("x", P .. "l", links.expr_visual, "Link: create / convert URL / remove", { expr = true })
  if lopts.smart_paste_normal then
    map("n", "p", function()
      return links.expr_paste(true)
    end, "Paste (URL → titled link)", { expr = true })
    map("n", "P", function()
      return links.expr_paste(false)
    end, "Paste before (URL → titled link)", { expr = true })
  end
  if lopts.smart_paste_visual then
    map("x", "p", links.expr_paste_visual, "Paste (URL over selection → link)", { expr = true })
  end

  -- follow
  local fkey = config.options.follow.key
  if fkey and fkey ~= "" then
    map("n", fkey, function()
      require("mdtools.follow").follow()
    end, "Follow link / anchor / footnote")
  end

  -- code fences & footnotes
  map("n", P .. "f", function()
    require("mdtools.fence").insert()
  end, "Insert code fence")
  map("x", P .. "f", "<Esc><Cmd>lua require('mdtools.fence').wrap_visual()<CR>", "Wrap in code fence")
  map("n", P .. "n", function()
    require("mdtools.footnotes").insert()
  end, "Insert footnote")

  -- tables
  local tables = require("mdtools.tables")
  map("n", P .. "tt", tables.create, "Create table")
  map("x", P .. "tc", "<Esc><Cmd>lua require('mdtools.tables').from_csv_visual()<CR>", "CSV → table")
  map("n", P .. "tr", tables.add_row, "Add row below")
  map("n", P .. "tR", tables.delete_row, "Delete row")
  map("n", P .. "tk", tables.add_col, "Add column right")
  map("n", P .. "tK", tables.delete_col, "Delete column")
  map("n", P .. "ta", function()
    tables.align()
  end, "Align table")

  -- lists: <Tab>/<S-Tab> serve both tables and lists
  local util = require("mdtools.util")
  local lists = require("mdtools.lists")
  for _, t in ipairs({ { "<Tab>", 1, "Next cell / indent item" }, { "<S-Tab>", -1, "Previous cell / outdent item" } }) do
    util.save_fallback(buf, "i", t[1])
    map("i", t[1], function()
      return lists.expr_tab(t[2])
    end, t[3], { expr = true })
  end
  util.save_fallback(buf, "i", "<CR>")
  map("i", "<CR>", lists.expr_enter, "Continue list", { expr = true })
  map("n", "o", function()
    return lists.expr_open(true)
  end, "Open line (continues lists)", { expr = true })
  map("n", "O", function()
    return lists.expr_open(false)
  end, "Open line above (continues lists)", { expr = true })
  local ck = config.options.lists.checkbox_key
  if ck and ck ~= "" then
    util.save_fallback(buf, "n", ck)
    map("n", ck, lists.expr_checkbox, "Toggle checkbox", { expr = true })
    map("x", ck, "<Esc><Cmd>lua require('mdtools.lists').toggle_visual()<CR>", "Toggle checkboxes")
  end

  -- headings
  local headings = require("mdtools.headings")
  map("n", P .. "=", function()
    headings.change_cursor(1)
  end, "Heading: add #")
  map("n", P .. "-", function()
    headings.change_cursor(-1)
  end, "Heading: remove #")
  map("x", P .. "=", "<Esc><Cmd>lua require('mdtools.headings').change_visual(1)<CR>", "Heading: add #")
  map("x", P .. "-", "<Esc><Cmd>lua require('mdtools.headings').change_visual(-1)<CR>", "Heading: remove #")

  -- insert-mode formatting trigger (";;" by default)
  require("mdtools.insert").attach(buf)

  -- images
  map("n", P .. "p", function()
    require("mdtools.images").paste()
  end, "Paste image")
  map("x", P .. "p", "<Esc><Cmd>lua require('mdtools.images').paste_visual()<CR>", "Paste image (selection = alt text)")

  -- toc
  map("n", P .. "T", function()
    require("mdtools.toc").insert()
  end, "Insert / update TOC")

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({
      { P, group = "markdown", buffer = buf, mode = { "n", "x" } },
      { P .. "t", group = "table", buffer = buf, mode = { "n", "x" } },
    })
  end
end

return M
