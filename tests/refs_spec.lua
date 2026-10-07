-- Inline ↔ reference link specs (SPEC.md section 14.17).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local eq = H.eq

local cases = {
  -- inline → reference
  {
    "inline → reference, label from the text, definition at the end",
    { "See [Neovim docs](https://neovim.io) now." },
    { 1, 6 },
    " mr",
    { "See [Neovim docs][neovim-docs] now.", "", "[neovim-docs]: https://neovim.io" },
    { 1, 4 },
  },
  {
    "title kept on the definition",
    { 'a [x](http://u "The T") b' },
    { 1, 3 },
    " mr",
    { "a [x][x] b", "", '[x]: http://u "The T"' },
  },
  {
    "after existing definitions",
    { "[a](http://a) and [b][b]", "", "[b]: http://b", "", "[^1]: note" },
    { 1, 1 },
    " mr",
    { "[a][a] and [b][b]", "", "[b]: http://b", "[a]: http://a", "", "[^1]: note" },
  },
  {
    "the same URL reuses its label",
    { "[one](http://u) and [two](http://u)", "", "[docs]: http://u" },
    { 1, 1 },
    " mr",
    { "[one][docs] and [two](http://u)", "", "[docs]: http://u" },
  },
  {
    "a taken label gets a suffix",
    { "[docs](http://new)", "", "[docs]: http://old" },
    { 1, 1 },
    " mr",
    { "[docs][docs-2]", "", "[docs]: http://old", "[docs-2]: http://new" },
  },
  {
    "images too",
    { "![A logo](logo.png)" },
    { 1, 2 },
    " mr",
    { "![A logo][a-logo]", "", "[a-logo]: logo.png" },
  },
  -- reference → inline
  {
    "reference → inline, unused definition removed",
    { "See [docs][d] now.", "", "[d]: http://d.io" },
    { 1, 5 },
    " mr",
    { "See [docs](http://d.io) now." },
  },
  {
    "a definition still in use stays",
    { "[a][d] and [b][d]", "", "[d]: http://d" },
    { 1, 1 },
    " mr",
    { "[a](http://d) and [b][d]", "", "[d]: http://d" },
  },
  {
    "collapsed and shortcut references, title back inline",
    { "[d][] and [d]", "", '[d]: <http://d x> "T"' },
    { 1, 1 },
    { " mr", "f[ mr" },
    { '[d](<http://d x> "T") and [d](<http://d x> "T")' },
  },
  { "a [shortcut] without a definition isn't a link", { "a [x] b" }, { 1, 3 }, " mr", { "a [x] b" } },
  { "not on a link", { "plain" }, { 1, 0 }, " mr", { "plain" } },
  {
    "one undo step",
    { "[a](http://a)" },
    { 1, 1 },
    { " mr", "u" },
    { "[a](http://a)" },
  },
  {
    "repeat with .",
    { "[a](http://a) [b](http://b)" },
    { 1, 1 },
    { " mr", "f[f[." },
    { "[a][a] [b][b]", "", "[a]: http://a", "[b]: http://b" },
  },
  -- visual and commands
  {
    "visual: every inline link in the selection",
    { "[a](http://a)", "[b](http://b)", "[c](http://c)" },
    { 1, 0 },
    "Vj mr",
    { "[a][a]", "[b][b]", "[c](http://c)", "", "[a]: http://a", "[b]: http://b" },
  },
  {
    "visual: no inline links → references become inline",
    { "[a][a] [b][b]", "", "[a]: http://a", "[b]: http://b" },
    { 1, 0 },
    "V mr",
    { "[a](http://a) [b](http://b)" },
  },
  {
    ":Markwright links reference / inline (whole buffer)",
    fn = function()
      H.buf({ "[a](http://a) and [b](http://b)", "", "`[c](http://c)`" }, { 1, 0 })
      vim.cmd("Markwright links reference")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), {
        "[a][a] and [b][b]",
        "",
        "`[c](http://c)`",
        "",
        "[a]: http://a",
        "[b]: http://b",
      })
      vim.cmd("Markwright links inline")
      eq(api.nvim_buf_get_lines(0, 0, -1, false), { "[a](http://a) and [b](http://b)", "", "`[c](http://c)`" })
      eq(vim.fn.getcompletion("Markwright links ", "cmdline"), { "inline", "reference" })
    end,
  },
}

return H.run("inline ↔ reference links", cases)
