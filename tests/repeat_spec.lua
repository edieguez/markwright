-- Dot-repeat specs: every <leader>m action that changes the buffer repeats
-- with `.`, reusing the answers to its prompts.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local config = require("markwright.config")
local links = require("markwright.links")
local title = require("markwright.title")
local lists = require("markwright.lists")
local eq = H.eq

lists.clock = function()
  return os.time({ year = 2026, month = 10, day = 2, hour = 15, min = 52 })
end
local STAMP = " ✅ 2026-10-02 15:52"

local real_select, real_clip, real_fetch = vim.ui.select, links.read_clipboard, title.fetch
local picks, asked
local function before_each()
  H.queue, picks, asked = {}, {}, 0
  config.options.callouts.default = nil
  vim.ui.select = function(_, _, cb)
    asked = asked + 1
    cb(table.remove(picks, 1))
  end
  links.read_clipboard = function()
    return ""
  end
  title.fetch = function(_, cb)
    cb("Title")
  end
end

local function answers(...)
  local list = { ... }
  return function()
    H.queue = list
  end
end

local T = { "| a | b |", "| - | - |", "| 1 | 2 |" }

local cases = {
  -- tables
  {
    "add row above, repeated",
    T,
    { 3, 2 },
    { " mtk", "." },
    { "| a   | b   |", "| --- | --- |", "|     |     |", "|     |     |", "| 1   | 2   |" },
  },
  {
    "add column right, repeated",
    { "| a |", "| - |", "| 1 |" },
    { 1, 2 },
    { " mtl", "." },
    { "| a   |     |     |", "| --- | --- | --- |", "| 1   |     |     |" },
  },
  {
    "move row with a count, repeated with the same count",
    { "| h |", "| - |", "| 1 |", "| 2 |", "| 3 |", "| 4 |", "| 5 |" },
    { 3, 2 },
    { "2 mtJ", "." },
    { "| h   |", "| --- |", "| 2   |", "| 3   |", "| 4   |", "| 5   |", "| 1   |" },
  },
  {
    "flip, repeated, gives the table back",
    T,
    { 1, 2 },
    { " mtf", "." },
    { "| a   | b   |", "| --- | --- |", "| 1   | 2   |" },
  },
  {
    "delete row, repeated",
    { "| a |", "| - |", "| 1 |", "| 2 |", "| 3 |" },
    { 3, 2 },
    { " mtdr", "." },
    { "| a   |", "| --- |", "| 3   |" },
  },
  {
    "CSV → table reuses the separator",
    { "a;b", "1;2", "", "c;d", "3;4" },
    { 1, 0 },
    { " mtc", "4j." },
    { "| a   | b   |", "| --- | --- |", "| 1   | 2   |", "", "| c   | d   |", "| --- | --- |", "| 3   | 4   |" },
    setup = answers(";"),
  },
  {
    "N. repeats with the new count, later . keep it",
    { "| h |", "| - |", "| 1 |", "| 2 |", "| 3 |", "| 4 |", "| 5 |", "| 6 |", "| 7 |" },
    { 3, 2 },
    { " mtJ", "2.", "." },
    { "| h   |", "| --- |", "| 2   |", "| 3   |", "| 4   |", "| 5   |", "| 6   |", "| 1   |", "| 7   |" },
  },
  { "N. on headings", { "Title" }, { 1, 0 }, { " m=", "2." }, { "### Title" } },
  -- lists
  {
    "move item, repeated",
    { "- a", "- b", "- c" },
    { 1, 0 },
    { " mlJ", "." },
    { "- b", "- c", "- a" },
  },
  { "each repeat is one undo step", { "- a", "- b", "- c" }, { 1, 0 }, { " mlJ", ".", "u" }, { "- b", "- a", "- c" } },
  {
    "convert to bullets, repeated on another paragraph",
    { "a", "b", "", "c" },
    { 1, 0 },
    { " mlb", "3j." },
    { "- a", "- b", "", "- c" },
  },
  {
    "visual convert, repeated over as many lines",
    { "a", "b", "c", "d" },
    { 1, 0 },
    { "Vj mlb", "jj." },
    { "- a", "- b", "- c", "- d" },
  },
  {
    "checkbox <CR>, repeated",
    { "- [ ] a", "- [ ] b" },
    { 1, 0 },
    { "<CR>", "j." },
    { "- [x] a" .. STAMP, "- [x] b" .. STAMP },
  },
  -- headings
  { "add #, repeated", { "Title" }, { 1, 0 }, { " m=", "." }, { "## Title" } },
  { "visual add #, repeated", { "a", "b", "c", "d" }, { 1, 0 }, { "Vj m=", "jj." }, { "# a", "# b", "# c", "# d" } },
  -- callouts
  {
    "callout reuses the picked type",
    { "one", "", "two" },
    { 1, 0 },
    { " ma", "jj." },
    { "> [!TIP]", "> one", "", "> [!TIP]", "> two" },
    setup = function()
      picks = { "TIP" }
    end,
  },
  {
    "remove callout, repeated",
    { "> [!NOTE]", "> a", "", "> [!TIP]", "> b" },
    { 2, 2 },
    { " mA", "2j." },
    { "a", "", "b" },
  },
  -- links
  {
    "remove link, repeated",
    { "[a](x) and [b](y)" },
    { 1, 1 },
    { " mk", "f[." },
    { "a and b" },
  },
  {
    "bare URL → titled link, repeated",
    { "https://a.io", "https://b.io" },
    { 1, 0 },
    { " mk", "j." },
    { "[Title](https://a.io)", "[Title](https://b.io)" },
  },
  {
    "new link on an empty line reuses URL and text",
    { "", "" },
    { 1, 0 },
    { " mk", "j." },
    { "[docs](https://x.io)", "[docs](https://x.io)" },
    setup = answers("https://x.io", "docs"),
  },
  -- fences
  {
    "visual fence reuses the language",
    { "a", "", "b" },
    { 1, 0 },
    { "V mf", "4j." },
    { "```lua", "a", "```", "", "```lua", "b", "```" },
    setup = answers("lua"),
  },
  {
    "a repeat only asks what it doesn't know",
    fn = function()
      H.buf({ "one", "", "two" }, { 1, 0 })
      picks = { "TIP" }
      H.feed({ " ma", "jj." })
      eq(asked, 1)
    end,
  },
}

H.mock_input()
local failed, total = H.run("dot-repeat", cases, { before_each = before_each })
H.restore_input()
vim.ui.select, links.read_clipboard, title.fetch = real_select, real_clip, real_fetch
return failed, total
