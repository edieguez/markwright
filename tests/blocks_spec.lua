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
  { "fence below text, no language", { "text" }, { 1, 0 }, " mfa<Esc>", { "text", "```", "a", "```" }, setup = A("") },
  {
    "fence inside list item",
    { "- item" },
    { 1, 3 },
    " mfls<Esc>",
    { "- item", "  ```sh", "  ls", "  ```" },
    setup = A(" sh "),
  },
  {
    "fence inside blockquote",
    { "> quote" },
    { 1, 3 },
    " mfx<Esc>",
    { "> quote", "> ```py", "> x", "> ```" },
    setup = A("py"),
  },
  { "fence cancelled", { "text" }, { 1, 0 }, " mf", { "text" }, setup = A(nil) },
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

H.mock_input()
local failed, total = H.run("fence + footnotes", cases, { before_each = A() })
H.restore_input()
return failed, total
