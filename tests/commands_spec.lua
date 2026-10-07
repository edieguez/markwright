-- :Markwright commands that mirror the keys (tables, lists, headings, checkboxes).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local lists = require("markwright.lists")
local eq = H.eq

lists.clock = function()
  return os.time({ year = 2026, month = 10, day = 2, hour = 15, min = 52 })
end
local STAMP = " ✅ 2026-10-02 15:52"

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end

local function run(buf_lines, cursor, cmd, want)
  return function()
    H.buf(buf_lines, cursor)
    vim.cmd(cmd)
    eq(lines(), want)
  end
end

local ROWS = { "| h |", "| - |", "| 1 |", "| 2 |", "| 3 |", "| 4 |" }

local cases = {
  {
    "table move down 2",
    fn = run(ROWS, { 3, 2 }, "Markwright table move down 2", {
      "| h   |",
      "| --- |",
      "| 2   |",
      "| 3   |",
      "| 1   |",
      "| 4   |",
    }),
  },
  {
    "table move right",
    fn = run(
      { "| a | b |", "| - | - |" },
      { 1, 2 },
      "Markwright table move right",
      { "| b   | a   |", "| --- | --- |" }
    ),
  },
  {
    ":range table move up moves the rows together",
    fn = run(ROWS, { 1, 0 }, "5,6Markwright table move up", {
      "| h   |",
      "| --- |",
      "| 1   |",
      "| 3   |",
      "| 4   |",
      "| 2   |",
    }),
  },
  {
    ":range table delrow",
    fn = run(ROWS, { 1, 0 }, "3,4Markwright table delrow", { "| h   |", "| --- |", "| 3   |", "| 4   |" }),
  },
  {
    "table row with a count",
    fn = run({ "| a |", "| - |", "| 1 |" }, { 3, 2 }, "Markwright table row 2", {
      "| a   |",
      "| --- |",
      "| 1   |",
      "|     |",
      "|     |",
    }),
  },
  {
    ":range table sort sorts only those rows",
    fn = run(
      { "| n |", "| - |", "| d |", "| c |", "| b |", "| a |" },
      { 1, 0 },
      "3,5Markwright table sort",
      { "| n   |", "| --- |", "| b   |", "| c   |", "| d   |", "| a   |" }
    ),
  },
  {
    "table fromcsv on the paragraph",
    fn = function()
      H.buf({ "a,b", "1,2" }, { 1, 0 })
      H.queue = { "," }
      vim.cmd("Markwright table fromcsv")
      eq(lines(), { "| a   | b   |", "| --- | --- |", "| 1   | 2   |" })
    end,
  },
  {
    "list down 2",
    fn = run({ "- a", "- b", "- c" }, { 1, 0 }, "Markwright list down 2", { "- b", "- c", "- a" }),
  },
  {
    "heading add / remove, with a count and a range",
    fn = function()
      H.buf({ "a", "b" }, { 1, 0 })
      vim.cmd("Markwright heading add 2")
      eq(lines(), { "## a", "b" })
      vim.cmd("%Markwright heading add")
      eq(lines(), { "### a", "# b" })
      vim.cmd("Markwright heading remove 3")
      eq(lines(), { "a", "# b" })
    end,
  },
  {
    "checkbox, and over a range",
    fn = function()
      H.buf({ "- [ ] a", "- [ ] b" }, { 1, 0 })
      vim.cmd("Markwright checkbox")
      eq(lines(), { "- [x] a" .. STAMP, "- [ ] b" })
      vim.cmd("%Markwright checkbox")
      eq(lines(), { "- [x] a" .. STAMP, "- [x] b" .. STAMP })
    end,
  },
  {
    "completion",
    fn = function()
      H.buf({ "" }, { 1, 0 })
      local c = vim.fn.getcompletion("Markwright ", "cmdline")
      eq(vim.tbl_contains(c, "heading") and vim.tbl_contains(c, "checkbox"), true)
      eq(vim.fn.getcompletion("Markwright table move ", "cmdline"), { "down", "left", "right", "up" })
      eq(vim.fn.getcompletion("Markwright heading ", "cmdline"), { "add", "remove" })
      eq(vim.tbl_contains(vim.fn.getcompletion("Markwright table ", "cmdline"), "fromcsv"), true)
    end,
  },
}

H.mock_input()
local failed, total = H.run("commands", cases)
H.restore_input()
return failed, total
