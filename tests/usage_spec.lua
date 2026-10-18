-- Local usage counts (usage.lua) and the report (usage_ui.lua).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local usage = require("markwright.usage")
local ui = require("markwright.usage_ui")
local eq = H.eq

local real_clock = usage.clock
local function before_each()
  usage._pending = {}
  usage._default_file = vim.fn.tempname() .. "-usage.json"
  usage.clock = real_clock
  ui.state = { sort = "recent", grouped = true, unused_rows = false }
end

local function entry(id)
  return usage.data().features[id] or {}
end
local function count(id)
  return entry(id).count or 0
end

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end

local function at_day(offset)
  local t = real_clock() + offset * 86400
  usage.clock = function()
    return t
  end
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
    "keys count per feature: both add-row keys are one feature",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      H.feed(" mtj")
      H.feed(" mtj")
      H.feed(" mtk")
      eq(#lines(), 6)
      local e = entry("table.add_row")
      eq(e.count, 3)
      eq(e.via, { key = 3 })
      eq(e.days, { [usage.today()] = 3 })
      eq(e.last, usage.today())
    end,
  },
  {
    "visual keys and commands are told apart in `via`",
    fn = function()
      H.buf({ "a", "b" }, { 1, 0 })
      H.feed("Vj mlb")
      eq(lines(), { "- a", "- b" })
      vim.cmd("Markwright list number")
      eq(entry("list.convert").via, { visual = 1, command = 1 })
    end,
  },
  {
    "keys that keep their meaning elsewhere count only when markwright acts",
    fn = function()
      H.buf({ "plain text" }, { 1, 0 })
      H.feed("ox<Esc>")
      H.feed("A<CR>y<Esc>")
      eq(lines(), { "plain text", "x", "y" })
      H.buf({ "text", "more" }, { 1, 0 })
      H.feed("<CR>")
      eq(usage.data().features, {})
      H.buf({ "- item" }, { 1, 0 })
      H.feed("ox<Esc>")
      H.feed("A<CR>y<Esc>")
      eq(lines(), { "- item", "- x", "- y" })
      eq(count("list.continue"), 2)
      H.buf({ "> quote" }, { 1, 0 })
      H.feed("A<CR>z<Esc>")
      eq(lines(), { "> quote", "> z" })
      eq(count("quote.continue"), 1)
    end,
  },
  {
    "<Tab> is the next table cell or list nesting, from what it did",
    fn = function()
      H.buf({ "| a | b |", "| - | - |", "| 1 | 2 |" }, { 3, 2 })
      H.feed("i<Tab><Esc>")
      eq(count("table.next_cell"), 1)
      H.buf({ "- a", "- b" }, { 2, 0 })
      H.feed("A<Tab><Esc>")
      eq(lines(), { "- a", "  - b" })
      eq(count("list.indent"), 1)
    end,
  },
  {
    "insert-mode keys count as their feature, via insert",
    fn = function()
      H.buf({ "" }, { 1, 0 })
      H.feed("i;;bword<Esc>")
      eq(lines(), { "**word**" })
      eq(entry("format.bold").via, { insert = 1 })
    end,
  },
  {
    "text objects and heading motions count",
    fn = function()
      H.buf({ "see [docs](https://x.org) now" }, { 1, 6 })
      H.feed("dik")
      eq(lines(), { "see [](https://x.org) now" })
      eq(count("textobject.link"), 1)
      H.buf({ "# A", "", "# B" }, { 1, 0 })
      H.feed("]]")
      eq(api.nvim_win_get_cursor(0), { 3, 0 })
      eq(count("nav.heading"), 1)
    end,
  },
  {
    "commands count as their feature, whatever the arguments",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      vim.cmd("Markwright table row 2")
      vim.cmd("Markwright table rowabove")
      eq(entry("table.add_row").via, { command = 2 })
      vim.cmd("Markwright table move right")
      eq(count("table.move_col"), 1)
      H.buf({ "text" }, { 1, 0 })
      vim.cmd("Markwright callout note")
      eq(count("callout.toggle"), 1)
      eq(usage.command_feature({ "section", "up", "2" }), "section.move")
      eq(usage.command_feature({ "section", "add" }), "section.change")
      eq(usage.command_feature({ "footnote" }), "footnote.insert")
      eq(usage.command_feature({ "usage" }), nil)
    end,
  },
  {
    "every key maps to a known feature, and every feature can be reached",
    fn = function()
      H.buf({ "x" }, { 1, 0 })
      for id in pairs(usage._registered) do
        assert(usage.FEATURES[id], "unknown feature " .. id)
      end
      for id, f in pairs(usage.FEATURES) do
        assert(f.cmd or usage._registered[id], "feature without a key or command: " .. id)
      end
      for _, a in pairs(usage.FEATURES) do
        assert(vim.tbl_contains(usage.AREAS, a.area), a.area)
      end
    end,
  },
  {
    "every feature's docs heading is in the README",
    fn = function()
      local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
      local heads = {}
      for _, l in ipairs(vim.fn.readfile(root .. "/README.md")) do
        local h = l:match("^#+%s+(.-)%s*$")
        if h then
          heads[h] = true
        end
      end
      for id, f in pairs(usage.FEATURES) do
        assert(heads[f.doc], id .. ": no README heading '" .. tostring(f.doc) .. "'")
      end
    end,
  },
  {
    "flush adds to the file another Neovim wrote meanwhile",
    fn = function()
      usage.record("table.add_row", "key")
      eq(usage.flush(), true)
      eq(usage._pending, {})
      local data = usage.load()
      data.features["table.add_row"].count = 10
      data.features["link.toggle"] = { count = 3, via = { key = 3 }, days = {}, last = "2026-01-01" }
      vim.fn.writefile({ vim.json.encode(data) }, usage.path())
      usage.record("table.add_row", "command")
      usage.flush()
      eq(count("table.add_row"), 11)
      eq(entry("table.add_row").via, { key = 1, command = 1 })
      eq(count("link.toggle"), 3)
    end,
  },
  {
    "daily counts older than 90 days are dropped; totals stay",
    fn = function()
      at_day(-100)
      usage.record("toc", "key")
      usage.flush()
      at_day(0)
      usage.record("toc", "key")
      usage.flush()
      local e = entry("toc")
      eq(e.count, 2)
      eq(e.days, { [usage.today()] = 1 })
    end,
  },
  {
    "a broken file starts over instead of failing",
    fn = function()
      vim.fn.mkdir(vim.fs.dirname(usage.path()), "p")
      vim.fn.writefile({ "{not json" }, usage.path())
      usage.record("toc", "key")
      eq(usage.flush(), true)
      eq(count("toc"), 1)
    end,
  },
  {
    "counts from 4.5.0 (per key) carry over to their features",
    fn = function()
      H.buf({ "x" }, { 1, 0 }) -- maps the keys, so their ids are known
      vim.fn.mkdir(vim.fs.dirname(usage.path()), "p")
      vim.fn.writefile({
        vim.json.encode({
          version = 1,
          since = "2026-10-17",
          features = {
            ["n <P>tj"] = { count = 5, desc = "Add row below", last = "2026-10-17" },
            ["x <P>tJ"] = { count = 1, last = "2026-10-16" },
            [":Markwright table row"] = { count = 2, last = "2026-10-17" },
            ["i <T>b"] = { count = 4, last = "2026-10-17" },
            ["n <P>zz"] = { count = 1, last = "2026-10-17" },
          },
        }),
      }, usage.path())
      local d = usage.data()
      eq(d.version, 2)
      eq(d.since, "2026-10-17")
      eq(d.features["table.add_row"].count, 7)
      eq(d.features["table.add_row"].via, { key = 5, command = 2 })
      eq(d.features["table.move_row"].via, { visual = 1 })
      eq(d.features["format.bold"].via, { insert = 4 })
      eq(d.legacy["n <P>zz"].count, 1)
    end,
  },
  {
    "rows: last 30 days and all time; features never used are included",
    fn = function()
      at_day(-40)
      usage.record("table.sort", "key")
      at_day(0)
      usage.record("table.sort", "command")
      usage.record("table.sort", "command")
      local rows = usage.rows()
      local by = {}
      for _, r in ipairs(rows) do
        by[r.id] = r
      end
      eq(by["table.sort"].recent, 2)
      eq(by["table.sort"].total, 3)
      eq(by["table.sort"].area, "Tables")
      eq(by["table.transpose"].total, 0)
    end,
  },
  {
    "report helpers: bars, dates, how it was used",
    fn = function()
      eq(ui.bar(10, 10), "██████████")
      eq(ui.bar(5, 10), "█████")
      eq(ui.bar(1, 1000), "▏")
      eq(ui.bar(0, 10), "")
      at_day(0)
      eq(ui.relative(usage.today()), "today")
      at_day(1)
      eq(ui.relative(os.date("%Y-%m-%d", real_clock())), "yesterday")
      at_day(5)
      eq(ui.relative(os.date("%Y-%m-%d", real_clock())), "5 days ago")
      eq(ui.relative("2020-01-01"), "2020-01-01")
      eq(ui.relative(nil), "—")
      eq(ui.via_text({ key = 3 }), "key")
      eq(ui.via_text({ key = 3, command = 8, insert = 1 }), "cmd 8 · key 3 · ;; 1")
    end,
  },
  {
    "report: areas by use, features by use, never used folded, Automatic last",
    fn = function()
      for _ = 1, 5 do
        usage.record("list.checkbox", "key")
      end
      usage.record("table.add_row", "key")
      usage.record("table.sort", "key")
      usage.record("table.sort", "key")
      usage.record("list.continue", "insert")
      local rows, data = usage.rows()
      local out = table.concat(ui.render(rows, data, ui.state, 100), "\n")
      local lists, tables = out:find("\n Lists "), out:find("\n Tables ")
      local auto = out:find("\n Automatic ")
      assert(lists and tables and auto and lists < tables and tables < auto, out)
      local sort, add = out:find("Sort table", tables, true), out:find("Add row", tables, true)
      assert(sort < add, out)
      assert(out:find("never used: Add column, Align table", tables, true), out)
      assert(out:find("Toggle checkbox%s+██████████"), out)
      assert(out:find("Continue list", auto, true), out)
      -- automatic uses are counted apart, and drawn against each other
      assert(out:find("last 30 days: 8 uses of 3 features · all time: 8 · automatic: 1", 1, true), out)
      assert(out:find("Continue list[^\n]*██████████"), out)
      assert(not out:find("\n Headings +0"), out) -- unused areas have no numbers
    end,
  },
  {
    "report: flat list, name sort, unused as rows",
    fn = function()
      usage.record("table.add_row", "key")
      usage.record("list.checkbox", "key")
      usage.record("list.checkbox", "key")
      local rows, data = usage.rows()
      local flat = table.concat(ui.render(rows, data, { sort = "recent", grouped = false }, 100), "\n")
      assert(not flat:find("\n Tables "), flat)
      assert(flat:find("Toggle checkbox", 1, true) < flat:find("Add row", 1, true), flat)
      assert(flat:find("\n Never used", 1, true), flat)
      assert(flat:find("\n   Tables: Add column", 1, true), flat)
      local by_name = table.concat(ui.render(rows, data, { sort = "name", grouped = false }, 100), "\n")
      assert(by_name:find("Add row", 1, true) < by_name:find("Toggle checkbox", 1, true), by_name)
      local unused =
        table.concat(ui.render(rows, data, { sort = "recent", grouped = true, unused_rows = true }, 100), "\n")
      assert(unused:find("Transpose table%s+never"), unused)
    end,
  },
  {
    ":Markwright usage opens a floating window with its own keys",
    fn = function()
      H.buf(TABLE, { 3, 2 })
      H.feed(" mtj")
      vim.cmd("Markwright usage")
      local win = api.nvim_get_current_win()
      eq(api.nvim_win_get_config(win).relative, "editor")
      eq(vim.bo.filetype, "markwright-usage")
      eq(vim.b.markwright_attached, nil) -- not Markdown: markwright isn't there
      local row = ui._at[api.nvim_win_get_cursor(0)[1]]
      eq(row.id, "table.add_row") -- starts on the first feature
      local text = table.concat(lines(), "\n")
      assert(text:find("Add row", 1, true), text)
      H.feed("s")
      eq(ui.state.sort, "total")
      H.feed("a")
      eq(ui.state.grouped, false)
      H.feed("u")
      eq(ui.state.unused_rows, true)
      H.feed("jjj]]")
      eq(count("nav.heading"), 0) -- moving in the report doesn't count
      H.feed("q")
      eq(api.nvim_win_is_valid(win), false)
      eq(vim.fn.getcompletion("Markwright usage ", "cmdline"), { "reset" })
    end,
  },
  {
    "<CR> opens the feature's README section, read-only",
    fn = function()
      usage.record("table.add_row", "key")
      vim.cmd("Markwright usage")
      local l
      for i, r in pairs(ui._at) do
        if r.id == "table.add_row" then
          l = i
        end
      end
      api.nvim_win_set_cursor(0, { l, 0 })
      H.feed("<CR>")
      eq(vim.fn.fnamemodify(api.nvim_buf_get_name(0), ":t"), "README.md")
      eq(api.nvim_get_current_line(), "### Editing")
      eq(vim.bo.readonly, true)
      vim.cmd("bwipeout")
    end,
  },
  {
    "the first count tells the user, once",
    fn = function()
      vim.wait(20) -- run notices scheduled by earlier tests
      local msgs = {}
      local real = vim.notify
      vim.notify = function(m)
        table.insert(msgs, m)
      end
      usage._noticed = false
      usage.record("toc", "key")
      usage.record("toc", "key")
      vim.wait(100, function()
        return #msgs > 0
      end)
      vim.notify = real
      eq(#msgs, 1)
      assert(msgs[1]:find("local file only", 1, true), msgs[1])
      -- not when the file already exists
      usage.flush()
      usage._noticed = false
      msgs = {}
      vim.notify = function(m)
        table.insert(msgs, m)
      end
      usage.record("toc", "key")
      vim.wait(50, function()
        return #msgs > 0
      end)
      vim.notify = real
      eq(#msgs, 0)
    end,
  },
  {
    "reset keeps a backup",
    fn = function()
      usage.record("toc", "key")
      usage.flush()
      vim.cmd("Markwright usage reset")
      eq(count("toc"), 0)
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
        usage.record("table.add_row", "key")
        eq(usage._pending, {})
        eq(usage.flush(), true)
        eq(vim.fn.filereadable(usage.path()), 0)
        local wins = #api.nvim_list_wins()
        vim.cmd("Markwright usage")
        eq(#api.nvim_list_wins(), wins)
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
