-- Word count / reading time specs (SPEC.md section 14.20).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local stats = require("markwright.stats")
local eq = H.eq

local function words(text)
  return (stats.count_text(stats.clean(text)))
end

local function count(lines, range)
  H.buf(lines, { 1, 0 })
  return stats.count(0, range)
end

local cases = {
  -- words in plain text
  {
    "words and characters",
    fn = function()
      eq({ stats.count_text("Hello  world") }, { 2, 11 })
      eq(words("don't well-known 3.14 15:30"), 4)
      eq(words("don’t stop"), 2)
      eq(words("a — b, c"), 3)
      eq(words("a—b"), 2)
      eq(words("Ünïcödé café"), 2)
      eq(words("日本語のテキスト"), 8)
      eq(words("— ✅ 🎉 -- ..."), 0)
    end,
  },
  -- markup
  {
    "markup isn't counted",
    fn = function()
      eq(stats.clean("**bold** and *it* `code` ~~gone~~ ==hl=="), "bold and it code gone hl")
      eq(stats.clean("see [the docs](https://x.io/a_b) now"), "see the docs now")
      eq(stats.clean("see [the docs][ref] now"), "see the docs now")
      eq(stats.clean("![alt text](a.png) caption"), "caption")
      eq(stats.clean("## Heading two ##"), "Heading two")
      eq(stats.clean("> > - [ ] quoted task"), "quoted task")
      eq(stats.clean("> [!NOTE] Title"), "Title")
      eq(stats.clean("1. numbered"), "numbered")
      eq(stats.clean("snake_case_word and _emph_ __strong__"), "snake_case_word and emph strong")
      eq(words("visit https://example.com or www.x.io or <https://a.b>"), 3)
      eq(words("Task [2/3] [50%] done[^1]"), 2)
      eq(words("<span>hi</span> &nbsp; <!-- note --> x"), 2)
      eq(words("[^1]: The note text"), 3)
      eq(words("- [x] task done ✅ 2026-10-02 15:52"), 2)
      eq(stats.clean("| a | b \\| c |", true), "a   b | c")
    end,
  },
  -- buffers
  {
    "code, front matter, HTML and definitions are skipped",
    fn = function()
      local s = count({
        "---",
        "title: Not counted",
        "---",
        "",
        "# Title",
        "",
        "Two words.",
        "",
        "```lua",
        "local not_counted = true",
        "```",
        "",
        "    indented code here",
        "",
        "<div>",
        "html block",
        "</div>",
        "",
        "[ref]: https://x.io",
        "",
        "***",
        "",
        "| Col | Two |",
        "| --- | --- |",
        "| one | x   |",
      })
      eq(s.words, 1 + 2 + 2 + 2) -- Title, Two words, Col Two, one x
    end,
  },
  {
    "reading time rounds up, configurable speed",
    fn = function()
      local text = string.rep("word ", 450)
      eq(count({ text }).reading_minutes, 3)
      config.options.stats.wpm = 300
      eq(count({ text }).reading_minutes, 2)
      config.options.stats.wpm = 200
      eq(count({ "" }).reading_minutes, 0)
      eq(count({ "one" }).reading_minutes, 1)
    end,
  },
  {
    "line range and character range",
    fn = function()
      local lines = { "one two three", "```", "x y", "```", "four five" }
      eq(count(lines, { 0, 0 }).words, 3)
      eq(count(lines, { 0, 4 }).words, 5)
      eq(count(lines, { 0, 4, 4, 4 }).words, 3) -- "two three" … "four"
      eq(count(lines, { 0, 4 }).selection, true)
    end,
  },
  {
    "visual selection",
    fn = function()
      H.buf({ "one two three", "four five six" }, { 1, 4 })
      local got
      vim.keymap.set("x", "<F2>", function()
        got = require("markwright").stats()
      end, { buffer = true })
      H.feed("ve<F2><Esc>")
      eq({ got.words, got.selection }, { 1, true })
      H.feed("Vj<F2><Esc>")
      eq(got.words, 6)
      H.feed("gg0<C-v>j$<F2><Esc>")
      eq(got.words, 6)
      eq(require("markwright").stats().selection, nil)
    end,
  },
  {
    "cache follows edits",
    fn = function()
      H.buf({ "one two" }, { 1, 0 })
      eq(stats.count(0).words, 2)
      api.nvim_buf_set_lines(0, 0, -1, false, { "one two three" })
      eq(stats.count(0).words, 3)
    end,
  },
  {
    "statusline",
    fn = function()
      H.buf({ string.rep("word ", 401) }, { 1, 0 })
      eq(stats.statusline(), "401 words · 3 min")
      api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("w ", 1234) })
      eq(stats.statusline(), "1,234 words · 7 min")
      local plain = api.nvim_create_buf(true, true)
      api.nvim_set_current_buf(plain)
      eq(stats.statusline(), "")
    end,
  },
  {
    ":Markwright stats",
    fn = function()
      H.buf({ "one two", "three" }, { 1, 0 })
      local msgs = {}
      local real = vim.notify
      vim.notify = function(m)
        table.insert(msgs, m)
      end
      vim.cmd("Markwright stats")
      vim.cmd("2Markwright stats")
      vim.notify = real
      eq(msgs, {
        "markwright: 3 words · 12 characters · 1 min read",
        "markwright: lines 2–2: 1 word · 5 characters · 1 min read",
      })
      eq(vim.tbl_contains(vim.fn.getcompletion("Markwright st", "cmdline"), "stats"), true)
    end,
  },
  {
    "invalid wpm",
    fn = function()
      local saved = config.options
      eq(pcall(config.setup, { stats = { wpm = 0 } }), false)
      eq(pcall(config.setup, { stats = { wpm = "fast" } }), false)
      config.options = saved
    end,
  },
}

return H.run("stats", cases)
