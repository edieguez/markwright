-- Local usage counts (usage.lua, :Markwright usage).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local usage = require("markwright.usage")
local eq = H.eq

local function before_each()
  usage._pending = {}
  usage._default_file = vim.fn.tempname() .. "-usage.json"
end

local function count(id)
  local f = usage.data().features[id]
  return f and f.count or 0
end

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end

local TABLE = { "| a |", "| - |", "| 1 |" }

local cases = {
  {
    "on by default, in a file under stdpath('data')",
    fn = function()
      eq(config.defaults.usage.enabled, true)
      local real = usage._default_file
      usage._default_file = nil
      eq(usage.path(), vim.fs.joinpath(vim.fn.stdpath("data"), "markwright", "usage.json"))
      usage._default_file = real
    end,
  },
  {
    "a key counts once per press, with its description",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      H.feed(" mtj")
      H.feed(" mtj")
      eq(#lines(), 5)
      eq(count("n <P>tj"), 2)
      eq(usage.data().features["n <P>tj"].desc, "Add row below")
      eq(usage.data().features["n <P>tj"].last, os.date("%Y-%m-%d"))
    end,
  },
  {
    "visual keys count under x",
    fn = function()
      H.buf({ "a", "b" }, { 1, 0 })
      H.feed("Vj mlb")
      eq(lines(), { "- a", "- b" })
      eq(count("x <P>lb"), 1)
      eq(count("n <P>lb"), 0)
    end,
  },
  {
    "keys that keep their meaning elsewhere count only when markwright acts",
    fn = function()
      H.buf({ "plain text" }, { 1, 0 })
      H.feed("ox<Esc>")
      eq(lines(), { "plain text", "x" })
      eq(count("n o"), 0)
      H.buf({ "- item" }, { 1, 0 })
      H.feed("ox<Esc>")
      eq(lines(), { "- item", "- x" })
      eq(count("n o"), 1)
      H.buf({ "plain" }, { 1, 0 })
      H.feed("A<CR>y<Esc>")
      eq(count("i <CR>"), 0)
      H.buf({ "- item" }, { 1, 0 })
      H.feed("A<CR>y<Esc>")
      eq(lines(), { "- item", "- y" })
      eq(count("i <CR>"), 1)
      -- normal <CR> on plain text runs the previous mapping
      H.buf({ "text", "more" }, { 1, 0 })
      H.feed("<CR>")
      eq(count("n <CR>"), 0)
    end,
  },
  {
    "insert-mode keys count as i <trigger><key>",
    fn = function()
      H.buf({ "" }, { 1, 0 })
      H.feed("i;;bword<Esc>")
      eq(lines(), { "**word**" })
      eq(count("i <T>b"), 1)
      eq(usage.display("i <T>b"), "i ;;b")
    end,
  },
  {
    "text objects and heading motions count",
    fn = function()
      H.buf({ "see [docs](https://x.org) now" }, { 1, 6 })
      H.feed("dik")
      eq(lines(), { "see [](https://x.org) now" })
      eq(count("ox ik"), 1)
      H.buf({ "# A", "", "# B" }, { 1, 0 })
      H.feed("]]")
      eq(api.nvim_win_get_cursor(0), { 3, 0 })
      eq(count("nxo ]]"), 1)
    end,
  },
  {
    "commands count with their action, not their arguments",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      vim.cmd("Markwright table row 2")
      vim.cmd("Markwright table row")
      eq(count(":Markwright table row"), 2)
      H.buf({ "text" }, { 1, 0 })
      vim.cmd("Markwright callout note")
      eq(count(":Markwright callout"), 1)
      eq(count(":Markwright callout note"), 0)
      vim.cmd("Markwright usage")
      vim.cmd("tabclose")
      eq(count(":Markwright usage"), 0)
    end,
  },
  {
    "flush adds to the file another Neovim wrote meanwhile",
    fn = function()
      usage.record("n <P>tj", "Add row below")
      eq(usage.flush(), true)
      eq(usage._pending, {})
      -- another instance
      local data = usage.load()
      data.features["n <P>tj"].count = 10
      data.features["n <P>k"] = { count = 3, desc = "Link", last = "2026-01-01" }
      vim.fn.writefile({ vim.json.encode(data) }, usage.path())
      usage.record("n <P>tj")
      usage.flush()
      eq(count("n <P>tj"), 11)
      eq(count("n <P>k"), 3)
    end,
  },
  {
    "a broken file starts over instead of failing",
    fn = function()
      vim.fn.mkdir(vim.fs.dirname(usage.path()), "p")
      vim.fn.writefile({ "{not json" }, usage.path())
      usage.record("n <P>tj")
      eq(usage.flush(), true)
      eq(count("n <P>tj"), 1)
    end,
  },
  {
    "the prefix is stored as <P>, so counts survive changing it",
    fn = function()
      eq(usage.key_id("n", "<leader>mtj"), "n <P>tj")
      eq(usage.key_id({ "o", "x" }, "ik"), "ox ik")
      eq(usage.display("n <P>tj"), "n <leader>mtj")
    end,
  },
  {
    "report: most used first, then the features never used",
    fn = function()
      usage.record("n <P>k", "Link")
      usage.record("n <P>tj", "Add row below")
      usage.record("n <P>tj", "Add row below")
      usage._known["n <P>tK"] = "Move row up"
      local r = usage.report_lines({ ":Markwright toc" })
      local text = table.concat(r, "\n")
      local a = text:find("| n <leader>mtj", 1, true)
      local b = text:find("| n <leader>mk ", 1, true)
      local never = text:find("## Never used", 1, true)
      assert(a and b and never and a < b and b < never, text)
      assert(text:find("|    2 | n <leader>mtj", 1, true), text)
      assert(text:find("| n <leader>mtK", never, true), text)
      assert(text:find("| :Markwright toc", never, true), text)
      assert(text:find("3 uses of 2 features", 1, true), text)
    end,
  },
  {
    ":Markwright usage opens the report as Markdown; reset keeps a backup",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      H.feed(" mtj")
      vim.cmd("Markwright usage")
      eq(api.nvim_buf_get_name(0), "markwright://usage")
      eq(vim.bo.filetype, "markdown")
      local text = table.concat(lines(), "\n")
      assert(text:find("n <leader>mtj", 1, true), text)
      assert(text:find(":Markwright table delrow", 1, true), text) -- never used
      vim.cmd("tabclose")
      eq(vim.fn.getcompletion("Markwright usage ", "cmdline"), { "reset" })
      vim.cmd("Markwright usage reset")
      eq(count("n <P>tj"), 0)
      eq(vim.fn.filereadable(usage.path() .. ".bak"), 1)
    end,
  },
  {
    "off: keys aren't wrapped and nothing is written",
    fn = function()
      require("markwright").setup({ usage = { enabled = false } })
      local ok, err = pcall(function()
        H.buf(TABLE, { 3, 2 })
        H.feed(" mtj")
        eq(#lines(), 4)
        usage.record("n <P>tj")
        eq(usage._pending, {})
        eq(usage.flush(), true)
        eq(vim.fn.filereadable(usage.path()), 0)
        local m = vim.fn.maparg(" mtj", "n", false, true)
        eq(m.desc, "markwright: Add row below")
      end)
      require("markwright").setup({})
      assert(ok, err)
    end,
  },
  {
    "config is validated",
    fn = function()
      local ok = pcall(config.setup, { usage = { enabled = "yes" } })
      eq(ok, false)
      ok = pcall(config.setup, { usage = { file = 3 } })
      eq(ok, false)
      config.setup({})
    end,
  },
}

return H.run("usage", cases, { before_each = before_each })
