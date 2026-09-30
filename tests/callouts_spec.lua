-- GitHub callout specs (SPEC.md section 14.11). The type picker is mocked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local config = require("markwright.config")
local eq = H.eq

local real_select = vim.ui.select
local pick -- what the mocked picker answers (nil = cancel)
local asked
local function before_each()
  pick, asked = "NOTE", 0
  config.options.callouts.default = nil
  vim.ui.select = function(items, _, cb)
    asked = asked + 1
    eq(items[1], "NOTE")
    cb(pick)
  end
end

local function choose(t)
  return function()
    pick = t
  end
end

local cases = {
  -- wrapping
  {
    "wrap the paragraph",
    { "intro", "", "line one", "line two", "", "after" },
    { 3, 2 },
    " ma",
    { "intro", "", "> [!NOTE]", "> line one", "> line two", "", "after" },
    { 4, 2 },
  },
  { "picked type", { "careful" }, { 1, 0 }, " ma", { "> [!WARNING]", "> careful" }, setup = choose("WARNING") },
  { "picker cancelled", { "text" }, { 1, 0 }, " ma", { "text" }, setup = choose(nil) },
  {
    "visual selection with a blank line",
    { "a", "", "b", "c" },
    { 1, 0 },
    "Vjj ma",
    { "> [!TIP]", "> a", ">", "> b", "c" },
    setup = choose("TIP"),
  },
  {
    "wrap a whole code block",
    { "```lua", "", "x = 1", "```" },
    { 3, 0 },
    " ma",
    { "> [!NOTE]", "> ```lua", ">", "> x = 1", "> ```" },
  },
  { "wrap a list", { "- a", "  - b" }, { 2, 4 }, " ma", { "> [!NOTE]", "> - a", ">   - b" } },
  {
    "indented paragraph keeps its indent",
    { "- item", "", "  para", "  more" },
    { 3, 2 },
    " ma",
    { "- item", "", "  > [!NOTE]", "  > para", "  > more" },
  },
  { "empty line: empty callout, insert mode", { "" }, { 1, 0 }, " matyped<Esc>", { "> [!NOTE]", "> typed" } },
  { "one undo step", { "text" }, { 1, 0 }, { " ma", "u" }, { "text" } },

  -- changing the type
  {
    "change the type",
    { "> [!NOTE]", "> text" },
    { 2, 3 },
    " ma",
    { "> [!WARNING]", "> text" },
    setup = choose("WARNING"),
  },
  {
    "lowercase type is recognized",
    { "> [!warning]", "> x" },
    { 2, 0 },
    " ma",
    { "> [!TIP]", "> x" },
    setup = choose("TIP"),
  },
  {
    "changing keeps a title after the marker",
    { "> [!NOTE] Heads up", "> x" },
    { 1, 0 },
    " ma",
    { "> [!CAUTION] Heads up", "> x" },
    setup = choose("CAUTION"),
  },
  { "change cancelled", { "> [!NOTE]", "> x" }, { 2, 0 }, " ma", { "> [!NOTE]", "> x" }, setup = choose(nil) },
  {
    "the picker marks the current type",
    fn = function()
      local labels
      vim.ui.select = function(items, o, cb)
        labels = vim.tbl_map(o.format_item, items)
        cb(nil)
      end
      H.buf({ "> [!IMPORTANT]", "> x" }, { 2, 0 })
      H.feed(" ma")
      eq(labels, { "NOTE", "TIP", "IMPORTANT  (current)", "WARNING", "CAUTION" })
    end,
  },
  {
    "changing asks even with a default type",
    fn = function()
      config.options.callouts.default = "NOTE"
      pick = "TIP"
      H.buf({ "> [!NOTE]", "> x" }, { 2, 0 })
      H.feed(" ma")
      eq(asked, 1)
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "> [!TIP]", "> x" })
    end,
  },
  {
    "plain blockquote becomes a callout",
    { "> quoted", "> text" },
    { 2, 0 },
    " ma",
    { "> [!IMPORTANT]", "> quoted", "> text" },
    setup = choose("IMPORTANT"),
  },
  {
    "blockquote inside a code block is left alone",
    { "```", "> not a quote", "```" },
    { 2, 0 },
    " ma",
    { "> [!NOTE]", "> ```", "> > not a quote", "> ```" },
  },

  -- removing
  {
    "remove a callout",
    { "a", "> [!NOTE]", "> one", ">", "> two", "b" },
    { 3, 2 },
    " mA",
    { "a", "one", "", "two", "b" },
  },
  { "remove keeps a title as text", { "> [!TIP] Title", "> body" }, { 2, 0 }, " mA", { "Title", "body" } },
  { "remove a plain blockquote", { "> a", "> > nested" }, { 1, 0 }, " mA", { "a", "> nested" } },
  { "remove outside a callout does nothing", { "text" }, { 1, 0 }, " mA", { "text" } },
  { "remove then undo", { "> [!NOTE]", "> x" }, { 2, 0 }, { " mA", "u" }, { "> [!NOTE]", "> x" } },

  -- continuing quotes and callouts
  {
    "<CR> after the marker continues the callout",
    { "> [!NOTE]" },
    { 1, 0 },
    "A<CR>text<Esc>",
    { "> [!NOTE]", "> text" },
  },
  {
    "<CR> on a content line continues",
    { "> [!NOTE]", "> one" },
    { 2, 0 },
    "A<CR>two<Esc>",
    { "> [!NOTE]", "> one", "> two" },
  },
  {
    "<CR> on an empty > line ends the quote",
    { "> [!NOTE]", "> one", "> " },
    { 3, 0 },
    "A<CR>after<Esc>",
    { "> [!NOTE]", "> one", "after" },
  },
  {
    "Enter twice leaves the callout",
    { "> [!TIP]", "> one" },
    { 2, 0 },
    "A<CR><CR>plain<Esc>",
    { "> [!TIP]", "> one", "plain" },
  },
  { "bare > counts as empty", { "> a", ">" }, { 2, 0 }, "A<CR>x<Esc>", { "> a", "x" } },
  { "plain blockquotes continue too", { "> quoted" }, { 1, 0 }, "A<CR>more<Esc>", { "> quoted", "> more" } },
  { "nested quote keeps its level", { "> > deep" }, { 1, 0 }, "A<CR>x<Esc>", { "> > deep", "> > x" } },
  { "empty nested line drops one level", { "> > deep", "> > " }, { 2, 0 }, "A<CR>x<Esc>", { "> > deep", "> x" } },
  { "split in the middle", { "> hello world" }, { 1, 7 }, "i<CR><Esc>", { "> hello", "> world" } },
  { "indented quote", { "- item", "  > quote" }, { 2, 0 }, "A<CR>x<Esc>", { "- item", "  > quote", "  > x" } },
  { "list inside a quote still continues as a list", { "> - a" }, { 1, 0 }, "A<CR>b<Esc>", { "> - a", "> - b" } },
  {
    "code inside a callout keeps the >",
    { "> [!NOTE]", "> ```", "> x = 1" },
    { 3, 0 },
    "A<CR>y<Esc>",
    { "> [!NOTE]", "> ```", "> x = 1", "> y" },
  },
  {
    "> in a normal code block is not a quote",
    { "```", "> prompt" },
    { 2, 0 },
    "A<CR>x<Esc>",
    { "```", "> prompt", "x" },
  },
  { "o continues the quote", { "> [!NOTE]", "> one" }, { 2, 0 }, "otwo<Esc>", { "> [!NOTE]", "> one", "> two" } },
  { "O continues the quote above", { "> [!NOTE]", "> two" }, { 2, 0 }, "Oone<Esc>", { "> [!NOTE]", "> one", "> two" } },
  { "<CR> outside quotes is unchanged", { "text" }, { 1, 0 }, "A<CR>x<Esc>", { "text", "x" } },
  {
    "can be turned off",
    fn = function()
      config.options.blockquotes.continue_on_enter = false
      H.buf({ "> quoted" }, { 1, 0 })
      H.feed("A<CR>x<Esc>")
      config.options.blockquotes.continue_on_enter = true
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "> quoted", "x" })
    end,
  },

  -- commands and config
  {
    ":Markwright callout warning",
    { "text" },
    { 1, 0 },
    ":Markwright callout warning<CR>",
    { "> [!WARNING]", "> text" },
  },
  {
    ":Markwright callout sets the type directly",
    { "> [!NOTE]", "> x" },
    { 1, 0 },
    ":Markwright callout caution<CR>",
    { "> [!CAUTION]", "> x" },
  },
  {
    ":'<,'>Markwright callout tip",
    { "a", "b", "c" },
    { 1, 0 },
    ":1,2Markwright callout tip<CR>",
    { "> [!TIP]", "> a", "> b", "c" },
  },
  { ":Markwright callout remove", { "> [!NOTE]", "> x" }, { 2, 0 }, ":Markwright callout remove<CR>", { "x" } },
  { "unknown type", { "text" }, { 1, 0 }, ":Markwright callout nope<CR>", { "text" } },
  {
    "default type skips the picker",
    fn = function()
      config.options.callouts.default = "tip"
      H.buf({ "text" }, { 1, 0 })
      H.feed(" ma")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "> [!TIP]", "> text" })
      eq(asked, 0)
    end,
  },
  {
    "completion",
    fn = function()
      H.buf({ "x" })
      eq(vim.fn.getcompletion("Markwright callout w", "cmdline"), { "warning" })
      eq(#vim.fn.getcompletion("Markwright callout ", "cmdline"), 6)
    end,
  },
}

local failed, total = H.run("callouts", cases, { before_each = before_each })
vim.ui.select = real_select
config.options.callouts.default = nil
return failed, total
