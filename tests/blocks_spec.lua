-- Code fence + footnote specs (SPEC.md sections 9.3, 9.5).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local A = H.answers

local cases = {
  -- fences: insert
  {
    "fence on empty line",
    { "" },
    { 1, 0 },
    " mfx = 1<Esc>",
    { "```lua", "x = 1", "```" },
    { 2, 4 },
    setup = A("lua"),
  },
  {
    "fence on a paragraph wraps it",
    { "a", "b", "", "c" },
    { 2, 0 },
    " mf",
    { "```", "a", "b", "```", "", "c" },
    { 1, 0 },
    setup = A(""),
  },
  {
    "fence on an indented empty line (inside a list item)",
    { "- item", "  " },
    { 2, 1 },
    " mfls<Esc>",
    { "- item", "  ```sh", "  ls", "  ```" },
    setup = A(" sh "),
  },
  {
    "fence on an empty quote line",
    { "> quote", ">" },
    { 2, 0 },
    " mfx<Esc>",
    { "> quote", "> ```py", "> x", "> ```" },
    setup = A("py"),
  },
  {
    "wrapping a quoted paragraph keeps the >",
    { "> a", "> b" },
    { 1, 3 },
    " mf",
    { "> ```py", "> a", "> b", "> ```" },
    setup = A("py"),
  },
  {
    "wrapping a paragraph repeats with the same language",
    { "a", "", "b" },
    { 1, 0 },
    { " mf", "4j." },
    { "```lua", "a", "```", "", "```lua", "b", "```" },
    setup = A("lua"),
  },
  { "fence cancelled", { "text" }, { 1, 0 }, " mf", { "text" }, setup = A(nil) },
  { "empty fence cancelled", { "" }, { 1, 0 }, " mf", { "" }, setup = A(nil) },
  {
    "fence skipped inside code block",
    { "```", "x", "```" },
    { 2, 0 },
    " mf",
    { "```", "x", "```" },
    setup = A("lua"),
  },

  -- fences: wrap selection
  { "wrap lines", { "a", "b", "c" }, { 1, 0 }, "Vj mf", { "```go", "a", "b", "```", "c" }, { 1, 0 }, setup = A("go") },
  {
    "wrap keeps shared indent",
    { "  a", "    b" },
    { 1, 0 },
    "Vj mf",
    { "  ```js", "  a", "    b", "  ```" },
    setup = A("js"),
  },
  {
    "wrap escalates fence",
    { "text", "```", "x" },
    { 1, 0 },
    "Vjj mf",
    { "````md", "text", "```", "x", "````" },
    setup = A("md"),
  },
  { "wrap cancelled", { "a" }, { 1, 0 }, "V mf", { "a" }, setup = A(nil) },
  {
    ":Markwright fence with range",
    { "a", "b" },
    { 1, 0 },
    ":1,2Markwright fence<CR>",
    { "```", "a", "b", "```" },
    setup = A(""),
  },

  -- footnotes
  {
    "first footnote",
    { "Text here." },
    { 1, 9 },
    " mnthe note<Esc>",
    { "Text here.[^1]", "", "[^1]: the note" },
    { 3, 13 },
  },
  {
    "joins existing definitions",
    { "A[^1] b", "", "[^1]: one" },
    { 1, 6 },
    " mntwo<Esc>",
    { "A[^1] b[^2]", "", "[^1]: one", "[^2]: two" },
  },
  {
    "named footnotes don't count",
    { "A[^x]", "", "[^x]: n" },
    { 1, 4 },
    " mnm<Esc>",
    { "A[^x][^1]", "", "[^x]: n", "[^1]: m" },
  },
  {
    "numbering uses the max id",
    { "A[^7]", "", "[^7]: n" },
    { 1, 0 },
    " mnm<Esc>",
    { "A[^8][^7]", "", "[^7]: n", "[^8]: m" },
  },
  { "trailing blank lines stay last", { "A", "", "" }, { 1, 0 }, " mnn<Esc>", { "A[^1]", "", "[^1]: n", "", "" } },
  { "empty buffer line", { "" }, { 1, 0 }, " mnn<Esc>", { "[^1]", "", "[^1]: n" } },
  { "<C-o> returns to the reference", { "Text here." }, { 1, 9 }, " mnn<Esc><C-o>", nil, { 1, 13 } },
  { "footnote skipped in code", { "`code`" }, { 1, 2 }, " mn", { "`code`" } },
  { "footnote is one undo step", { "Text" }, { 1, 3 }, { " mnn<Esc>", "u" }, { "Text" } },
}

-- fill in "unchanged" expectations
for _, c in ipairs(cases) do
  if not c.fn and c[5] == nil then
    c[5] = { "Text here.[^1]", "", "[^1]: n" }
  end
end

local function renumber(before, after)
  return function()
    H.buf(before, { 1, 0 })
    vim.cmd("Markwright footnote renumber")
    H.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), after)
  end
end

vim.list_extend(cases, {
  {
    "renumber by first reference, definitions reordered",
    fn = renumber(
      { "b[^2] then a[^1] and b[^2] again", "", "[^1]: one", "[^2]: two" },
      { "b[^1] then a[^2] and b[^1] again", "", "[^1]: two", "[^2]: one" }
    ),
  },
  {
    "multi-line definitions move whole, blank lines between them stay",
    fn = renumber(
      { "x[^3] y[^1]", "", "[^1]: one", "    more one", "", "[^3]: three" },
      { "x[^1] y[^2]", "", "[^1]: three", "", "[^2]: one", "    more one" }
    ),
  },
  {
    "named footnotes keep their name and place",
    fn = renumber(
      { "a[^note] b[^5]", "", "[^note]: n", "[^5]: five" },
      { "a[^note] b[^1]", "", "[^note]: n", "[^1]: five" }
    ),
  },
  {
    "unreferenced definitions go after the referenced ones",
    fn = renumber({ "a[^7]", "", "[^2]: orphan", "[^7]: seven" }, { "a[^1]", "", "[^1]: seven", "[^2]: orphan" }),
  },
  {
    "a definition elsewhere is relabeled in place",
    fn = renumber(
      { "p[^9]", "", "[^9]: by the paragraph", "", "Text", "q[^4]", "", "[^4]: later" },
      { "p[^1]", "", "[^1]: by the paragraph", "", "Text", "q[^2]", "", "[^2]: later" }
    ),
  },
  {
    "references in code are left alone",
    fn = renumber({ "`x[^1]` a[^2]", "", "[^2]: two" }, { "`x[^1]` a[^1]", "", "[^1]: two" }),
  },
  {
    "already in order: nothing changes",
    fn = function()
      H.buf({ "a[^1]", "", "[^1]: one" }, { 1, 0 })
      local tick = vim.api.nvim_buf_get_changedtick(0)
      vim.cmd("Markwright footnote renumber")
      H.eq(vim.api.nvim_buf_get_changedtick(0), tick)
    end,
  },
  {
    "renumbering is one undo step",
    fn = function()
      H.buf({ "a[^2] b[^1]", "", "[^1]: one", "[^2]: two" }, { 1, 0 })
      vim.cmd("Markwright footnote renumber")
      vim.cmd("undo")
      H.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "a[^2] b[^1]", "", "[^1]: one", "[^2]: two" })
      H.eq(vim.fn.getcompletion("Markwright footnote ", "cmdline"), { "renumber" })
    end,
  },
})

H.mock_input()
local failed, total = H.run("fence + footnotes", cases, { before_each = A() })
H.restore_input()
return failed, total
