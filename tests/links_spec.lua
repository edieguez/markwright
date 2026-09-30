-- Links specs (SPEC.md section 7). Clipboard, prompts and title fetching are mocked.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local links = require("markwright.links")
local title = require("markwright.title")

local mock = {}
local real_input = vim.ui.input

local function before_each()
  mock.clipboard = ""
  mock.inputs = {}
  mock.title = "Title"
  links.read_clipboard = function()
    return mock.clipboard
  end
  title.fetch = function(_, cb)
    cb(mock.title)
  end
  vim.ui.input = function(_, cb)
    cb(table.remove(mock.inputs, 1))
  end
  vim.fn.setreg('"', "")
end

local function clip(url)
  return function()
    mock.clipboard = url
  end
end
local function inputs(...)
  local list = { ... }
  return function()
    mock.inputs = list
  end
end
local function title_is(t)
  return function()
    mock.title = t
  end
end
local function reg(name, value, typ)
  return function()
    vim.fn.setreg(name, value, typ or "v")
  end
end

local function eq(a, b)
  if not vim.deep_equal(a, b) then
    error(("expected %s, got %s"):format(vim.inspect(b), vim.inspect(a)), 2)
  end
end

local cases = {
  -- unit: URL helpers and title parsing
  {
    "is_url",
    fn = function()
      eq(links.is_url("https://example.com/a?b=1"), true)
      eq(links.is_url("www.example.com"), true)
      eq(links.is_url("mailto:me@x.io"), true)
      eq(links.is_url("<https://x.io>"), true)
      eq(links.is_url("example.com"), false)
      eq(links.is_url("two words"), false)
      eq(links.is_url("https://"), false)
    end,
  },
  {
    "url_at trims sentence punctuation",
    fn = function()
      local line = "see https://ex.com/a, and (https://en.wikipedia.org/wiki/Foo_(bar)). www.x.io."
      eq({ links.url_at(line, 6) }, { 4, 20, "https://ex.com/a" })
      eq({ links.url_at(line, 30) }, { 27, 66, "https://en.wikipedia.org/wiki/Foo_(bar)" })
      eq({ links.url_at(line, 72) }, { 69, 77, "www.x.io" })
      eq(links.url_at(line, 0), nil)
    end,
  },
  {
    "domain / normalize",
    fn = function()
      eq(links.domain("https://www.github.com/x"), "github.com")
      eq(links.domain("mailto:me@x.io"), "me@x.io")
      eq(links.normalize("www.x.io"), "https://www.x.io")
      eq(links.normalize(" <https://x.io> "), "https://x.io")
    end,
  },
  {
    "title parse: <title> with entities",
    fn = function()
      eq(title.parse("<html><head><TITLE lang=en>\n  Tom &amp; Jerry &#8212; &#x41;  </TITLE>"), "Tom & Jerry — A")
    end,
  },
  {
    "title parse: og:title fallback",
    fn = function()
      eq(
        title.parse([[<head><title> </title><meta property="og:title" content="Café &quot;Olé&quot;"></head>]]),
        'Café "Olé"'
      )
      eq(title.parse([[<meta content="Rev order" property='og:title'>]]), "Rev order")
      eq(title.parse("<p>no title</p>"), nil)
    end,
  },

  -- link key on a word / selection
  {
    "word + clipboard URL",
    { "see docs here" },
    { 1, 5 },
    " mk",
    { "see [docs](https://ex.com/docs) here" },
    { 1, 4 },
    setup = clip("https://ex.com/docs\n"),
  },
  {
    "visual + clipboard URL",
    { "read the manual now" },
    { 1, 5 },
    "v9l mk",
    { "read [the manual](https://m.io) now" },
    setup = clip("https://m.io"),
  },
  {
    "visual keeps edge spaces outside",
    { "read the manual now" },
    { 1, 4 },
    "v11l mk",
    { "read [the manual](https://m.io) now" },
    setup = clip("https://m.io"),
  },
  {
    "no clipboard URL → prompt",
    { "word" },
    { 1, 0 },
    " mk",
    { "[word](https://p.io)" },
    setup = inputs("https://p.io"),
  },
  {
    "prompt accepts relative paths",
    { "notes" },
    { 1, 0 },
    " mk",
    { "[notes](./notes.md)" },
    setup = inputs("./notes.md"),
  },
  { "prompt cancelled", { "word" }, { 1, 0 }, " mk", { "word" }, setup = inputs(nil) },
  {
    "www clipboard gets https",
    { "site" },
    { 1, 0 },
    " mk",
    { "[site](https://www.x.io)" },
    setup = clip("www.x.io"),
  },
  {
    "linewise selection skips list marker",
    { "- item text" },
    { 1, 0 },
    "V mk",
    { "- [item text](https://l.io)" },
    setup = clip("https://l.io"),
  },
  {
    "link inside bold",
    { "**word**" },
    { 1, 3 },
    " mk",
    { "**[word](https://b.io)**" },
    setup = clip("https://b.io"),
  },

  -- bare URLs → titled links
  {
    "bare URL → page title",
    { "go https://example.com/a now" },
    { 1, 10 },
    " mk",
    { "go [Example A](https://example.com/a) now" },
    setup = title_is("Example A"),
  },
  {
    "title fetch fails → domain",
    { "go https://www.example.com/a now" },
    { 1, 10 },
    " mk",
    { "go [example.com](https://www.example.com/a) now" },
    setup = title_is(nil),
  },
  { "trailing period stays outside", { "see https://ex.com." }, { 1, 6 }, " mk", { "see [Title](https://ex.com)." } },
  { "www URL", { "www.ex.com" }, { 1, 2 }, " mk", { "[Title](https://www.ex.com)" } },
  {
    "title brackets escaped",
    { "https://x.io" },
    { 1, 0 },
    " mk",
    { [[[A \[b\] c](https://x.io)]] },
    setup = title_is("A [b] c"),
  },
  { "selected URL → titled", { "a https://x.io b" }, { 1, 2 }, "vt  mk", { "a [Title](https://x.io) b" } },
  { "mailto keeps address as text", { "mailto:me@x.io" }, { 1, 3 }, " mk", { "[me@x.io](mailto:me@x.io)" } },

  -- removing links
  { "unlink inline link", { "a [text *em*](http://x.io) b" }, { 1, 4 }, " mk", { "a text *em* b" }, { 1, 2 } },
  { "unlink from destination", { "a [text](http://x.io) b" }, { 1, 14 }, " mk", { "a text b" } },
  { "unlink reference link", { "[r][ref]", "", "[ref]: http://z" }, { 1, 1 }, " mk", { "r", "", "[ref]: http://z" } },
  { "unlink autolink", { "x <http://y.io> z" }, { 1, 5 }, " mk", { "x http://y.io z" } },
  { "visual over link unlinks", { "a [text](u) b" }, { 1, 3 }, "vll mk", { "a text b" } },
  { "image is left alone", { "![alt](i.png)" }, { 1, 3 }, " mk", { "![alt](i.png)" } },

  -- guards
  { "skip in code span", { "`code`" }, { 1, 2 }, " mk", { "`code`" }, setup = clip("https://x.io") },
  {
    "skip in fenced block",
    { "```", "text", "```" },
    { 2, 0 },
    " mk",
    { "```", "text", "```" },
    setup = clip("https://x.io"),
  },

  -- whitespace: prompt for URL, then text
  { "empty line: URL + text", { "" }, { 1, 0 }, " mk", { "[Q](https://q.io)" }, setup = inputs("https://q.io", "Q") },
  {
    "empty line: empty text → title",
    { "" },
    { 1, 0 },
    " mk",
    { "[Title](https://q.io)" },
    setup = inputs("https://q.io", ""),
  },
  {
    "space before word keeps spacing",
    { "a b" },
    { 1, 1 },
    " mk",
    { "a [Q](https://q.io) b" },
    setup = inputs("https://q.io", "Q"),
  },
  { "cancel text prompt", { "" }, { 1, 0 }, " mk", { "" }, setup = inputs("https://q.io", nil) },

  -- smart paste
  {
    "visual p with URL → link",
    { "click here please" },
    { 1, 6 },
    "viwp",
    { "click [here](https://h.io) please" },
    setup = reg('"', "https://h.io"),
  },
  {
    "visual p with text → native",
    { "click here please" },
    { 1, 6 },
    "viwp",
    { "click there please" },
    setup = reg('"', "there"),
  },
  {
    "visual p on link → native",
    { "a [t](u) b" },
    { 1, 3 },
    "vp",
    { "a [https://h.io](u) b" },
    setup = reg('"', "https://h.io"),
  },
  {
    "normal p with URL → titled link",
    { "see " },
    { 1, 3 },
    "p",
    { "see [Title](https://h.io)" },
    setup = reg('"', "https://h.io"),
  },
  { "normal P with URL", { "x" }, { 1, 0 }, "P", { "[Title](https://h.io)x" }, setup = reg('"', "https://h.io") },
  { "normal p with text → native", { "a" }, { 1, 0 }, "p", { "abc" }, setup = reg('"', "bc") },
  { "p after ( stays native", { "[t](" }, { 1, 3 }, "p", { "[t](https://h.io" }, setup = reg('"', "https://h.io") },
  {
    "linewise URL register → native",
    { "a" },
    { 1, 0 },
    "p",
    { "a", "https://h.io" },
    setup = reg('"', "https://h.io", "l"),
  },
  { "register prefix passes through", { "a" }, { 1, 0 }, '"ap', { "axyz" }, setup = reg("a", "xyz") },
  { "count passes through", { "" }, { 1, 0 }, "3p", { "ababab" }, setup = reg('"', "ab") },
  { "paste URL in code → native", { "`c`" }, { 1, 1 }, "p", { "`chttps://h.io`" }, setup = reg('"', "https://h.io") },

  -- undo
  { "link is one undo step", { "word" }, { 1, 0 }, { " mk", "u" }, { "word" }, setup = clip("https://x.io") },
  { "titled link + title is one undo step", { "https://x.io" }, { 1, 0 }, { " mk", "u" }, { "https://x.io" } },
}

local failed, total = H.run("links", cases, { before_each = before_each })
vim.ui.input = real_input
return failed, total
