-- List tools specs (SPEC.md section 14.12).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local lists = require("markwright.lists")
local eq = H.eq

lists.clock = function()
  return os.time({ year = 2026, month = 10, day = 2, hour = 15, min = 52 })
end

local NESTED = { "- a", "  - a1", "  - a2", "- b", "- c" }

local cases = {
  -- move
  { "move down with children", NESTED, { 1, 2 }, " mlj", { "- b", "- a", "  - a1", "  - a2", "- c" }, { 2, 2 } },
  { "move up with children", NESTED, { 4, 0 }, " mlk", { "- b", "- a", "  - a1", "  - a2", "- c" }, { 1, 0 } },
  {
    "cursor on a child moves the child",
    NESTED,
    { 2, 4 },
    " mlj",
    { "- a", "  - a2", "  - a1", "- b", "- c" },
    { 3, 4 },
  },
  { "count", NESTED, { 1, 0 }, "2 mlj", { "- b", "- c", "- a", "  - a1", "  - a2" }, { 3, 0 } },
  { "no move past the last sibling", NESTED, { 5, 0 }, " mlj", NESTED },
  { "a child doesn't leave its parent", NESTED, { 3, 4 }, " mlj", NESTED },
  {
    "ordered lists are renumbered",
    { "1. one", "2. two", "3. three" },
    { 1, 0 },
    " mlj",
    { "1. two", "2. one", "3. three" },
    { 2, 0 },
  },
  {
    "blank lines between items stay in place",
    { "- a", "", "- b", "  more b", "", "- c" },
    { 1, 0 },
    " mlj",
    { "- b", "  more b", "", "- a", "", "- c" },
    { 4, 0 },
  },
  { "move is one undo step", { "1. a", "2. b" }, { 1, 0 }, { " mlj", "u" }, { "1. a", "2. b" } },
  { "move in a blockquote", { "> - a", "> - b" }, { 1, 3 }, " mlj", { "> - b", "> - a" } },
  {
    "progress cookies follow",
    { "- P [/]", "  - [x] a", "  - [ ] b", "- Q [/]", "  - [ ] c" },
    { 3, 4 },
    " mlk",
    { "- P [1/2]", "  - [ ] b", "  - [x] a", "- Q [0/1]", "  - [ ] c" },
  },
  { "not on a list item", { "text" }, { 1, 0 }, " mlj", { "text" } },

  -- sort
  {
    "sort A→Z",
    { "- banana", "- Apple", "- cherry" },
    { 1, 0 },
    " mls",
    { "- Apple", "- banana", "- cherry" },
    { 2, 0 },
  },
  {
    "sort again: Z→A",
    { "- banana", "- Apple", "- cherry" },
    { 1, 0 },
    { " mls", " mls" },
    { "- cherry", "- banana", "- Apple" },
  },
  {
    "children move with their parent",
    { "- b", "  - b1", "- a", "  - a1" },
    { 1, 0 },
    " mls",
    { "- a", "  - a1", "- b", "  - b1" },
  },
  {
    "sort ignores checkboxes and emphasis",
    { "- [x] **zeta**", "- [ ] alpha", "- *mid*" },
    { 1, 0 },
    " mls",
    { "- [ ] alpha", "- *mid*", "- [x] **zeta**" },
  },
  {
    "numbered list is renumbered after sorting",
    { "1. b", "2. a", "3. c" },
    { 1, 0 },
    " mls",
    { "1. a", "2. b", "3. c" },
  },
  {
    "sort: done items last, order kept",
    { "- [x] one", "- [ ] two", "- [x] three", "- four", "- [ ] five" },
    { 1, 0 },
    " mld",
    { "- [ ] two", "- four", "- [ ] five", "- [x] one", "- [x] three" },
  },
  { "sort is one undo step", { "- b", "- a" }, { 1, 0 }, { " mls", "u" }, { "- b", "- a" } },

  -- converters: lines ↔ bullets / numbers / checkboxes
  { "paragraph → bullets", { "one", "two", "", "three" }, { 1, 0 }, " mlb", { "- one", "- two", "", "three" } },
  { "bullets → plain", { "- one", "* two" }, { 1, 0 }, " mlb", { "one", "two" } },
  { "paragraph → numbers", { "one", "two" }, { 2, 0 }, " mln", { "1. one", "2. two" } },
  { "numbers → plain", { "1. one", "2) two" }, { 1, 0 }, " mln", { "one", "two" } },
  { "paragraph → checkboxes", { "one", "two" }, { 1, 0 }, " mlc", { "- [ ] one", "- [ ] two" } },
  { "checkboxes → plain (checked or not)", { "- [x] one", "- [ ] two" }, { 1, 0 }, " mlc", { "one", "two" } },
  { "bullets → numbers", { "- one", "- two" }, { 1, 0 }, " mln", { "1. one", "2. two" } },
  { "numbers → bullets", { "1. one", "2. two" }, { 1, 0 }, " mlb", { "- one", "- two" } },
  { "bullets → checkboxes keep the bullet", { "* one", "* two" }, { 1, 0 }, " mlc", { "* [ ] one", "* [ ] two" } },
  { "numbers → checkboxes stay numbered", { "1. one", "2. two" }, { 1, 0 }, " mlc", { "1. [ ] one", "2. [ ] two" } },
  { "checkboxes → bullets drop the box", { "+ [x] one", "+ [ ] two" }, { 1, 0 }, " mlb", { "+ one", "+ two" } },
  { "checkboxes → numbers", { "- [x] one", "- [ ] two" }, { 1, 0 }, " mln", { "1. one", "2. two" } },
  { "the number delimiter is kept", { "1) one", "two" }, { 1, 0 }, " mln", { "1) one", "2. two" } },
  { "mixed lines: plain ones join the style", { "- one", "two" }, { 1, 0 }, " mlb", { "- one", "- two" } },
  {
    "nested items: numbering per level",
    { "a", "  x", "  y", "b" },
    { 1, 0 },
    " mln",
    { "1. a", "   1. x", "   2. y", "2. b" },
  },
  { "nested bullets", { "a", "  x", "b" }, { 1, 0 }, " mlb", { "- a", "  - x", "- b" } },
  {
    "re-indented when the parent's marker grows",
    { "- a", "  - x", "- b" },
    { 1, 0 },
    " mln",
    { "1. a", "   1. x", "2. b" },
  },
  { "visual: only the selection", { "a", "b", "c" }, { 2, 0 }, "Vj mlb", { "a", "- b", "- c" } },
  { "visual numbers", { "a", "", "b" }, { 1, 0 }, "Vjj mln", { "1. a", "", "2. b" } },
  { "inside a quote", { "> one", "> two" }, { 1, 2 }, " mlb", { "> - one", "> - two" } },
  { "headings and fences are skipped", { "# T", "a" }, { 1, 0 }, "Vj mlb", { "# T", "- a" } },
  { "conversion is one undo step", { "a", "b" }, { 1, 0 }, { " mlc", "u" }, { "a", "b" } },
  {
    "lists.bullet and lists.number_delim pick new markers",
    fn = function()
      config.options.lists.bullet, config.options.lists.number_delim = "*", ")"
      H.buf({ "a", "b" }, { 1, 0 })
      H.feed(" mlb")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "* a", "* b" })
      H.buf({ "a", "b" }, { 1, 0 })
      H.feed(" mln")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "1) a", "2) b" })
      config.options.lists.bullet, config.options.lists.number_delim = "-", "."
    end,
  },

  -- commands
  {
    ":Markwright list",
    fn = function()
      H.buf({ "- b", "- a" }, { 1, 0 })
      vim.cmd("Markwright list sort")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "- a", "- b" })
      vim.cmd("Markwright list up")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "- b", "- a" })
      vim.cmd("Markwright list number")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "1. b", "2. a" })
      vim.cmd("Markwright list checkbox")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "1. [ ] b", "2. [ ] a" })
      vim.cmd("1Markwright list bullet")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "- b", "2. [ ] a" })
      eq(vim.fn.getcompletion("Markwright list ", "cmdline"), { "bullet", "checkbox", "down", "number", "sort", "up" })
    end,
  },

  -- optional move keys
  {
    "lists.move_keys: moves on items, previous mapping elsewhere",
    fn = function()
      vim.keymap.set("n", "<M-j>", "<Cmd>let g:mw_moved = 1<CR>")
      config.options.lists.move_keys = { down = "<M-j>", up = "<M-k>" }
      H.buf({ "- a", "- b", "", "text" }, { 1, 0 })
      config.options.lists.move_keys = nil
      H.feed("<M-j>")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "- b", "- a", "", "text" })
      api.nvim_win_set_cursor(0, { 4, 0 })
      vim.g.mw_moved = 0
      H.feed("<M-j>")
      eq(vim.g.mw_moved, 1)
      pcall(vim.keymap.del, "n", "<M-j>")
    end,
  },
}

return H.run("list tools", cases)
