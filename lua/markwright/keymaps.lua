local config = require("markwright.config")

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
    opts = vim.tbl_extend("force", { buffer = buf, desc = "markwright: " .. desc, silent = true }, opts or {})
    vim.keymap.set(mode, lhs, rhs, opts)
  end

  -- Inline keys (formatting, links) act at once when there's nothing to choose
  -- (inside an existing span or link, on a bare URL, on whitespace) and wait
  -- for a motion on plain text, like d or gu: <P>biw, <P>b$, <P>b_ for the
  -- line ([count] lines). No doubled keys: <P>ii would shadow i{object}.
  -- Visual mode acts on the selection.
  local format = require("markwright.format")
  for _, f in ipairs(FORMAT_KEYS) do
    local desc = "Toggle " .. f.desc:lower()
    map("n", P .. f.key, function()
      return format.expr_smart(f.fmt)
    end, desc, { expr = true })
    map("x", P .. f.key, function()
      return format.expr_operator(f.fmt)
    end, desc, { expr = true })
  end

  -- links
  local links = require("markwright.links")
  local lopts = config.options.links
  -- <P>k: on a link remove it, on a bare URL make a titled link, on whitespace
  -- insert a new link (URL prompt prefilled from the clipboard, then text); on plain text wait
  -- for a motion (<P>kiw, <P>k$)
  map("n", P .. "k", links.expr_smart, "Link: create / convert URL / remove", { expr = true })
  map("x", P .. "k", links.expr_visual, "Link: create / convert URL / remove", { expr = true })
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
      require("markwright.follow").follow()
    end, "Follow link / anchor / footnote")
  end

  -- code fences & footnotes
  -- Block keys (fence, callout, CSV → table) and inserts (footnote, table,
  -- TOC, image) act at once; only inline keys (formatting, links) are operators.
  map("n", P .. "f", function()
    require("markwright.fence").insert()
  end, "Insert code fence")
  map("x", P .. "f", "<Esc><Cmd>lua require('markwright.fence').wrap_visual()<CR>", "Wrap in code fence")
  map("n", P .. "n", function()
    require("markwright.footnotes").insert()
  end, "Insert footnote")

  -- tables
  local tables = require("markwright.tables")
  map("n", P .. "tt", tables.create, "Create table")
  map("n", P .. "tc", tables.from_csv_paragraph, "CSV → table (paragraph)")
  map("x", P .. "tc", "<Esc><Cmd>lua require('markwright.tables').from_csv_visual()<CR>", "CSV → table")
  map("n", P .. "tx", tables.to_csv, "Table → CSV")
  -- h/j/k/l add a column left / row below / row above / column right
  map("n", P .. "th", function()
    tables.add_col(true)
  end, "Add column left")
  map("n", P .. "tj", function()
    tables.add_row()
  end, "Add row below")
  map("n", P .. "tk", function()
    tables.add_row(true)
  end, "Add row above")
  map("n", P .. "tl", function()
    tables.add_col()
  end, "Add column right")
  -- H/J/K/L move the column / row; s sort, T transpose, y copy as CSV
  map("n", P .. "tH", function()
    tables.move_col(-1)
  end, "Move column left")
  map("n", P .. "tJ", function()
    tables.move_row(1)
  end, "Move row down")
  map("n", P .. "tK", function()
    tables.move_row(-1)
  end, "Move row up")
  map("n", P .. "tL", function()
    tables.move_col(1)
  end, "Move column right")
  map("n", P .. "ts", function()
    tables.sort()
  end, "Sort by this column (ascending)")
  map("n", P .. "tS", function()
    tables.sort(true)
  end, "Sort by this column (descending)")
  map("n", P .. "tT", tables.transpose, "Transpose")
  map("n", P .. "ty", tables.yank_csv, "Copy as CSV")
  map("n", P .. "tdr", tables.delete_row, "Delete row")
  map("n", P .. "tdc", tables.delete_col, "Delete column")
  map("n", P .. "ta", function()
    tables.align()
  end, "Align table")

  -- lists: <Tab>/<S-Tab> serve both tables and lists
  local util = require("markwright.util")
  local lists = require("markwright.lists")
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
    map("x", ck, "<Esc><Cmd>lua require('markwright.lists').toggle_visual()<CR>", "Toggle checkboxes")
  end

  -- list tools (<P>l…)
  local lt = require("markwright.listtools")
  map("n", P .. "lj", function()
    lt.move(1)
  end, "Move item down (with children)")
  map("n", P .. "lk", function()
    lt.move(-1)
  end, "Move item up (with children)")
  map("n", P .. "ls", function()
    lt.sort("asc")
  end, "Sort list A→Z")
  map("n", P .. "lS", function()
    lt.sort("desc")
  end, "Sort list Z→A")
  map("n", P .. "ld", function()
    lt.sort("done")
  end, "Sort list: done items last")
  -- converters: plain lines ↔ bullets / numbers / checkboxes
  for key, style in pairs({ b = "bullet", n = "number", c = "checkbox" }) do
    local what = ({ bullet = "bullets", number = "numbers", checkbox = "checkboxes" })[style]
    map("n", P .. "l" .. key, function()
      lt.convert_paragraph(style)
    end, "Lines ↔ " .. what)
    map(
      "x",
      P .. "l" .. key,
      ("<Esc><Cmd>lua require('markwright.listtools').convert_visual(%q)<CR>"):format(style),
      "Lines ↔ " .. what
    )
  end
  local mk = config.options.lists.move_keys
  if type(mk) == "table" then
    for dir, key in pairs({ [1] = mk.down, [-1] = mk.up }) do
      if key and key ~= "" then
        util.save_fallback(buf, "n", key)
        map("n", key, function()
          return lt.expr_move(dir, key)
        end, dir == 1 and "Move item down" or "Move item up", { expr = true })
      end
    end
  end

  -- headings
  local headings = require("markwright.headings")
  map("n", P .. "=", function()
    headings.change_cursor(1)
  end, "Heading: add #")
  map("n", P .. "-", function()
    headings.change_cursor(-1)
  end, "Heading: remove #")
  map("x", P .. "=", "<Esc><Cmd>lua require('markwright.headings').change_visual(1)<CR>", "Heading: add #")
  map("x", P .. "-", "<Esc><Cmd>lua require('markwright.headings').change_visual(-1)<CR>", "Heading: remove #")

  -- heading navigation and outline
  require("markwright.nav").attach(buf)

  -- text objects
  require("markwright.textobjects").attach(buf)

  -- insert-mode formatting trigger (";;" by default)
  require("markwright.insert").attach(buf)

  -- images
  map("n", P .. "p", function()
    require("markwright.images").paste()
  end, "Paste image")
  map(
    "x",
    P .. "p",
    "<Esc><Cmd>lua require('markwright.images').paste_visual()<CR>",
    "Paste image (selection = alt text)"
  )
  map("n", P .. "r", function()
    require("markwright.images").rename()
  end, "Rename image file")

  -- callouts: block keys act at once on the paragraph (or callout) under the cursor
  map("n", P .. "a", function()
    require("markwright.callouts").toggle()
  end, "Callout: wrap / change type")
  map("x", P .. "a", "<Esc><Cmd>lua require('markwright.callouts').wrap_visual()<CR>", "Callout: wrap selection")
  map("n", P .. "A", function()
    require("markwright.callouts").unwrap()
  end, "Callout: remove")

  -- toc
  map("n", P .. "T", function()
    require("markwright.toc").insert()
  end, "Insert / update TOC")

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({
      { P, group = "markdown", buffer = buf, mode = { "n", "x" } },
      { P .. "t", group = "table", buffer = buf, mode = { "n", "x" } },
      { P .. "td", group = "delete", buffer = buf, mode = "n" },
      { P .. "l", group = "list", buffer = buf, mode = { "n", "x" } },
    })
  end
end

return M
