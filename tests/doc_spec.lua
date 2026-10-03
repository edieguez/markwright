-- TOC + diagnostics specs (SPEC.md sections 9.6, 10).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local diagnostics = require("markwright.diagnostics")
local eq = H.eq

local DOC = { "# Title", "", "## A", "### A.1", "## B `code`", "```", "## not a heading", "```", "## See [docs](u)" }
local TOC = {
  "<!-- toc -->",
  "- [A](#a)",
  "  - [A.1](#a1)",
  "- [B `code`](#b-code)",
  "- [See docs](#see-docs)",
  "<!-- tocstop -->",
}

local function with(t, extra)
  local out = vim.deepcopy(t)
  vim.list_extend(out, extra)
  return out
end

local dir = H.tmpdir({
  ["exists.md"] = { "# Exists", "## Part" },
  ["img.png"] = { "x" },
  ["sub/deep.md"] = { "# Deep" },
})

local function messages(buf)
  local out = {}
  for _, d in ipairs(diagnostics.collect(buf)) do
    table.insert(out, (d.lnum + 1) .. ": " .. d.message)
  end
  return out
end

local cases = {
  -- TOC
  {
    "insert on blank line",
    with({ "# Title", "" }, { unpack(DOC, 3) }),
    { 2, 0 },
    " mO",
    with({ "# Title" }, with(TOC, { unpack(DOC, 3) })),
  },
  {
    "insert below text adds a blank line",
    { "intro", "## X" },
    { 1, 0 },
    " mO",
    { "intro", "", "<!-- toc -->", "- [X](#x)", "<!-- tocstop -->", "## X" },
  },
  {
    "update stale TOC",
    { "<!-- toc -->", "- [Old](#old)", "<!-- tocstop -->", "## New", "## New" },
    { 4, 0 },
    " mO",
    { "<!-- toc -->", "- [New](#new)", "- [New](#new-1)", "<!-- tocstop -->", "## New", "## New" },
  },
  {
    "TOC respects level range",
    { "", "# H1", "## H2", "#### H4", "##### H5" },
    { 1, 0 },
    " mO",
    { "<!-- toc -->", "- [H2](#h2)", "    - [H4](#h4)", "<!-- tocstop -->", "# H1", "## H2", "#### H4", "##### H5" },
  },
  { "TOC is one undo step", { "", "## X" }, { 1, 0 }, { " mO", "u" }, { "", "## X" } },
  {
    "TOC updates on save",
    fn = function()
      local path = dir .. "/toc.md"
      vim.fn.writefile({ "<!-- toc -->", "<!-- tocstop -->", "## Saved" }, path)
      vim.cmd("edit! " .. vim.fn.fnameescape(path))
      vim.cmd("silent write")
      eq(vim.fn.readfile(path), { "<!-- toc -->", "- [Saved](#saved)", "<!-- tocstop -->", "## Saved" })
      -- unchanged TOC: save doesn't modify the buffer
      vim.cmd("silent write")
      eq(vim.bo.modified, false)
      vim.cmd("bwipeout!")
    end,
  },
  {
    "TOC update disabled",
    fn = function()
      config.options.toc.update_on_save = false
      local path = dir .. "/toc2.md"
      vim.fn.writefile({ "<!-- toc -->", "<!-- tocstop -->", "## Saved" }, path)
      vim.cmd("edit! " .. vim.fn.fnameescape(path))
      vim.cmd("silent write")
      config.options.toc.update_on_save = true
      eq(vim.fn.readfile(path)[2], "<!-- tocstop -->")
      vim.cmd("bwipeout!")
    end,
  },

  -- diagnostics
  {
    "broken links, anchors, references, footnotes",
    fn = function()
      local buf = H.buf({
        "[ok](exists.md) [bad](missing.md)",
        "[a](#top) [b](#nope)",
        "[c](exists.md#part) [d](exists.md#zzz) [e](sub/deep.md)",
        "![i](img.png) ![j](gone.png)",
        "[web](https://x.io) [mail](mailto:a@b.c) [ext](zotero://x)",
        "[f][ref] [g][nodef] [h][]",
        "Note[^1] and[^2].",
        "",
        "# Top",
        "",
        "[ref]: exists.md",
        "[bad2]: nope.md",
        "[h]: #top",
        "[^1]: one",
        "[^3]: three",
      }, { 1, 0 }, dir .. "/doc.md")
      eq(messages(buf), {
        "1: file not found: missing.md",
        "2: no heading for #nope",
        "3: no heading #zzz in exists.md",
        "4: file not found: gone.png",
        "6: undefined reference [nodef]",
        "7: no definition for [^2]",
        "12: file not found: nope.md",
        "15: footnote [^3] is never referenced",
      })
    end,
  },
  {
    "diagnostic ranges point at the destination",
    fn = function()
      local buf = H.buf({ "see [bad](missing.md) ok" }, { 1, 0 }, dir .. "/doc.md")
      local d = diagnostics.collect(buf)[1]
      eq({ d.lnum, d.col, d.end_col, d.source }, { 0, 10, 20, "markwright" })
    end,
  },
  {
    "code is ignored",
    fn = function()
      local buf = H.buf(
        { "`[x](missing.md)` and `[^9]`", "```", "[y](missing.md) [^8]", "```" },
        { 1, 0 },
        dir .. "/doc.md"
      )
      eq(messages(buf), {})
    end,
  },
  {
    "unsaved buffer: relative files not checked",
    fn = function()
      local buf = H.buf({ "[x](missing.md) [y](#nope)" }, { 1, 0 })
      eq(messages(buf), { "1: no heading for #nope" })
    end,
  },
  {
    "published on save, cleared when fixed",
    fn = function()
      local path = dir .. "/diag.md"
      vim.fn.writefile({ "[x](missing.md)" }, path)
      vim.cmd("edit! " .. vim.fn.fnameescape(path))
      vim.cmd("silent write")
      eq(#vim.diagnostic.get(0, { namespace = diagnostics.ns }), 1)
      api.nvim_buf_set_lines(0, 0, -1, false, { "[x](exists.md)" })
      eq(#vim.diagnostic.get(0, { namespace = diagnostics.ns }), 1) -- kept until next save
      vim.cmd("silent write")
      eq(#vim.diagnostic.get(0, { namespace = diagnostics.ns }), 0)
      vim.cmd("bwipeout!")
    end,
  },
  {
    ":Markwright check",
    fn = function()
      H.buf({ "[y](#nope)" }, { 1, 0 })
      vim.cmd("Markwright check")
      eq(#vim.diagnostic.get(0, { namespace = diagnostics.ns }), 1)
    end,
  },
}

return H.run("toc + diagnostics", cases)
