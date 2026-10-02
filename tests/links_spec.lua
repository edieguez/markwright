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
  vim.ui.input = function(o, cb)
    local answer = table.remove(mock.inputs, 1)
    if answer == "<Enter>" then -- accept the prefilled default
      answer = o.default or ""
    end
    cb(answer)
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
    ":Markwright link\r",
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
    ":Markwright link\r",
    { "[word](https://p.io)" },
    setup = inputs("https://p.io"),
  },
  {
    "prompt accepts relative paths",
    { "notes" },
    { 1, 0 },
    ":Markwright link\r",
    { "[notes](./notes.md)" },
    setup = inputs("./notes.md"),
  },
  { "prompt cancelled", { "word" }, { 1, 0 }, ":Markwright link\r", { "word" }, setup = inputs(nil) },
  {
    "www clipboard gets https",
    { "site" },
    { 1, 0 },
    ":Markwright link\r",
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
    ":Markwright link\r",
    { "**[word](https://b.io)**" },
    setup = clip("https://b.io"),
  },

  -- bare URLs → titled links
  {
    "bare URL → page title",
    { "go https://example.com/a now" },
    { 1, 10 },
    ":Markwright link\r",
    { "go [Example A](https://example.com/a) now" },
    setup = title_is("Example A"),
  },
  {
    "title fetch fails → domain",
    { "go https://www.example.com/a now" },
    { 1, 10 },
    ":Markwright link\r",
    { "go [example.com](https://www.example.com/a) now" },
    setup = title_is(nil),
  },
  {
    "trailing period stays outside",
    { "see https://ex.com." },
    { 1, 6 },
    ":Markwright link\r",
    { "see [Title](https://ex.com)." },
  },
  { "www URL", { "www.ex.com" }, { 1, 2 }, ":Markwright link\r", { "[Title](https://www.ex.com)" } },
  {
    "title brackets escaped",
    { "https://x.io" },
    { 1, 0 },
    ":Markwright link\r",
    { [[[A \[b\] c](https://x.io)]] },
    setup = title_is("A [b] c"),
  },
  { "selected URL → titled", { "a https://x.io b" }, { 1, 2 }, "vt  mk", { "a [Title](https://x.io) b" } },
  {
    "mailto keeps address as text",
    { "mailto:me@x.io" },
    { 1, 3 },
    ":Markwright link\r",
    { "[me@x.io](mailto:me@x.io)" },
  },

  -- removing links
  {
    "unlink inline link",
    { "a [text *em*](http://x.io) b" },
    { 1, 4 },
    ":Markwright link\r",
    { "a text *em* b" },
    { 1, 2 },
  },
  { "unlink from destination", { "a [text](http://x.io) b" }, { 1, 14 }, ":Markwright link\r", { "a text b" } },
  {
    "unlink reference link",
    { "[r][ref]", "", "[ref]: http://z" },
    { 1, 1 },
    ":Markwright link\r",
    { "r", "", "[ref]: http://z" },
  },
  { "unlink autolink", { "x <http://y.io> z" }, { 1, 5 }, ":Markwright link\r", { "x http://y.io z" } },
  { "visual over link unlinks", { "a [text](u) b" }, { 1, 3 }, "vll mk", { "a text b" } },
  { "image is left alone", { "![alt](i.png)" }, { 1, 3 }, ":Markwright link\r", { "![alt](i.png)" } },

  -- guards
  { "skip in code span", { "`code`" }, { 1, 2 }, ":Markwright link\r", { "`code`" }, setup = clip("https://x.io") },
  {
    "skip in fenced block",
    { "```", "text", "```" },
    { 2, 0 },
    ":Markwright link\r",
    { "```", "text", "```" },
    setup = clip("https://x.io"),
  },

  -- whitespace: prompt for URL, then text
  {
    "empty line: URL + text",
    { "" },
    { 1, 0 },
    ":Markwright link\r",
    { "[Q](https://q.io)" },
    setup = inputs("https://q.io", "Q"),
  },
  {
    "empty line: empty text → title",
    { "" },
    { 1, 0 },
    ":Markwright link\r",
    { "[Title](https://q.io)" },
    setup = inputs("https://q.io", ""),
  },
  {
    "space before word keeps spacing",
    { "a b" },
    { 1, 1 },
    ":Markwright link\r",
    { "a [Q](https://q.io) b" },
    setup = inputs("https://q.io", "Q"),
  },
  { "cancel text prompt", { "" }, { 1, 0 }, ":Markwright link\r", { "" }, setup = inputs("https://q.io", nil) },

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
  {
    "link is one undo step",
    { "word" },
    { 1, 0 },
    { ":Markwright link\r", "u" },
    { "word" },
    setup = clip("https://x.io"),
  },
  {
    "titled link + title is one undo step",
    { "https://x.io" },
    { 1, 0 },
    { ":Markwright link\r", "u" },
    { "https://x.io" },
  },

  -- the page title arrives late (after another change): undo stays per change
  {
    "late title doesn't join the next change's undo step",
    { "go https://x.io now" },
    { 1, 5 },
    { " mk", "Ax<Esc>", "<Cmd>lua _G.mw_title_arrives()<CR>", "u" },
    { "go [x.io](https://x.io) nowx" },
    setup = function()
      local pending
      title.fetch = function(_, cb)
        pending = cb
      end
      -- selene: allow(global_usage)
      _G.mw_title_arrives = function()
        pending("Title")
      end
    end,
  },
  {
    "title arriving right away is one undo step with the link",
    { "go https://x.io now" },
    { 1, 5 },
    { " mk", "u" },
    { "go https://x.io now" },
  },
  -- callout markers parse as shortcut links, but aren't links
  { "callout marker is left alone", { "> [!WARNING]", "> careful" }, { 1, 5 }, " mk", { "> [!WARNING]", "> careful" } },
  { "callout marker with a title", { "> [!NOTE] Heads up" }, { 1, 3 }, " mk", { "> [!NOTE] Heads up" } },
  { ":Markwright link on a callout marker", { "> [!TIP]" }, { 1, 4 }, ":Markwright link\r", { "> [!TIP]" } },
  { "[!x] outside a quote is still a link", { "see [!x] here" }, { 1, 5 }, " mk", { "see !x here" } },
  -- whitespace: the URL prompt is prefilled with a clipboard URL
  {
    "empty line, clipboard URL: prefilled, Enter accepts it",
    { "" },
    { 1, 0 },
    " mk",
    { "[C](https://c.io)" },
    setup = function()
      clip("https://c.io")()
      inputs("<Enter>", "C")()
    end,
  },
  {
    "empty line, clipboard URL accepted, empty text: page title",
    { "" },
    { 1, 0 },
    " mk",
    { "[Title](https://c.io)" },
    setup = function()
      clip("https://c.io")()
      inputs("<Enter>", "")()
    end,
  },
  {
    "empty line, clipboard URL replaced in the prompt",
    { "" },
    { 1, 0 },
    " mk",
    { "[R](https://r.io)" },
    setup = function()
      clip("https://c.io")()
      inputs("https://r.io", "R")()
    end,
  },
  { "empty line, no clipboard URL: empty prompt", { "" }, { 1, 0 }, " mk", { "" }, setup = inputs("<Enter>") },
  -- operator: <leader>mk{motion}
  { "bare URL: titled link at once", { "go https://x.io now" }, { 1, 5 }, " mk", { "go [Title](https://x.io) now" } },
  {
    "bare URL at once: trailing period stays outside",
    { "see https://ex.com." },
    { 1, 6 },
    " mk",
    { "see [Title](https://ex.com)." },
  },
  {
    "operator: blank line prompts URL + text",
    { "" },
    { 1, 0 },
    " mk_",
    { "[Q](https://q.io)" },
    setup = inputs("https://q.io", "Q"),
  },
  {
    "whitespace: prompts URL + text at once",
    { "a b" },
    { 1, 1 },
    " mk",
    { "a [Q](https://q.io) b" },
    setup = inputs("https://q.io", "Q"),
  },
  {
    "operator: line",
    { "- read the docs" },
    { 1, 0 },
    " mk_",
    { "- [read the docs](https://x.io)" },
    setup = clip("https://x.io"),
  },
  {
    "operator to end of line",
    { "see the docs" },
    { 1, 4 },
    " mk$",
    { "see [the docs](https://x.io)" },
    setup = clip("https://x.io"),
  },
  {
    "operator on a word",
    { "one two" },
    { 1, 4 },
    " mkiw",
    { "one [two](https://x.io)" },
    setup = clip("https://x.io"),
  },
  {
    "operator prompts without a clipboard URL",
    { "one two" },
    { 1, 0 },
    " mke",
    { "[one](https://p.io) two" },
    setup = inputs("https://p.io"),
  },
  {
    "operator on a bare URL makes a titled link (at once)",
    { "go https://x.io now" },
    { 1, 3 },
    " mk",
    { "go [Title](https://x.io) now" },
  },
  { "on a link: removes it at once", { "a [text](http://x.io) b" }, { 1, 4 }, " mk", { "a text b" } },
  { "operator with a link text object from outside", { "x [text](http://x.io)" }, { 1, 0 }, " mkak", { "x text" } },
  {
    "operator dot repeat",
    { "aa bb" },
    { 1, 0 },
    " mkiw$.",
    { "[aa](https://x.io) [bb](https://x.io)" },
    setup = clip("https://x.io"),
  },
  { "in code: skipped at once", { "`code`" }, { 1, 2 }, " mk", { "`code`" }, setup = clip("https://x.io") },
}

local failed, total = H.run("links", cases, { before_each = before_each })
vim.ui.input = real_input
return failed, total
