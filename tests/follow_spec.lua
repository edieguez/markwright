-- gx / slug specs (SPEC.md section 8). The system opener is mocked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local follow = require("markwright.follow")
local slug = require("markwright.slug")
local eq = H.eq

local opened
local function before_each()
  opened = {}
  follow.open = function(target)
    table.insert(opened, target)
  end
end

local function row()
  return api.nvim_win_get_cursor(0)[1]
end

local dir = H.tmpdir({
  ["b.md"] = { "# B", "", "text", "## Part Two", "more" },
  ["note.md"] = { "# Note" },
  ["my file.md"] = { "# Spaced" },
  ["img.png"] = { "fake" },
})
local main = dir .. "/main.md"

local cases = {
  -- slugs
  { "slug basics", fn = function()
    eq(slug.slug("Hello, World!"), "hello-world")
    eq(slug.slug("Café `code` **bold** [link](x)"), "café-code-bold-link")
    eq(slug.slug("snake_case and _em_"), "snake_case-and-em")
    eq(slug.slug("A.1 — intro"), "a1--intro")
    eq(slug.slug("  Trim  me "), "trim--me")
  end },
  { "slug unique", fn = function()
    eq(slug.unique({ "x", "x", "y", "x", "x-1" }), { "x", "x-1", "y", "x-2", "x-1-1" })
  end },

  -- anchors in the same file
  { "anchor jump", fn = function()
    H.buf({ "[go](#second-heading)", "", "# First", "## Second Heading" }, { 1, 2 })
    H.feed("gx")
    eq(row(), 4)
  end },
  { "anchor from the destination part", fn = function()
    H.buf({ "[go](#first)", "# First" }, { 1, 8 })
    H.feed("gx")
    eq(row(), 2)
  end },
  { "duplicate + accented headings", fn = function()
    H.buf({ "[x](#café-olé-1)", "## Café Olé!", "text", "## Café Olé!" }, { 1, 1 })
    H.feed("gx")
    eq(row(), 4)
  end },
  { "headings in code blocks ignored", fn = function()
    H.buf({ "[x](#real)", "```", "# Real", "```", "# Real" }, { 1, 1 })
    H.feed("gx")
    eq(row(), 5)
  end },
  { "<C-o> returns after an anchor jump", fn = function()
    H.buf({ "[go](#end)", "a", "b", "# End" }, { 1, 1 })
    H.feed({ "gx", "<C-o>" })
    eq(row(), 1)
  end },
  { "missing anchor stays put", fn = function()
    H.buf({ "[go](#nope)", "# Yes" }, { 1, 1 })
    H.feed("gx")
    eq(row(), 1)
  end },

  -- URLs and schemes
  { "inline link URL", fn = function()
    H.buf({ "see [site](https://x.io/a) ok" }, { 1, 6 })
    H.feed("gx")
    eq(opened, { "https://x.io/a" })
  end },
  { "bare URL", fn = function()
    H.buf({ "go https://x.io/b." }, { 1, 8 })
    H.feed("gx")
    eq(opened, { "https://x.io/b" })
  end },
  { "www gets https", fn = function()
    H.buf({ "www.x.io" }, { 1, 1 })
    H.feed("gx")
    eq(opened, { "https://www.x.io" })
  end },
  { "autolinks", fn = function()
    H.buf({ "<http://y.io> <me@x.io>" }, { 1, 3 })
    H.feed("gx")
    api.nvim_win_set_cursor(0, { 1, 17 })
    H.feed("gx")
    eq(opened, { "http://y.io", "mailto:me@x.io" })
  end },
  { "reference link resolves definition", fn = function()
    H.buf({ "[t][Ref One]", "", "[ref one]: https://r.io" }, { 1, 1 })
    H.feed("gx")
    eq(opened, { "https://r.io" })
  end },
  { "collapsed reference", fn = function()
    H.buf({ "[docs][]", "", "[docs]: <https://d.io>" }, { 1, 1 })
    H.feed("gx")
    eq(opened, { "https://d.io" })
  end },
  { "definition line", fn = function()
    H.buf({ "[docs]: https://d.io" }, { 1, 2 })
    H.feed("gx")
    eq(opened, { "https://d.io" })
  end },
  { "undefined reference does nothing", fn = function()
    H.buf({ "[t][nope]" }, { 1, 1 })
    H.feed("gx")
    eq(opened, {})
  end },
  { "other schemes go to the opener", fn = function()
    H.buf({ "[z](zotero://select/1)" }, { 1, 1 })
    H.feed("gx")
    eq(opened, { "zotero://select/1" })
  end },
  { "not a link: default gx on <cfile>", fn = function()
    H.buf({ "open some/path.txt now" }, { 1, 8 })
    H.feed("gx")
    eq(opened, { "some/path.txt" })
  end },

  -- footnotes
  { "footnote ref → definition", fn = function()
    H.buf({ "Text[^n1] more.", "", "[^n1]: The note" }, { 1, 5 })
    H.feed("gx")
    eq(api.nvim_win_get_cursor(0), { 3, 0 })
  end },
  { "footnote definition → reference", fn = function()
    H.buf({ "a", "Text[^n1] more.", "", "[^n1]: The note" }, { 4, 2 })
    H.feed("gx")
    eq(api.nvim_win_get_cursor(0), { 2, 4 })
  end },
  { "footnote round trip with <C-o>", fn = function()
    H.buf({ "Text[^1].", "", "[^1]: x" }, { 1, 5 })
    H.feed({ "gx", "<C-o>" })
    eq(row(), 1)
  end },

  -- local files
  { "open existing md", fn = function()
    H.buf({ "[b](b.md)" }, { 1, 1 }, main)
    H.feed("gx")
    eq(api.nvim_buf_get_name(0), dir .. "/b.md")
  end },
  { "open md at anchor", fn = function()
    H.buf({ "[b](./b.md#part-two)" }, { 1, 1 }, main)
    H.feed("gx")
    eq(api.nvim_buf_get_name(0), dir .. "/b.md")
    eq(row(), 4)
  end },
  { "extensionless → .md", fn = function()
    H.buf({ "[n](note)" }, { 1, 1 }, main)
    H.feed("gx")
    eq(api.nvim_buf_get_name(0), dir .. "/note.md")
  end },
  { "url-encoded path", fn = function()
    H.buf({ "[s](my%20file.md)" }, { 1, 1 }, main)
    H.feed("gx")
    eq(api.nvim_buf_get_name(0), dir .. "/my file.md")
  end },
  { "<C-o> returns from another file", fn = function()
    H.buf({ "[b](b.md)" }, { 1, 1 }, main)
    H.feed({ "gx", "<C-o>" })
    eq(api.nvim_buf_get_name(0), main)
  end },
  { "missing md opens new buffer, dirs made on write", fn = function()
    H.buf({ "[n](sub/dir/new.md)" }, { 1, 1 }, main)
    H.feed("gx")
    local path = dir .. "/sub/dir/new.md"
    eq(api.nvim_buf_get_name(0), path)
    eq(vim.fn.filereadable(path), 0)
    vim.cmd("silent write")
    eq(vim.fn.filereadable(path), 1)
  end },
  { "image goes to the opener", fn = function()
    H.buf({ "![pic](img.png)" }, { 1, 3 }, main)
    H.feed("gx")
    eq(opened, { dir .. "/img.png" })
  end },
  { "missing image: nothing opened", fn = function()
    H.buf({ "![pic](gone.png)" }, { 1, 3 }, main)
    H.feed("gx")
    eq(opened, {})
    eq(api.nvim_buf_get_name(0), main)
  end },
  { "missing non-md file: stay", fn = function()
    H.buf({ "[x](missing.txt)" }, { 1, 1 }, main)
    H.feed("gx")
    eq(api.nvim_buf_get_name(0), main)
  end },
}

return H.run("follow", cases, { before_each = before_each })
