-- Text object specs (SPEC.md section 14.8).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local eq = H.eq

local function yanked(lines, cursor, keys)
  H.buf(lines, cursor)
  vim.fn.setreg('"', "")
  H.feed(keys)
  return vim.fn.getreg('"'), vim.fn.getregtype('"')
end

local LINK = { "see [the docs](http://x.io) ok" }
local SECTIONS = { "# A", "", "text a", "", "## B", "b1", "", "## C", "c1" }
local LIST = { "- [ ] item one", "  - child", "    more", "- two" }
local T = { "| a   | bb  |", "| --- | --- |", "| 1   | 2   |" }

local cases = {
  -- links
  { "dik deletes the link text", LINK, { 1, 6 }, "dik", { "see [](http://x.io) ok" } },
  { "cik changes the link text", LINK, { 1, 6 }, "ciknew<Esc>", { "see [new](http://x.io) ok" } },
  { "cik from the URL part", LINK, { 1, 18 }, "cikX<Esc>", { "see [X](http://x.io) ok" } },
  { "dak deletes the whole link", LINK, { 1, 6 }, "dak", { "see  ok" } },
  {
    "callout marker isn't a link: cik goes to the next link",
    { "> [!NOTE]", "> see [a](http://x.io)" },
    { 1, 4 },
    "cikX<Esc>",
    { "> [!NOTE]", "> see [X](http://x.io)" },
  },
  {
    "callout marker alone: dik does nothing",
    { "> [!WARNING]", "> text" },
    { 1, 5 },
    "dik",
    { "> [!WARNING]", "> text" },
  },
  { "cik searches forward on the line", LINK, { 1, 0 }, "cikX<Esc>", { "see [X](http://x.io) ok" } },
  { "image alt text", { "![alt txt](i.png)" }, { 1, 3 }, "dik", { "![](i.png)" } },
  { "autolink inner / around", { "a <http://y.io> b" }, { 1, 4 }, "dik", { "a <> b" } },
  { "autolink around", { "a <http://y.io> b" }, { 1, 4 }, "dak", { "a  b" } },
  { "bare URL", { "go https://x.io/a now" }, { 1, 5 }, "dik", { "go  now" } },
  {
    "reference link text",
    { "[text][ref]", "", "[ref]: http://z" },
    { 1, 2 },
    "dik",
    { "[][ref]", "", "[ref]: http://z" },
  },
  { "empty link text: cik inserts", { "[](u)" }, { 1, 0 }, "cikx<Esc>", { "[x](u)" } },
  { "dot-repeat cik", { "[a](u) [b](v)" }, { 1, 1 }, { "cikX<Esc>", "f[." }, { "[X](u) [X](v)" } },
  { "visual vak", LINK, { 1, 6 }, "vakd", { "see  ok" } },
  { "no link: nothing happens", { "plain text" }, { 1, 2 }, "dik", { "plain text" } },

  -- URLs
  { "diu", LINK, { 1, 6 }, "diu", { "see [the docs]() ok" } },
  { "ciu", LINK, { 1, 6 }, "ciuhttps://y.io<Esc>", { "see [the docs](https://y.io) ok" } },
  { "URL in angle brackets", { "[t](<a b.md>)" }, { 1, 1 }, "diu", { "[t](<>)" } },
  {
    "URL of a reference link's definition",
    { "[t][r]", "", "[r]: http://x" },
    { 1, 1 },
    "ciuhttp://y<Esc>",
    { "[t][r]", "", "[r]: http://y" },
  },
  {
    "yiu copies the URL",
    fn = function()
      eq(yanked(LINK, { 1, 6 }, "yiu"), "http://x.io")
    end,
  },

  -- code
  { "dic in inline code", { "a `co de` b" }, { 1, 4 }, "dic", { "a `` b" } },
  { "dac in inline code", { "a `co de` b" }, { 1, 4 }, "dac", { "a  b" } },
  { "dic skips padding", { "`` `x ``" }, { 1, 4 }, "dic", { "``  ``" } },
  {
    "dif in a fenced block",
    { "a", "```lua", "x = 1", "y = 2", "```", "b" },
    { 3, 0 },
    "dif",
    { "a", "```lua", "```", "b" },
  },
  { "daf removes the block", { "a", "```lua", "x = 1", "```", "b" }, { 3, 0 }, "daf", { "a", "b" } },
  {
    "yif from the fence line",
    fn = function()
      local text, typ = yanked({ "```", "x", "y", "```" }, { 1, 0 }, "yif")
      eq({ text, typ }, { "x\ny\n", "V" })
    end,
  },
  { "cif replaces block content", { "```", "old", "```" }, { 2, 0 }, "cifnew<Esc>", { "```", "new", "```" } },
  { "empty block: nothing", { "```", "```" }, { 1, 0 }, "dif", { "```", "```" } },
  {
    "indented code block",
    { "text", "", "    code", "    more", "", "end" },
    { 3, 4 },
    "dif",
    { "text", "", "", "end" },
  },

  -- heading sections
  { "di#: content only", SECTIONS, { 6, 0 }, "di#", { "# A", "", "text a", "", "## B", "", "## C", "c1" } },
  { "da#: heading + content", SECTIONS, { 6, 0 }, "da#", { "# A", "", "text a", "", "## C", "c1" } },
  { "da# from the heading line", SECTIONS, { 5, 0 }, "da#", { "# A", "", "text a", "", "## C", "c1" } },
  { "d2a#: parent section", SECTIONS, { 6, 0 }, "d2a#", { "" } },
  { "di# on a parent includes subsections", SECTIONS, { 3, 0 }, "di#", { "# A", "" } },
  { "ci#", SECTIONS, { 6, 0 }, "ci#new<Esc>", { "# A", "", "text a", "", "## B", "new", "", "## C", "c1" } },
  { "setext heading", { "Title", "=====", "body", "more" }, { 3, 0 }, "di#", { "Title", "=====" } },
  { "headings in code don't count", { "# A", "```", "# not", "```", "x" }, { 5, 0 }, "di#", { "# A" } },

  -- table cells
  { "diz deletes cell text", T, { 1, 8 }, "diz", { "| a   |   |", "| --- | --- |", "| 1   | 2   |" } },
  { "ciz then realign", T, { 1, 8 }, "cizX<Esc>", { "| a   | X   |", "| --- | --- |", "| 1   | 2   |" } },
  { "ciz in an empty cell", { "| a |   |", "|---|---|" }, { 1, 7 }, "cizz<Esc>", { "| a   | z   |", "| --- | --- |" } },
  {
    "yiz copies the cell",
    fn = function()
      eq(yanked(T, { 3, 2 }, "yiz"), "1")
    end,
  },
  { "outside a table: nothing", { "a | b" }, { 1, 0 }, "diz", { "a | b" } },

  -- list items
  { "dix: the item's text", LIST, { 1, 8 }, "dix", { "- [ ] ", "  - child", "    more", "- two" } },
  { "dax: item with children", LIST, { 1, 8 }, "dax", { "- two" } },
  { "dax on a child", LIST, { 2, 5 }, "dax", { "- [ ] item one", "- two" } },
  { "d2ax: parent item", LIST, { 2, 5 }, "d2ax", { "- two" } },
  { "cix across continuation lines", LIST, { 2, 5 }, "cixX<Esc>", { "- [ ] item one", "  - X", "- two" } },
  { "ordered item", { "1. first", "2. second" }, { 2, 4 }, "cixnew<Esc>", { "1. first", "2. new" } },
  { "not in a list: nothing", { "text" }, { 1, 0 }, "dax", { "text" } },

  -- emphasis
  { "di* bold", { "a **bold** b" }, { 1, 5 }, "di*", { "a **** b" } },
  { "da* bold", { "a **bold** b" }, { 1, 5 }, "da*", { "a  b" } },
  { "innermost first", { "***bi***" }, { 1, 4 }, "di*", { "******" } },
  { "count reaches the outer span", { "***bi***" }, { 1, 4 }, "c2i*X<Esc>", { "*X*" } },
  { "strikethrough", { "~~del~~" }, { 1, 3 }, "di*", { "~~~~" } },
  { "highlight", { "a ==hl== b" }, { 1, 4 }, "di*", { "a ==== b" } },
  { "italic inside a link", { "[x *em* y](u)" }, { 1, 5 }, "di*", { "[x ** y](u)" } },
  { "searches forward on the line", { "x **y** z" }, { 1, 0 }, "di*", { "x **** z" } },
  { "visual vi*", { "a *it* b" }, { 1, 4 }, "vi*d", { "a ** b" } },

  -- not inside one: the next one, even on later lines (like mini.ai)
  {
    "cik: link on a later line",
    { "no link here", "", "see [a](u)" },
    { 1, 0 },
    "cikX<Esc>",
    { "no link here", "", "see [X](u)" },
    { 3, 5 },
  },
  { "dak: image on the next line", { "text", "![alt](i.png) end" }, { 1, 2 }, "dak", { "text", " end" } },
  { "ciu: URL on a later line", { "x", "[t](old)" }, { 1, 0 }, "ciunew<Esc>", { "x", "[t](new)" } },
  { "dik: bare URL on the next line", { "x", "go https://a.io now" }, { 1, 0 }, "dik", { "x", "go  now" } },
  {
    "cic: inline code on a later line",
    { "text", "", "use `x` here" },
    { 1, 0 },
    "cicY<Esc>",
    { "text", "", "use `Y` here" },
  },
  { "ic doesn't match a code block", { "```", "x", "```" }, { 2, 0 }, "dic", { "```", "x", "```" } },
  { "dif: code block below", { "text", "```", "a", "```" }, { 1, 0 }, "dif", { "text", "```", "```" } },
  { "ci*: emphasis on the next line", { "plain", "a **b** c" }, { 1, 0 }, "ci*Z<Esc>", { "plain", "a **Z** c" } },
  { "di*: highlight on the next line", { "plain", "a ==h== c" }, { 1, 0 }, "di*", { "plain", "a ==== c" } },
  { "cix: list item below", { "intro", "", "- item" }, { 1, 0 }, "cixW<Esc>", { "intro", "", "- W" } },
  {
    "ciz: table below",
    { "intro", "", "| a | b |", "|---|---|" },
    { 1, 0 },
    "cizV<Esc>",
    { "intro", "", "| V   | b   |", "| --- | --- |" },
  },
  { "da#: before the first heading, the next section", { "intro", "", "# A", "a" }, { 1, 0 }, "da#", { "intro", "" } },
  { "vik selects the next link", { "x", "[ab](u)" }, { 1, 0 }, "vikd", { "x", "[](u)" } },
  {
    "the next one after the cursor, not the first on the line",
    { "[a](u) [b](v)", "[c](w)" },
    { 1, 6 },
    "cikX<Esc>",
    { "[a](u) [X](v)", "[c](w)" },
  },
  {
    "dot-repeat moves on to the following link",
    { "[a](u)", "text", "[b](v)" },
    { 1, 1 },
    { "cikX<Esc>", "j." },
    { "[X](u)", "text", "[X](v)" },
  },
  { "never searches backwards", { "[a](u)", "text" }, { 2, 0 }, "dik", { "[a](u)", "text" } },
  {
    "search limit",
    fn = function()
      local config = require("markwright.config")
      config.options.textobjects.search_lines = 1
      local ok, err = pcall(function()
        H.buf({ "x", "y", "z", "[a](u)" }, { 1, 0 })
        H.feed("dik")
        eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "x", "y", "z", "[a](u)" })
      end)
      config.options.textobjects.search_lines = 500
      assert(ok, err)
    end,
  },

  -- configuration
  {
    "keys are buffer-local and configurable",
    fn = function()
      H.buf({ "x" })
      eq(vim.fn.maparg("ik", "o") ~= "", true)
      eq(vim.fn.maparg("az", "x") ~= "", true)
      eq(vim.fn.maparg("i#", "o") ~= "", true)
      eq(vim.fn.maparg("ax", "o") ~= "", true)
      eq(vim.fn.maparg("if", "o") ~= "", true)
      eq(vim.fn.maparg("iu", "o") ~= "", true)
      eq(vim.fn.maparg("au", "o"), "")
      vim.cmd("enew!")
      eq(vim.fn.maparg("ik", "o"), "") -- not in non-markdown buffers
    end,
  },
}

return H.run("text objects", cases)
