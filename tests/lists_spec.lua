-- Lists + headings specs (SPEC.md sections 9.1, 9.2).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local lists = require("markwright.lists")
local eq = H.eq

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
  { "<CR> checks", { "- [ ] task" }, { 1, 5 }, "<CR>", { "- [x] task" }, { 1, 5 } },
  { "<CR> unchecks", { "- [x] task" }, { 1, 0 }, "<CR>", { "- [ ] task" } },
  { "<CR> unchecks [X]", { "1. [X] task" }, { 1, 0 }, "<CR>", { "1. [ ] task" } },
  { "<CR> adds a checkbox to a plain item", { "  * task" }, { 1, 4 }, "<CR>", { "  * [ ] task" } },
  { "<CR> on empty item", { "-" }, { 1, 0 }, "<CR>", { "- [ ]" } },
  { "<CR> in blockquote list", { "> - [ ] q" }, { 1, 0 }, "<CR>", { "> - [x] q" } },
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
    { "- [x] a", "- [x] b", "- [x] c", "text" },
  },
  { "visual <CR> unchecks when all checked", { "- [x] a", "- [x] b" }, { 1, 0 }, "Vj<CR>", { "- [ ] a", "- [ ] b" } },

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

return H.run("lists + headings", cases)
