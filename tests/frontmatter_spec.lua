-- Front matter specs (SPEC.md section 14.19).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local fm = require("markwright.frontmatter")
local eq = H.eq

local TODAY = os.date("%Y-%m-%d")
local defaults = vim.deepcopy(config.options.frontmatter)
local function before_each()
  config.options.frontmatter = vim.deepcopy(defaults)
end
local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end

local cases = {
  {
    "insert with the title from the first heading",
    { "# My Notes", "", "text" },
    { 3, 0 },
    " mF",
    { "---", "title: My Notes", "date: " .. TODAY, "tags: []", "---", "", "# My Notes", "", "text" },
    { 2, 14 },
  },
  {
    "title from the file name when there's no heading",
    fn = function()
      H.buf({ "text" }, { 1, 0 }, vim.fn.tempname() .. "/meeting-notes_2026.md")
      H.feed(" mF")
      eq(lines()[2], "title: Meeting notes 2026")
    end,
  },
  {
    "an empty buffer",
    fn = function()
      H.buf({ "" }, { 1, 0 })
      H.feed(" mF")
      eq(lines(), { "---", 'title: ""', "date: " .. TODAY, "tags: []", "---", "" })
    end,
  },
  {
    "titles that need quotes",
    fn = function()
      eq(fm.yaml_string("Plain title"), "Plain title")
      eq(fm.yaml_string("Note: read me"), '"Note: read me"')
      eq(fm.yaml_string("#hashtag"), '"#hashtag"')
      eq(fm.yaml_string('say "hi"'), 'say "hi"')
      eq(fm.yaml_string('- "x"'), '"- \\"x\\""')
    end,
  },
  {
    "on a file with front matter it jumps into it",
    { "---", "title: x", "---", "", "text" },
    { 5, 0 },
    " mF",
    { "---", "title: x", "---", "", "text" },
    { 2, 7 },
  },
  {
    "TOML front matter counts too",
    { "+++", 'title = "x"', "+++", "text" },
    { 4, 0 },
    " mF",
    { "+++", 'title = "x"', "+++", "text" },
    { 2, 10 },
  },
  {
    "custom template and date format",
    fn = function()
      config.options.frontmatter.template = { "---", "layout: post", "title: {title}", "published: {date}", "---" }
      config.options.frontmatter.date_format = "%d/%m/%Y"
      H.buf({ "# Hello" }, { 1, 0 })
      H.feed(" mF")
      eq(lines(), { "---", "layout: post", "title: Hello", "published: " .. os.date("%d/%m/%Y"), "---", "", "# Hello" })
    end,
  },
  {
    "template as a function",
    fn = function()
      config.options.frontmatter.template = function()
        return { "---", "id: 42", "---" }
      end
      H.buf({ "x" }, { 1, 0 })
      H.feed(" mF")
      eq(lines(), { "---", "id: 42", "---", "", "x" })
    end,
  },
  { "insert is one undo step", { "# T" }, { 1, 0 }, { " mF", "u" }, { "# T" } },
  -- update on save
  {
    "updated: refreshed on save when enabled, quotes kept",
    fn = function()
      config.options.frontmatter.update_on_save = true
      local path = vim.fn.tempname() .. ".md"
      local buf = H.buf({ "---", 'updated: "2020-01-01"', "---", "x" }, { 4, 0 }, path)
      vim.bo[buf].buftype = ""
      vim.cmd("silent write")
      eq(vim.fn.readfile(path)[2], 'updated: "' .. TODAY .. '"')
      vim.fn.delete(path)
    end,
  },
  {
    "nothing is added, and it's off by default",
    fn = function()
      local path = vim.fn.tempname() .. ".md"
      local buf = H.buf({ "---", "lastmod: 2020-01-01", "---", "x" }, { 4, 0 }, path)
      vim.bo[buf].buftype = ""
      vim.cmd("silent write")
      eq(vim.fn.readfile(path)[2], "lastmod: 2020-01-01")
      vim.fn.delete(path)
      config.options.frontmatter.update_on_save = true
      local path2 = vim.fn.tempname() .. ".md"
      buf = H.buf({ "---", "title: t", "---" }, { 1, 0 }, path2)
      vim.bo[buf].buftype = ""
      vim.cmd("silent write")
      eq(vim.fn.readfile(path2), { "---", "title: t", "---" })
      vim.fn.delete(path2)
    end,
  },
  -- the rest of the plugin ignores it
  {
    "front matter isn't a heading, prose or a table of contents entry",
    fn = function()
      H.buf({ "---", "title: Not a heading", "tags: [a, b]", "---", "", "# Real", "word" }, { 1, 0 })
      local hs = require("markwright.doc").headings(0)
      eq(#hs, 1)
      eq(hs[1].text, "Real")
      eq(require("markwright.stats").count(0).words, 2)
    end,
  },
  {
    ":Markwright frontmatter",
    fn = function()
      H.buf({ "# A" }, { 1, 0 })
      vim.cmd("Markwright frontmatter")
      eq(lines()[1], "---")
    end,
  },
}

return H.run("front matter", cases, { before_each = before_each })
