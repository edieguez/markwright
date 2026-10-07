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
  local util = require("markwright.util")
  local function map(mode, lhs, rhs, desc, opts)
    opts = vim.tbl_extend("force", { buffer = buf, desc = "markwright: " .. desc, silent = true }, opts or {})
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  -- actions that change the buffer are repeatable with `.` (see util.lua)
  local function nmap(lhs, fn, desc)
    map(
      "n",
      lhs,
      util.repeatable(function()
        fn()
      end),
      desc,
      { expr = true }
    )
  end
  local function xmap(lhs, fn, desc)
    map(
      "x",
      lhs,
      util.repeatable_visual(function(_, srow, erow)
        fn(srow, erow)
      end),
      desc,
      { expr = true }
    )
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

  -- <P>r: inline [text](url) ↔ reference [text][label] (label from the text,
  -- definitions at the end of the file); visual: every link in the selection
  local refs = require("markwright.refs")
  nmap(P .. "r", refs.toggle, "Link: inline ↔ reference")
  xmap(P .. "r", function(srow, erow)
    refs.convert_range(vim.api.nvim_get_current_buf(), srow, erow)
  end, "Links: inline ↔ reference")

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
    return require("markwright.fence").expr()
  end, "Code fence: wrap the paragraph / insert", { expr = true })
  xmap(P .. "f", function(srow, erow)
    require("markwright.fence").wrap(vim.api.nvim_get_current_buf(), srow, erow)
  end, "Wrap in code fence")
  map("n", P .. "n", function()
    require("markwright.footnotes").insert()
  end, "Insert footnote")

  -- tables
  local tables = require("markwright.tables")
  map("n", P .. "tt", tables.create, "Create table")
  nmap(P .. "tc", tables.from_csv_paragraph, "CSV → table (paragraph)")
  xmap(P .. "tc", function(srow, erow)
    tables.from_csv_prompt(vim.api.nvim_get_current_buf(), srow, erow)
  end, "CSV → table")
  nmap(P .. "tC", tables.to_csv, "Table → CSV")
  -- h/j/k/l add a column left / row below / row above / column right
  nmap(P .. "th", function()
    tables.add_col(true)
  end, "Add column left")
  nmap(P .. "tj", function()
    tables.add_row()
  end, "Add row below")
  nmap(P .. "tk", function()
    tables.add_row(true)
  end, "Add row above")
  nmap(P .. "tl", function()
    tables.add_col()
  end, "Add column right")
  -- H/J/K/L move the column / row; s sort, T transpose, y copy as CSV
  nmap(P .. "tH", function()
    tables.move_col(-1)
  end, "Move column left")
  nmap(P .. "tJ", function()
    tables.move_row(1)
  end, "Move row down")
  nmap(P .. "tK", function()
    tables.move_row(-1)
  end, "Move row up")
  nmap(P .. "tL", function()
    tables.move_col(1)
  end, "Move column right")
  nmap(P .. "ts", function()
    tables.sort()
  end, "Sort by this column (ascending)")
  nmap(P .. "tS", function()
    tables.sort(true)
  end, "Sort by this column (descending)")
  nmap(P .. "tf", tables.transpose, "Flip (transpose)")
  map("n", P .. "ty", tables.yank_csv, "Copy as CSV")
  nmap(P .. "tdr", function()
    tables.delete_row()
  end, "Delete row")
  nmap(P .. "tdc", function()
    tables.delete_col()
  end, "Delete column")
  -- visual: the selected rows / columns ([count] moves them further)
  for lhs, a in pairs({
    tdr = { "delete_row", nil, "Delete selected rows" },
    tdc = { "delete_col", nil, "Delete selected columns" },
    tJ = { "move_row", 1, "Move selected rows down" },
    tK = { "move_row", -1, "Move selected rows up" },
    tH = { "move_col", -1, "Move selected columns left" },
    tL = { "move_col", 1, "Move selected columns right" },
    ts = { "sort", false, "Sort selected rows (ascending)" },
    tS = { "sort", true, "Sort selected rows (descending)" },
  }) do
    map(
      "x",
      P .. lhs,
      util.repeatable_visual(function(_, srow, erow, mtype, scol, ecol)
        tables.visual(a[1], a[2], srow, erow, scol, ecol, mtype)
      end),
      a[3],
      { expr = true }
    )
  end
  nmap(P .. "ta", function()
    tables.align()
  end, "Align table")

  -- lists: <Tab>/<S-Tab> serve both tables and lists
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
    xmap(ck, function(srow, erow)
      lists.toggle_range(srow, erow)
    end, "Toggle checkboxes")
  end

  -- list tools (<P>l…)
  local lt = require("markwright.listtools")
  -- J/K move, like <P>tJ / <P>tK for table rows
  nmap(P .. "lJ", function()
    lt.move(1)
  end, "Move item down (with children)")
  nmap(P .. "lK", function()
    lt.move(-1)
  end, "Move item up (with children)")
  nmap(P .. "ls", function()
    lt.sort("asc")
  end, "Sort list A→Z")
  nmap(P .. "lS", function()
    lt.sort("desc")
  end, "Sort list Z→A")
  nmap(P .. "ld", function()
    lt.sort("done")
  end, "Sort list: done items last")
  -- converters: lines ↔ bullets / numbers / checkboxes. Lowercase: the cursor's
  -- level of the list (or the paragraph); uppercase: that level and every
  -- sub-list below it.
  for key, style in pairs({ b = "bullet", n = "number", c = "checkbox" }) do
    local what = ({ bullet = "bullets", number = "numbers", checkbox = "checkboxes" })[style]
    nmap(P .. "l" .. key, function()
      lt.convert(style)
    end, "Convert to " .. what .. " (this level)")
    nmap(P .. "l" .. key:upper(), function()
      lt.convert(style, true)
    end, "Convert to " .. what .. " (this level and below)")
    local function vis(srow, erow)
      lt.convert_lines(style, srow, erow)
    end
    xmap(P .. "l" .. key, vis, "Convert selection to " .. what)
    xmap(P .. "l" .. key:upper(), vis, "Convert selection to " .. what)
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
  nmap(P .. "=", function()
    headings.change_cursor(1)
  end, "Heading: add #")
  nmap(P .. "-", function()
    headings.change_cursor(-1)
  end, "Heading: remove #")
  for key, delta in pairs({ ["="] = 1, ["-"] = -1 }) do
    xmap(P .. key, function(srow, erow)
      headings.change(vim.api.nvim_get_current_buf(), srow, erow, delta * util.count1())
    end, delta > 0 and "Heading: add #" or "Heading: remove #")
  end

  -- sections (<P>#…, # as in the i# / a# text object): j/k move the section
  -- with its sub-sections (nothing is added here, so the lowercase keys are
  -- free; tables and lists use J/K because j/k add rows); =/- add or remove a # on the
  -- heading and every sub-heading, like <P>= / <P>- for one line
  local sections = require("markwright.sections")
  nmap(P .. "#j", function()
    sections.move(1)
  end, "Move section down")
  nmap(P .. "#k", function()
    sections.move(-1)
  end, "Move section up")
  nmap(P .. "#=", function()
    sections.change(1)
  end, "Section: add # (with sub-headings)")
  nmap(P .. "#-", function()
    sections.change(-1)
  end, "Section: remove # (with sub-headings)")

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
  -- uppercase = acts on an existing image
  map("n", P .. "P", function()
    require("markwright.images").rename()
  end, "Rename image file")

  -- callouts: block keys act at once on the paragraph (or callout) under the cursor
  nmap(P .. "a", function()
    require("markwright.callouts").toggle()
  end, "Callout: wrap / change type")
  xmap(P .. "a", function(srow, erow)
    require("markwright.callouts").wrap_range(vim.api.nvim_get_current_buf(), srow, erow)
  end, "Callout: wrap selection")
  nmap(P .. "A", function()
    require("markwright.callouts").unwrap()
  end, "Callout: remove")

  -- front matter: insert from the template, or jump to it
  map("n", P .. "F", function()
    require("markwright.frontmatter").insert()
  end, "Front matter: insert / go to")

  -- table of contents: the outline (<P>o) written into the file
  map("n", P .. "O", function()
    require("markwright.toc").insert()
  end, "Insert / update table of contents")

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({
      { P, group = "markdown", buffer = buf, mode = { "n", "x" } },
      { P .. "t", group = "table", buffer = buf, mode = { "n", "x" } },
      { P .. "td", group = "delete", buffer = buf, mode = "n" },
      { P .. "l", group = "list", buffer = buf, mode = { "n", "x" } },
      { P .. "#", group = "section", buffer = buf, mode = "n" },
    })
  end
end

return M
