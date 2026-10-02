-- Table specs (SPEC.md section 9.4).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local tables = require("markwright.tables")
local eq = H.eq
local A = H.answers

local T3 = { "| a | b |", "|---|---|", "| 1 | 2 |" }
local T3_ALIGNED = { "| a   | b   |", "| --- | --- |", "| 1   | 2   |" }

local cases = {
  -- parsing
  {
    "split_row",
    fn = function()
      local texts = function(l)
        return vim.tbl_map(function(c)
          return c.text
        end, tables.split_row(l))
      end
      eq(texts("| a | b |"), { "a", "b" })
      eq(texts("a | b"), { "a", "b" })
      eq(texts("| a\\|b | c |"), { "a\\|b", "c" })
      eq(texts("  |x|  y  |"), { "x", "y" })
      eq(texts("| a | b\\|"), { "a", "b\\|" })
    end,
  },
  {
    "csv parsing",
    fn = function()
      eq(tables.csv_fields('a,"b, c","say ""hi""",', ","), { "a", "b, c", 'say "hi"', "" })
      eq(tables.csv_fields("x|y;z", ";"), { "x\\|y", "z" })
      eq(tables.detect_sep("a\tb\tc"), "\t")
      eq(tables.detect_sep("a;b;c,d"), ";")
      eq(tables.detect_sep('"x;y",z'), ",")
      -- whole blocks: a separator that splits every line the same way wins
      eq(tables.detect_sep({ "name;note", "Ana;a, b" }), ";")
      eq(tables.detect_sep({ "10:30,Ana", "11:00,Bob" }), ",")
      eq(tables.detect_sep({ "name|age", "Ana|35" }), "|")
      eq(tables.detect_sep({ "name | age", "Ana | 35" }), "|")
      eq(tables.detect_sep({ "key:value", "a:1" }), ":")
      eq(tables.detect_sep({ "single" }), ",")
      eq(tables.csv_fields("a::b::c", "::"), { "a", "b", "c" })
      eq(tables.csv_fields('"x::y"::z', "::"), { "x::y", "z" })
    end,
  },

  -- alignment
  {
    "align widths",
    { "|a|b|", "|-|-|", "|long cell|x|" },
    { 1, 0 },
    " mta",
    { "| a         | b   |", "| --------- | --- |", "| long cell | x   |" },
  },
  {
    "align markers",
    { "| a | b | c |", "|:-|:-:|-:|", "| 1 | 2 | 3 |" },
    { 1, 0 },
    " mta",
    { "| a   |  b  |   c |", "| :-- | :-: | --: |", "| 1   |  2  |   3 |" },
  },
  {
    "missing pipes + uneven rows",
    { "a | b", "---|---", "1" },
    { 1, 0 },
    " mta",
    { "| a   | b   |", "| --- | --- |", "| 1   |     |" },
  },
  {
    "escaped pipe kept",
    { "| a\\|b | c |", "|---|---|" },
    { 1, 0 },
    " mta",
    { "| a\\|b | c   |", "| ---- | --- |" },
  },
  {
    "display width (accents, CJK)",
    { "| ñandú | x |", "|---|---|", "| a | 日本 |" },
    { 1, 0 },
    " mta",
    { "| ñandú | x    |", "| ----- | ---- |", "| a     | 日本 |" },
  },
  {
    "table inside a list",
    { "- item", "  | a | b |", "  |---|---|" },
    { 2, 3 },
    " mta",
    { "- item", "  | a   | b   |", "  | --- | --- |" },
  },
  {
    "align keeps cursor in cell",
    { "|a|bb|", "|-|-|" },
    { 1, 4 },
    " mta",
    { "| a   | bb  |", "| --- | --- |" },
    { 1, 9 },
  },
  { "not in a table", { "text" }, { 1, 0 }, " mta", { "text" } },
  {
    "realign on InsertLeave",
    T3,
    { 3, 2 },
    "ilonger<Esc>",
    { "| a       | b   |", "| ------- | --- |", "| longer1 | 2   |" },
  },
  { "insert + realign undo together", T3, { 3, 2 }, { "ilonger<Esc>", "u" }, T3 },

  -- create / convert
  {
    "create 2x2",
    { "" },
    { 1, 0 },
    " mtth<Esc>",
    { "| h   |     |", "| --- | --- |", "|     |     |", "|     |     |" },
    setup = A("2x2"),
  },
  {
    "create below text",
    { "intro" },
    { 1, 0 },
    " mtt<Esc>",
    { "intro", "|     |", "| --- |", "|     |" },
    setup = A("1 x 1"),
  },
  { "create: bad size", { "" }, { 1, 0 }, " mtt", { "" }, setup = A("big") },
  { "create: cancelled", { "" }, { 1, 0 }, " mtt", { "" }, setup = A(nil) },
  {
    "CSV → table",
    { "name,age", '"Doe, J",42', "a|b;x,1" },
    { 1, 0 },
    "Vjj mtc",
    { "| name   | age |", "| ------ | --- |", "| Doe, J | 42  |", "| a\\|b;x | 1   |" },
    setup = A(""),
  },
  { "TSV → table", { "a\tb", "1\t2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("") },
  { "normal: the paragraph → table", { "a,b", "1,2" }, { 2, 0 }, " mtc", T3_ALIGNED, setup = A("") },
  {
    "normal: only the paragraph around the cursor",
    { "intro", "", "a;b", "1;2", "", "after" },
    { 3, 0 },
    " mtc",
    { "intro", "", "| a   | b   |", "| --- | --- |", "| 1   | 2   |", "", "after" },
    setup = A(""),
  },
  { "normal: blank line does nothing", { "", "a,b" }, { 1, 0 }, " mtc", { "", "a,b" }, setup = A("") },
  { "pipe-separated → table", { "a|b", "1|2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("") },
  { "pipe with spaces → table", { "a | b", "1 | 2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("") },
  { "colon-separated → table", { "a:b", "1:2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("") },
  { "typed multi-character separator", { "a::b", "1::2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("::") },
  { "typed \\t for tab", { "a\tb", "1\t2" }, { 1, 0 }, "Vj mtc", T3_ALIGNED, setup = A("\\t") },
  {
    "typed separator overrides detection",
    { "a;b,c", "1;2,3" },
    { 1, 0 },
    "Vj mtc",
    { "| a   | b,c |", "| --- | --- |", "| 1   | 2,3 |" },
    setup = A(";"),
  },
  { "CSV → table cancelled", { "a,b", "1,2" }, { 1, 0 }, "Vj mtc", { "a,b", "1,2" }, setup = A(nil) },
  {
    ":Markwright table csv with range",
    { "x;y", "1;2" },
    { 1, 0 },
    ":%Markwright table csv<CR>",
    { "| x   | y   |", "| --- | --- |", "| 1   | 2   |" },
    setup = A(""),
  },

  -- rows / columns
  {
    "add row on header goes below delimiter",
    T3,
    { 1, 2 },
    " mtj",
    { "| a   | b   |", "| --- | --- |", "|     |     |", "| 1   | 2   |" },
    { 3, 2 },
  },
  {
    "add row below body row",
    T3,
    { 3, 2 },
    " mtj",
    { "| a   | b   |", "| --- | --- |", "| 1   | 2   |", "|     |     |" },
    { 4, 2 },
  },
  {
    "delete body row",
    { "| a | b |", "|---|---|", "| 1 | 2 |", "| 3 | 4 |" },
    { 3, 2 },
    " mtdr",
    { "| a   | b   |", "| --- | --- |", "| 3   | 4   |" },
  },
  { "can't delete header", T3, { 1, 2 }, " mtdr", T3 },
  {
    "add column right",
    T3,
    { 1, 2 },
    " mtl",
    { "| a   |     | b   |", "| --- | --- | --- |", "| 1   |     | 2   |" },
    { 1, 8 },
  },
  {
    "add column keeps alignments",
    { "| a | b |", "|:-|-:|" },
    { 1, 6 },
    " mtl",
    { "| a   |   b |     |", "| :-- | --: | --- |" },
  },
  { "delete column", T3, { 1, 6 }, " mtdc", { "| a   |", "| --- |", "| 1   |" } },
  { "can't delete only column", { "| a |", "|---|" }, { 1, 2 }, " mtdc", { "| a |", "|---|" } },
  {
    "add row above body row",
    { "| a | b |", "|---|---|", "| 1 | 2 |", "| 3 | 4 |" },
    { 4, 2 },
    " mtk",
    { "| a   | b   |", "| --- | --- |", "| 1   | 2   |", "|     |     |", "| 3   | 4   |" },
    { 4, 2 },
  },
  {
    "add row above first body row",
    T3,
    { 3, 2 },
    " mtk",
    { "| a   | b   |", "| --- | --- |", "|     |     |", "| 1   | 2   |" },
  },
  { "can't add a row above the header", T3, { 1, 2 }, " mtk", T3 },
  {
    "add column left",
    T3,
    { 1, 6 },
    " mth",
    { "| a   |     | b   |", "| --- | --- | --- |", "| 1   |     | 2   |" },
    { 1, 8 },
  },
  {
    "add column left of the first",
    T3,
    { 3, 2 },
    " mth",
    { "|     | a   | b   |", "| --- | --- | --- |", "|     | 1   | 2   |" },
    { 3, 2 },
  },

  -- table → CSV
  { "table → CSV", T3, { 1, 2 }, " mtx", { "a,b", "1,2" }, { 1, 0 }, setup = A(",") },
  { "empty answer uses the default separator", T3, { 3, 2 }, " mtx", { "a,b", "1,2" }, setup = A("") },
  { "semicolon separator", T3, { 1, 2 }, " mtx", { "a;b", "1;2" }, setup = A(";") },
  { "\\t means tab", T3, { 1, 2 }, " mtx", { "a\tb", "1\t2" }, setup = A("\\t") },
  {
    "quoting and escaped pipes",
    { "| name | note |", "|---|---|", '| Doe, J | say "hi" |', "| a\\|b | x |" },
    { 1, 2 },
    " mtx",
    { "name,note", '"Doe, J","say ""hi"""', "a|b,x" },
    setup = A(","),
  },
  {
    "short rows are padded",
    { "| a | b | c |", "|---|---|---|", "| 1 |" },
    { 1, 2 },
    " mtx",
    { "a,b,c", "1,," },
    setup = A(","),
  },
  {
    "table inside a list keeps its indent",
    { "- item", "  | a | b |", "  |---|---|" },
    { 2, 4 },
    " mtx",
    { "- item", "  a,b" },
    setup = A(","),
  },
  { "cancel keeps the table", T3, { 1, 2 }, " mtx", T3, setup = A(nil) },
  { "not in a table", { "text" }, { 1, 0 }, " mtx", { "text" }, setup = A(",") },
  { "table → CSV is one undo step", T3, { 1, 2 }, { " mtx", "u" }, T3, setup = A(",") },
  { ":Markwright table tocsv", T3, { 1, 2 }, ":Markwright table tocsv<CR>", { "a,b", "1,2" }, setup = A(",") },
  {
    "CSV → table → CSV round trip",
    { "name,age", '"Doe, J",42' },
    { 1, 0 },
    { "Vj mtc", " mtx" },
    { "name,age", '"Doe, J",42' },
    setup = A("", ","),
  },

  {
    "table → pipe CSV → table round trip",
    T3,
    { 1, 2 },
    { " mtx", "Vj mtc" },
    T3_ALIGNED,
    setup = A("|", ""),
  },

  -- cell navigation
  { "<Tab> to next cell", T3, { 1, 2 }, "i<Tab>X<Esc>", { "| a   | bX  |", "| --- | --- |", "| 1   | 2   |" } },
  {
    "<Tab> wraps to next row, skipping delimiter",
    T3,
    { 1, 6 },
    "i<Tab>X<Esc>",
    { "| a   | b   |", "| --- | --- |", "| 1X  | 2   |" },
  },
  {
    "<Tab> from last cell adds a row",
    T3,
    { 3, 6 },
    "A<Tab>z<Esc>",
    { "| a   | b   |", "| --- | --- |", "| 1   | 2   |", "| z   |     |" },
  },
  {
    "<S-Tab> back over delimiter",
    T3,
    { 3, 2 },
    "i<S-Tab>Q<Esc>",
    { "| a   | bQ  |", "| --- | --- |", "| 1   | 2   |" },
  },
  -- markdown ftplugin sets expandtab + softtabstop=4, so native <Tab> inserts spaces
  { "<Tab> outside a table is native", { "x" }, { 1, 0 }, "A<Tab><Esc>", { "x   " } },
  {
    "<Tab> falls back to an existing mapping",
    fn = function()
      vim.g.markwright_tab_hit = 0
      vim.keymap.set("i", "<Tab>", "<Cmd>let g:markwright_tab_hit = 1<CR>")
      local ok, err = pcall(function()
        H.buf({ "x" }, { 1, 0 })
        H.feed("A<Tab><Esc>")
        eq(vim.g.markwright_tab_hit, 1)
        eq(api.nvim_buf_get_lines(0, 0, -1, false), { "x" })
        -- ...but still moves between cells in a table
        H.buf(T3, { 1, 2 })
        H.feed("i<Tab>X<Esc>")
        eq(api.nvim_buf_get_lines(0, 0, 1, false), { "| a   | bX  |" })
      end)
      vim.keymap.del("i", "<Tab>")
      if not ok then
        error(err)
      end
    end,
  },
}

H.mock_input()
local failed, total = H.run("tables", cases, { before_each = A() })
H.restore_input()
return failed, total
