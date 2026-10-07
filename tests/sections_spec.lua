-- Section specs (SPEC.md section 14.16).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local eq = H.eq

local DOC = {
  "# A",
  "a text",
  "",
  "## A.1",
  "one",
  "",
  "## A.2",
  "two",
  "",
  "### A.2.1",
  "deep",
  "",
  "## A.3",
  "three",
  "",
  "# B",
  "b text",
}

local cases = {
  -- move
  {
    "move down past the next sibling, with sub-sections",
    DOC,
    { 7, 0 },
    " m#j",
    {
      "# A",
      "a text",
      "",
      "## A.1",
      "one",
      "",
      "## A.3",
      "three",
      "",
      "## A.2",
      "two",
      "",
      "### A.2.1",
      "deep",
      "",
      "# B",
      "b text",
    },
    { 10, 0 },
  },
  {
    "move up from inside the section's text",
    DOC,
    { 8, 1 },
    " m#k",
    {
      "# A",
      "a text",
      "",
      "## A.2",
      "two",
      "",
      "### A.2.1",
      "deep",
      "",
      "## A.1",
      "one",
      "",
      "## A.3",
      "three",
      "",
      "# B",
      "b text",
    },
    { 5, 1 },
  },
  { "no move past the last sibling", DOC, { 13, 0 }, " m#j", DOC },
  { "no move past the first sibling", DOC, { 4, 0 }, " m#k", DOC },
  {
    "count",
    DOC,
    { 4, 0 },
    "2 m#j",
    {
      "# A",
      "a text",
      "",
      "## A.2",
      "two",
      "",
      "### A.2.1",
      "deep",
      "",
      "## A.3",
      "three",
      "",
      "## A.1",
      "one",
      "",
      "# B",
      "b text",
    },
  },
  {
    "top-level sections, last one without a trailing blank line",
    { "# A", "a", "", "# B", "b" },
    { 1, 0 },
    " m#j",
    { "# B", "b", "", "# A", "a" },
  },
  {
    "definitions at the end of the file stay there",
    { "# A", "a[^1]", "", "# B", "b", "", "[^1]: note", "[r]: http://x.io" },
    { 4, 0 },
    " m#k",
    { "# B", "b", "", "# A", "a[^1]", "", "[^1]: note", "[r]: http://x.io" },
  },
  {
    "headings in code blocks don't count",
    { "# A", "```", "# not", "```", "", "# B", "b" },
    { 1, 0 },
    " m#j",
    { "# B", "b", "", "# A", "```", "# not", "```" },
  },
  { "move is one undo step", { "# A", "", "# B" }, { 1, 0 }, { " m#j", "u" }, { "# A", "", "# B" } },
  {
    "move repeats with .",
    { "# A", "", "# B", "", "# C" },
    { 1, 0 },
    { " m#j", "." },
    { "# B", "", "# C", "", "# A" },
  },
  { "before the first heading: nothing", { "intro", "# A" }, { 1, 0 }, " m#j", { "intro", "# A" } },
  -- promote / demote
  {
    "add # to the section and its sub-headings",
    DOC,
    { 7, 0 },
    " m#=",
    {
      "# A",
      "a text",
      "",
      "## A.1",
      "one",
      "",
      "### A.2",
      "two",
      "",
      "#### A.2.1",
      "deep",
      "",
      "## A.3",
      "three",
      "",
      "# B",
      "b text",
    },
  },
  {
    "remove # with a count",
    { "### A", "#### B", "x" },
    { 1, 0 },
    "2 m#-",
    { "# A", "## B", "x" },
  },
  { "a level-1 heading isn't promoted", { "# A", "## B" }, { 1, 0 }, " m#-", { "# A", "## B" } },
  { "nothing goes past level 6", { "##### A", "###### B" }, { 1, 0 }, " m#=", { "##### A", "###### B" } },
  {
    "setext headings are converted",
    { "A", "===", "", "B", "---" },
    { 1, 0 },
    " m#=",
    { "## A", "", "### B" },
  },
  { "promote is one undo step", { "## A", "### B" }, { 1, 0 }, { " m#-", "u" }, { "## A", "### B" } },
  -- move keys and commands
  {
    "lists.move_keys move sections on a heading line",
    fn = function()
      config.options.lists.move_keys = { down = "<M-j>", up = "<M-k>" }
      H.buf({ "# A", "", "# B" }, { 1, 0 })
      config.options.lists.move_keys = nil
      H.feed("<M-j>")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "# B", "", "# A" })
    end,
  },
  {
    ":Markwright section",
    fn = function()
      H.buf({ "# A", "", "# B", "## C" }, { 1, 0 })
      vim.cmd("Markwright section down")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "# B", "## C", "", "# A" })
      vim.cmd("Markwright section add 2")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "# B", "## C", "", "### A" })
      eq(vim.fn.getcompletion("Markwright section ", "cmdline"), { "add", "down", "remove", "up" })
    end,
  },
}

return H.run("sections", cases)
