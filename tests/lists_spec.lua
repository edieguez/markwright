-- Lists + headings specs (SPEC.md sections 9.1, 9.2).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local lists = require("markwright.lists")
local config = require("markwright.config")
local eq = H.eq

-- completion stamps: a fixed clock, formatted in the local time zone
local T0 = os.time({ year = 2026, month = 10, day = 2, hour = 15, min = 52 })
local STAMP = os.date(" ✅ %Y-%m-%d %H:%M", T0) -- " ✅ 2026-10-02 15:52"
lists.clock = function()
  return T0
end
local function done_date(fmt)
  return function()
    config.options.lists.done_date = fmt
  end
end

local cases = {
  -- parsing
  {
    "parse",
    fn = function()
      local p = lists.parse
      eq(p("- item").text, "item")
      eq(p("  * [x] done").check, "x")
      eq(p("  * [x] done").text, "done")
      eq(p("12) twelve").num, 12)
      eq(p("> - quoted").bq, "> ")
      eq(p("-"), p("-") and p("-") or nil) -- bare marker is an (empty) item
      eq(p("- - -"), nil) -- thematic break
      eq(p("---"), nil)
      eq(p("*emphasis* text"), nil)
      eq(p("-5 degrees"), nil)
      eq(p("plain"), nil)
    end,
  },

  -- <CR> continuation (insert mode)
  { "continue bullet", { "- one" }, { 1, 0 }, "A<CR>two<Esc>", { "- one", "- two" } },
  { "continue star + spacing", { "*   one" }, { 1, 0 }, "A<CR>two<Esc>", { "*   one", "*   two" } },
  { "continue ordered", { "1. one" }, { 1, 0 }, "A<CR>two<Esc>", { "1. one", "2. two" } },
  { "continue paren ordered", { "3) c" }, { 1, 0 }, "A<CR>d<Esc>", { "3) c", "4) d" } },
  { "continue checkbox unchecked", { "- [x] done" }, { 1, 0 }, "A<CR>next<Esc>", { "- [x] done", "- [ ] next" } },
  { "continue nested", { "- a", "  - b" }, { 2, 0 }, "A<CR>c<Esc>", { "- a", "  - b", "  - c" } },
  { "continue in blockquote", { "> - a" }, { 1, 0 }, "A<CR>b<Esc>", { "> - a", "> - b" } },
  { "empty item ends the list", { "- a", "- " }, { 2, 0 }, "A<CR>text<Esc>", { "- a", "text" } },
  { "empty checkbox item ends the list", { "- [ ] a", "- [ ] " }, { 2, 0 }, "A<CR>x<Esc>", { "- [ ] a", "x" } },
  { "split item in the middle", { "- hello world" }, { 1, 7 }, "i<CR><Esc>", { "- hello", "- world" } },
  { "<CR> at line start opens line above", { "- a" }, { 1, 0 }, "i<CR><Esc>", { "", "- a" } },
  { "<CR> on plain text is native", { "text" }, { 1, 0 }, "A<CR>more<Esc>", { "text", "more" } },
  { "<CR> in code block is native", { "```", "- a", "```" }, { 2, 0 }, "A<CR>b<Esc>", { "```", "- a", "b", "```" } },
  { "continuing renumbers following items", { "1. a", "2. b" }, { 1, 0 }, "A<CR>x<Esc>", { "1. a", "2. x", "3. b" } },
  { "lazy numbering is kept", { "1. a", "1. b" }, { 2, 0 }, "A<CR>c<Esc>", { "1. a", "1. b", "1. c" } },

  -- o / O
  { "o continues", { "- a" }, { 1, 0 }, "ob<Esc>", { "- a", "- b" } },
  { "O continues above", { "- b" }, { 1, 0 }, "Oa<Esc>", { "- a", "- b" } },
  { "o on ordered renumbers", { "1. a", "2. b" }, { 1, 0 }, "ox<Esc>", { "1. a", "2. x", "3. b" } },
  { "O on ordered renumbers", { "1. a", "2. b" }, { 2, 0 }, "Ox<Esc>", { "1. a", "2. x", "3. b" } },
  { "o on plain text is native", { "text" }, { 1, 0 }, "ob<Esc>", { "text", "b" } },
  { "o is one undo step", { "- a" }, { 1, 0 }, { "ob<Esc>", "u" }, { "- a" } },

  -- <Tab> / <S-Tab> nesting
  { "tab nests under previous sibling", { "- a", "- b" }, { 2, 3 }, "a<Tab><Esc>", { "- a", "  - b" } },
  { "tab aligns with ordered content", { "1. a", "2. b" }, { 2, 3 }, "a<Tab><Esc>", { "1. a", "   1. b" } },
  {
    "tab moves children too",
    { "- a", "- b", "  - c", "    text", "- d" },
    { 2, 0 },
    "i<Tab><Esc>",
    { "- a", "  - b", "    - c", "      text", "- d" },
  },
  { "shift-tab outdents", { "- a", "  - b" }, { 2, 4 }, "a<S-Tab><Esc>", { "- a", "- b" } },
  {
    "shift-tab to parent level",
    { "- a", "  - b", "    - c" },
    { 3, 6 },
    "a<S-Tab><Esc>",
    { "- a", "  - b", "  - c" },
  },
  { "shift-tab at top level does nothing", { "- a" }, { 1, 2 }, "a<S-Tab><Esc>", { "- a" } },
  {
    "nested ordered restarts at 1, rest renumbered",
    { "1. a", "2. b", "3. c" },
    { 2, 0 },
    "i<Tab><Esc>",
    { "1. a", "   1. b", "2. c" },
  },
  {
    "outdent rejoins parent numbering",
    { "1. a", "   1. b", "2. c" },
    { 2, 3 },
    "i<S-Tab><Esc>",
    { "1. a", "2. b", "3. c" },
  },
  { "tab keeps cursor on text", { "- a", "- bc" }, { 2, 3 }, "i<Tab>X<Esc>", { "- a", "  - bXc" } },
  { "tab on plain text is native", { "x" }, { 1, 0 }, "A<Tab><Esc>", { "x   " } },
  {
    "tab in a table still moves cells",
    { "| a | b |", "|---|---|" },
    { 1, 2 },
    "i<Tab>X<Esc>",
    { "| a   | bX  |", "| --- | --- |" },
  },

  -- checkboxes: <CR> in normal mode
  {
    "<CR> checks (and stamps the date and time)",
    { "- [ ] task" },
    { 1, 5 },
    "<CR>",
    { "- [x] task" .. STAMP },
    { 1, 5 },
  },
  { "<CR> unchecks", { "- [x] task" }, { 1, 0 }, "<CR>", { "- [ ] task" } },
  { "<CR> unchecks [X]", { "1. [X] task" }, { 1, 0 }, "<CR>", { "1. [ ] task" } },
  { "<CR> adds a checkbox to a plain item", { "  * task" }, { 1, 4 }, "<CR>", { "  * [ ] task" } },
  { "<CR> on empty item", { "-" }, { 1, 0 }, "<CR>", { "- [ ]" } },
  { "<CR> in blockquote list", { "> - [ ] q" }, { 1, 0 }, "<CR>", { "> - [x] q" .. STAMP } },
  { "<CR> on plain text moves down (native)", { "text", "next" }, { 1, 0 }, "<CR>", { "text", "next" }, { 2, 0 } },
  {
    "<CR> in code block is native",
    { "```", "- [ ] x", "```", "" },
    { 2, 0 },
    "<CR>",
    { "```", "- [ ] x", "```", "" },
    { 3, 0 },
  },
  { "<CR> toggle is one undo step", { "- [ ] a" }, { 1, 0 }, { "<CR>", "u" }, { "- [ ] a" } },
  {
    "visual <CR> checks all",
    { "- [ ] a", "- [x] b", "- c", "text" },
    { 1, 0 },
    "Vjjj<CR>",
    { "- [x] a" .. STAMP, "- [x] b", "- [x] c" .. STAMP, "text" },
  },
  { "visual <CR> unchecks when all checked", { "- [x] a", "- [x] b" }, { 1, 0 }, "Vj<CR>", { "- [ ] a", "- [ ] b" } },

  -- completion dates (lists.done_date)
  { "unchecking removes the stamp", { "- [x] task" .. STAMP }, { 1, 0 }, "<CR>", { "- [ ] task" } },
  { "check, uncheck: back to the original", { "- [ ] task" }, { 1, 0 }, { "<CR>", "<CR>" }, { "- [ ] task" } },
  { "trailing spaces before the stamp are dropped", { "- [ ] task  " }, { 1, 0 }, "<CR>", { "- [x] task" .. STAMP } },
  {
    "an existing stamp isn't doubled",
    { "- [ ] task ✅ 2025-01-01" },
    { 1, 0 },
    "<CR>",
    { "- [x] task ✅ 2025-01-01" },
  },
  { "Obsidian date-only stamp is removed too", { "- [x] task ✅ 2025-01-01" }, { 1, 0 }, "<CR>", { "- [ ] task" } },
  { "[X] unchecks and removes", { "* [X] t ✅ 2025-01-01 09:30" }, { 1, 0 }, "<CR>", { "* [ ] t" } },
  { "multi-line item: stamp on the first line", { "- [ ] a", "  b" }, { 1, 0 }, "<CR>", { "- [x] a" .. STAMP, "  b" } },
  { "adding a checkbox to a plain item doesn't stamp", { "- task" }, { 1, 0 }, "<CR>", { "- [ ] task" } },
  { "check is one undo step with its stamp", { "- [ ] task" }, { 1, 0 }, { "<CR>", "u" }, { "- [ ] task" } },
  {
    "custom format",
    { "- [ ] task" },
    { 1, 0 },
    "<CR>",
    { "- [x] task done:" .. os.date("%d/%m/%Y", T0) },
    setup = done_date("done:%d/%m/%Y"),
  },
  {
    "custom format is removed",
    { "- [x] task done:02/10/2026" },
    { 1, 0 },
    "<CR>",
    { "- [ ] task" },
    setup = done_date("done:%d/%m/%Y"),
  },
  { "done_date = false: no stamp", { "- [ ] task" }, { 1, 0 }, "<CR>", { "- [x] task" }, setup = done_date(false) },
  -- progress cookies (lists.progress)
  {
    "checking a child fills the parent's [/]",
    { "- Release [/]", "  - [ ] docs", "  - [ ] tag" },
    { 2, 0 },
    "<CR>",
    { "- Release [1/2]", "  - [x] docs" .. STAMP, "  - [ ] tag" },
  },
  {
    "percentage cookie",
    { "- Release [%]", "  - [x] a", "  - [ ] b", "  - [ ] c" },
    { 3, 0 },
    "<CR>",
    { "- Release [66%]", "  - [x] a", "  - [x] b" .. STAMP, "  - [ ] c" },
  },
  {
    "unchecking updates the count",
    { "- R [2/2]", "  - [x] a", "  - [x] b" },
    { 3, 0 },
    "<CR>",
    { "- R [1/2]", "  - [x] a", "  - [ ] b" },
  },
  {
    "only direct children count; items without a checkbox are ignored",
    { "- P [/]", "  - [x] a", "    - [ ] a.1", "  - note", "  - [ ] b" },
    { 5, 0 },
    "<CR>",
    { "- P [2/2]", "  - [x] a", "    - [ ] a.1", "  - note", "  - [x] b" .. STAMP },
  },
  {
    "counts roll up through children with their own cookie",
    { "- Project [/]", "  - Phase 1 [/]", "    - [x] a", "    - [ ] b", "  - [x] Phase 2" },
    { 4, 0 },
    "<CR>",
    { "- Project [2/2]", "  - Phase 1 [2/2]", "    - [x] a", "    - [x] b" .. STAMP, "  - [x] Phase 2" },
  },
  {
    "a parent with a checkbox isn't checked automatically",
    { "- [ ] Docs [/]", "  - [ ] readme" },
    { 2, 0 },
    "<CR>",
    { "- [ ] Docs [1/1]", "  - [x] readme" .. STAMP },
  },
  {
    "visual <CR> updates cookies once",
    { "- T [%]", "  - [ ] a", "  - [ ] b" },
    { 2, 0 },
    "Vj<CR>",
    { "- T [100%]", "  - [x] a" .. STAMP, "  - [x] b" .. STAMP },
  },
  {
    "cookie in the middle of the text, numbered list",
    { "1. Ship [/] this week", "   1. [x] build", "   2. [ ] test" },
    { 3, 0 },
    "<CR>",
    { "1. Ship [2/2] this week", "   1. [x] build", "   2. [x] test" .. STAMP },
  },
  {
    "both cookies on one item",
    { "- Release [/] [%]", "  - [x] a", "  - [ ] b" },
    { 3, 0 },
    "<CR>",
    { "- Release [2/2] [100%]", "  - [x] a", "  - [x] b" .. STAMP },
  },
  {
    "both cookies, any order, with text between",
    { "- [%] done of [/] tasks", "  - [x] a", "  - [ ] b", "  - [ ] c" },
    { 3, 0 },
    "<CR>",
    { "- [66%] done of [2/3] tasks", "  - [x] a", "  - [x] b" .. STAMP, "  - [ ] c" },
  },
  {
    "a link isn't a cookie",
    { "- see [1/2](url) [/]", "  - [ ] a" },
    { 2, 0 },
    "<CR>",
    { "- see [1/2](url) [1/1]", "  - [x] a" .. STAMP },
  },
  {
    "typing a cookie fills it on InsertLeave",
    { "- Release", "  - [x] a", "  - [ ] b" },
    { 1, 0 },
    "A [/]<Esc>",
    { "- Release [1/2]", "  - [x] a", "  - [ ] b" },
  },
  {
    "deleting a child updates the count (one undo step)",
    { "- R [1/2]", "  - [x] a", "  - [ ] b" },
    { 3, 0 },
    { "dd", "u" },
    { "- R [1/2]", "  - [x] a", "  - [ ] b" },
  },
  {
    "deleting a child updates the count",
    { "- R [1/2]", "  - [x] a", "  - [ ] b" },
    { 3, 0 },
    "dd",
    { "- R [1/1]", "  - [x] a" },
  },
  -- cookies on the line above a list
  {
    "heading above a checklist",
    { "## Tasks [/]", "", "- [ ] a", "- [x] b" },
    { 3, 0 },
    "<CR>",
    { "## Tasks [2/2]", "", "- [x] a" .. STAMP, "- [x] b" },
  },
  {
    "paragraph line right above a checklist",
    { "Groceries [%]", "- [x] milk", "- [ ] eggs", "- [ ] bread" },
    { 3, 0 },
    "<CR>",
    { "Groceries [66%]", "- [x] milk", "- [x] eggs" .. STAMP, "- [ ] bread" },
  },
  {
    "paragraph above with a blank line, both cookies",
    { "Shopping: [/] [%]", "", "- [ ] a", "- [ ] b" },
    { 3, 0 },
    "<CR>",
    { "Shopping: [1/2] [50%]", "", "- [x] a" .. STAMP, "- [ ] b" },
  },
  {
    "only the paragraph's last line labels the list",
    { "Plan [/]", "for the week", "- [ ] a" },
    { 3, 0 },
    "<CR>",
    { "Plan [/]", "for the week", "- [x] a" .. STAMP },
  },
  {
    "setext heading",
    { "Tasks [/]", "=====", "", "- [ ] a" },
    { 4, 0 },
    "<CR>",
    { "Tasks [1/1]", "=====", "", "- [x] a" .. STAMP },
  },
  {
    "callout title above a checklist",
    { "> [!NOTE] Todo [/]", "> - [ ] a", "> - [ ] b" },
    { 2, 0 },
    "<CR>",
    { "> [!NOTE] Todo [1/2]", "> - [x] a" .. STAMP, "> - [ ] b" },
  },
  {
    "label counts roll up through items with their own cookie",
    { "# Release [/]", "", "- Docs [/]", "  - [x] readme", "- [ ] tag" },
    { 5, 0 },
    "<CR>",
    { "# Release [2/2]", "", "- Docs [1/1]", "  - [x] readme", "- [x] tag" .. STAMP },
  },
  {
    "a heading with text before the list isn't a label",
    { "## Tasks [/]", "", "Intro.", "", "- [ ] a" },
    { 5, 0 },
    "<CR>",
    { "## Tasks [/]", "", "Intro.", "", "- [x] a" .. STAMP },
  },
  {
    "a cookie in inline code isn't filled",
    { "Type `[/]` here:", "- [ ] a" },
    { 2, 0 },
    "<CR>",
    { "Type `[/]` here:", "- [x] a" .. STAMP },
  },
  {
    "typing a label cookie fills it on InsertLeave",
    { "Todo", "- [x] a", "- [ ] b" },
    { 1, 0 },
    "A [/]<Esc>",
    { "Todo [1/2]", "- [x] a", "- [ ] b" },
  },
  {
    "cookies are left alone with progress = false",
    { "- R [/]", "  - [ ] a" },
    { 2, 0 },
    "<CR>",
    { "- R [/]", "  - [x] a" .. STAMP },
    setup = function()
      config.options.lists.progress = false
    end,
  },
  {
    "cookies are refreshed on save",
    fn = function()
      local path = vim.fn.tempname() .. ".md"
      local buf = H.buf({ "- R [/]", "  - [x] a", "  - [x] b" }, { 1, 0 }, path)
      vim.bo[buf].buftype = ""
      vim.cmd("silent write")
      eq(vim.fn.readfile(path), { "- R [2/2]", "  - [x] a", "  - [x] b" })
      vim.fn.delete(path)
    end,
  },
  {
    "cookies in code blocks are left alone",
    fn = function()
      local buf = H.buf({ "```", "- R [/]", "  - [x] a", "```" })
      lists.update_progress(buf)
      eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "```", "- R [/]", "  - [x] a", "```" })
    end,
  },
  {
    "stamp pattern",
    fn = function()
      eq(("x ✅ 2026-10-02 15:52"):match(lists.stamp_pattern("✅ %Y-%m-%d %H:%M")) ~= nil, true)
      eq(("x ✅ 2026-10-02"):match(lists.stamp_pattern("✅ %Y-%m-%d %H:%M")), nil)
      eq(("x (done 2026-10-02)"):match(lists.stamp_pattern("(done %F)")) ~= nil, true)
      eq(lists.strip_stamp("- [x] a ✅ 2026-10-02 15:52 "), "- [x] a")
      eq(lists.strip_stamp("- [x] a ✅ tomorrow"), nil)
    end,
  },

  -- auto-renumber after normal-mode edits
  { "dd renumbers", { "1. a", "2. b", "3. c" }, { 2, 0 }, "dd", { "1. a", "2. c" } },
  { "first number defines the start", { "1. a", "2. b", "3. c" }, { 1, 0 }, "dd", { "2. b", "3. c" } },
  { "dd renumber undoes in one step", { "1. a", "2. b", "3. c" }, { 2, 0 }, { "dd", "u" }, { "1. a", "2. b", "3. c" } },
  { "renumber keeps the start number", { "5. a", "9. b" }, { 1, 0 }, "ox<Esc>", { "5. a", "6. x", "7. b" } },
  {
    "wider numbers shift continuation lines",
    { "8. a", "9. b", "   more", "10. c" },
    { 1, 0 },
    "ox<Esc>",
    { "8. a", "9. x", "10. b", "    more", "11. c" },
  },
  { "p of a list item renumbers", { "1. a", "2. b" }, { 1, 0 }, "yyjp", { "1. a", "2. b", "3. a" } },

  -- headings
  { "add # to plain line", { "Title" }, { 1, 0 }, " m=", { "# Title" } },
  { "add # to heading", { "## Title" }, { 1, 0 }, " m=", { "### Title" } },
  { "remove #", { "## Title" }, { 1, 0 }, " m-", { "# Title" } },
  { "remove last # makes plain text", { "# Title" }, { 1, 0 }, " m-", { "Title" } },
  { "count", { "Title" }, { 1, 0 }, "3 m=", { "### Title" } },
  { "capped at 6", { "###### T" }, { 1, 0 }, " m=", { "###### T" } },
  { "plain text: remove does nothing", { "Title" }, { 1, 0 }, " m-", { "Title" } },
  { "closing hashes kept", { "## Title ##" }, { 1, 0 }, " m=", { "### Title ##" } },
  { "setext h1 converted", { "Title", "=====" }, { 1, 0 }, " m=", { "## Title" } },
  { "setext h2 converted", { "Title", "-----", "text" }, { 2, 0 }, " m-", { "# Title", "text" } },
  { "visual range", { "# A", "text", "", "## B" }, { 1, 0 }, "Vjjj m=", { "## A", "# text", "", "### B" } },
  { "headings skip code", { "```", "code", "```" }, { 2, 0 }, " m=", { "```", "code", "```" } },
  { "heading change is one undo step", { "Title" }, { 1, 0 }, { " m=", "u" }, { "Title" } },
}

local default_done = config.options.lists.done_date
return H.run("lists + headings", cases, {
  before_each = function()
    config.options.lists.done_date = default_done
    config.options.lists.progress = true
  end,
})
