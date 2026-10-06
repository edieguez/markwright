-- Word count and reading time. Spec: SPEC.md section 14.20.
--
-- Counts the prose a reader sees: front matter, code blocks, HTML blocks,
-- link and image destinations, bare URLs, reference definitions and Markdown
-- markup are left out. Per-line counts are cached per changedtick, so the
-- statusline component stays cheap.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")

local M = {}

-- Blocks that aren't prose, by tree-sitter node type.
local SKIP = {
  minus_metadata = true,
  plus_metadata = true,
  fenced_code_block = true,
  indented_code_block = true,
  html_block = true,
  pipe_table_delimiter_row = true,
  link_reference_definition = true,
  thematic_break = true,
  setext_h1_underline = true,
  setext_h2_underline = true,
}

-- Nodes that never contain any of the above: not descended into.
local LEAF = { paragraph = true, inline = true, atx_heading = true, block_continuation = true }

-- Words ---------------------------------------------------------------------------

--- Codepoints written without spaces between words: each one counts as a word.
local function is_cjk(cp)
  return (cp >= 0x3040 and cp <= 0x30FF) -- kana
    or (cp >= 0x3400 and cp <= 0x4DBF)
    or (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0xF900 and cp <= 0xFAFF)
    or (cp >= 0x20000 and cp <= 0x2FA1F)
end

--- Non-ASCII codepoints that are punctuation or symbols, not letters.
local function is_symbol(cp)
  return (cp >= 0x80 and cp <= 0xBF)
    or cp == 0xD7
    or cp == 0xF7
    or (cp >= 0x2000 and cp <= 0x2BFF) -- punctuation, arrows, math, dingbats, ✅
    or (cp >= 0x2E00 and cp <= 0x2E7F)
    or (cp >= 0x3000 and cp <= 0x303F) -- CJK punctuation
    or (cp >= 0xFE00 and cp <= 0xFE6F)
    or (cp >= 0xFF00 and cp <= 0xFF0F)
    or (cp >= 0xFF1A and cp <= 0xFF20)
    or (cp >= 0x1F000 and cp <= 0x1FAFF) -- emoji
end

local function codepoint(ch)
  local b = { ch:byte(1, -1) }
  if #b == 1 then
    return b[1]
  elseif #b == 2 then
    return (b[1] % 0x20) * 0x40 + b[2] % 0x40
  elseif #b == 3 then
    return (b[1] % 0x10) * 0x1000 + (b[2] % 0x40) * 0x40 + b[3] % 0x40
  end
  return (b[1] % 0x08) * 0x40000 + (b[2] % 0x40) * 0x1000 + (b[3] % 0x40) * 0x40 + (b[4] or 0) % 0x40
end

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

--- Words and characters in plain text (already cleaned of markup).
---@return integer words, integer chars
function M.count_text(text)
  local words, chars = 0, 0
  for token in text:gmatch("%S+") do
    local in_word = false
    for ch in token:gmatch(CHAR) do
      chars = chars + 1
      local cp = codepoint(ch)
      if cp >= 0x80 and is_cjk(cp) then
        words = words + 1
        in_word = false
      elseif (cp < 0x80 and ch:match("[%w]")) or (cp >= 0x80 and not is_symbol(cp)) then
        if not in_word then
          words = words + 1
          in_word = true
        end
      elseif ch ~= "’" and not (cp < 0x80 and ch:match("['_%-%.,:/]")) then
        -- symbols split words (a—b is two); apostrophes, hyphens and
        -- decimal points don't (don't, well-known, 3.14, 15:30)
        in_word = false
      end
    end
  end
  for _ in text:gmatch("%S%s+%f[%S]") do
    chars = chars + 1 -- one space between words
  end
  return words, chars
end

-- Markup --------------------------------------------------------------------------

--- The prose on one line, without Markdown markup, URLs or HTML.
---@param in_table? boolean the line is a table row (pipes separate cells)
function M.clean(line, in_table)
  local s = line
  -- block prefixes
  repeat
    local before = s
    s = s:gsub("^%s*>%s?", "")
  until s == before
  local item = s:match("^%s*[-*+]%s") or s:match("^%s*%d+[.)]%s")
  s = s:gsub("^%s*[-*+]%s+", ""):gsub("^%s*%d+[.)]%s+", "")
  if item and s:match("^%[[ xX%-]%]") then
    -- a completion stamp (`✅ 2026-10-02 15:52`) isn't prose
    local lists = require("markwright.lists")
    local fmt = config.options.lists.done_date
    s = lists.strip_stamp(s, fmt or nil) or s
  end
  s = s:gsub("^%[[ xX%-]%]%s+", "")
  s = s:gsub("^%s*#+%s+", ""):gsub("%s+#+%s*$", "")
  s = s:gsub("^%s*%[%^[^%]]+%]:%s*", "") -- footnote definition label
  s = s:gsub("^%s*%[!%a+%]%s*", "") -- callout marker
  -- HTML
  s = s:gsub("<!%-%-.-%-%->", " "):gsub("<!%-%-.*$", " ")
  s = s:gsub("</?%a[%w-]*[^>]*>", " ")
  s = s:gsub("&%a+;", " "):gsub("&#%w+;", " ")
  -- images (not read), then links (their text is)
  s = s:gsub("!%[[^%]]*%]%b()", " "):gsub("!%[[^%]]*%]%[[^%]]*%]", " ")
  s = s:gsub("%[([^%]]*)%]%b()", "%1"):gsub("%[([^%]^][^%]]*)%]%[[^%]]*%]", "%1")
  s = s:gsub("<%a[%w+.-]*:[^>%s]*>", " "):gsub("<[^>@%s]+@[^>%s]+>", " ")
  s = s:gsub("%[%^[^%]]+%]", " ") -- footnote references
  s = s:gsub("%[%d*/%d*%]", " "):gsub("%[%d*%%%]", " ") -- progress cookies
  s = s:gsub("%a[%w+.-]*://%S+", " "):gsub("www%.%S+", " ")
  -- inline markers
  if in_table then
    s = s:gsub("\\|", "\1"):gsub("|", " "):gsub("\1", "|")
  end
  s = s:gsub("\\(%p)", "%1")
  s = s:gsub("`+", ""):gsub("%*+", ""):gsub("~~", ""):gsub("==", "")
  s = (" " .. s .. " "):gsub("([%s%p])_+", "%1"):gsub("_+([%s%p])", "%1")
  return vim.trim(s)
end

-- Buffer --------------------------------------------------------------------------

---@type table<integer, { tick: integer, kind: table<integer, string>, words: integer[], chars: integer[], total_w: integer, total_c: integer, memo: table<string, integer[]> }>
local cache = {}

--- Line kinds from the syntax tree: "skip" (not prose) or "table" (a table
--- row); other lines are prose. 0-based rows.
local function kinds(buf, n)
  local kind = {}
  local p = ts.parser(buf)
  local tree = p and p:parse()[1]
  if not tree then
    return kind
  end
  local function walk(node)
    local t = node:type()
    local sr, _, er, ec = node:range()
    if ec == 0 and er > sr then
      er = er - 1
    end
    if SKIP[t] then
      -- `[^1]: text` is parsed as a reference definition, but it's a footnote
      local footnote = t == "link_reference_definition"
        and (api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""):match("^%s*%[%^")
      if not footnote then
        for r = sr, math.min(er, n - 1) do
          kind[r] = "skip"
        end
        return
      end
    elseif t == "pipe_table_header" or t == "pipe_table_row" then
      kind[sr] = kind[sr] or "table"
      return
    end
    if not LEAF[t] then
      for c in node:iter_children() do
        walk(c)
      end
    end
  end
  walk(tree:root())
  return kind
end

local function data(buf)
  local tick = api.nvim_buf_get_changedtick(buf)
  local d = cache[buf]
  if d and d.tick == tick then
    return d
  end
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local kind = kinds(buf, #lines)
  -- counts by line text from the previous pass: while typing, only the
  -- edited lines are counted again
  local memo, seen = d and d.memo or {}, {}
  d = { tick = tick, kind = kind, words = {}, chars = {}, total_w = 0, total_c = 0 }
  for i, line in ipairs(lines) do
    local r = i - 1
    local w, c = 0, 0
    if kind[r] ~= "skip" then
      local key = (kind[r] == "table" and "|" or " ") .. line
      local m = seen[key] or memo[key]
      if not m then
        m = { M.count_text(M.clean(line, kind[r] == "table")) }
      end
      seen[key] = m
      w, c = m[1], m[2]
    end
    d.words[r], d.chars[r] = w, c
    d.total_w, d.total_c = d.total_w + w, d.total_c + c
  end
  d.memo = seen
  cache[buf] = d
  return d
end

local function wpm()
  return config.options.stats.wpm
end

local function result(words, chars, selection)
  local minutes = words == 0 and 0 or math.ceil(words / wpm())
  return { words = words, chars = chars, reading_minutes = minutes, selection = selection or nil }
end

--- Counts for `buf`, or part of it.
---@param buf? integer
---@param range? { [1]: integer, [2]: integer, [3]: integer?, [4]: integer?, block: boolean? }
---  0-based rows {srow, erow}; with columns {srow, scol, erow, ecol} (byte
---  columns, ecol exclusive) the first and last lines are cut; with
---  `block = true` every line is cut to the same columns.
---@return { words: integer, chars: integer, reading_minutes: integer, selection: boolean? }
function M.count(buf, range)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  local d = data(buf)
  if not range then
    return result(d.total_w, d.total_c)
  end
  local srow, scol, erow, ecol = range[1], nil, range[2], nil
  if range[4] then
    srow, scol, erow, ecol = range[1], range[2], range[3], range[4]
  end
  local w, c = 0, 0
  for r = srow, erow do
    local cut = scol and (range.block or r == srow or r == erow)
    if not cut then
      w, c = w + (d.words[r] or 0), c + (d.chars[r] or 0)
    elseif d.kind[r] ~= "skip" then
      local line = api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""
      local from = (range.block or r == srow) and scol or 0
      local to = (range.block or r == erow) and ecol or #line
      local lw, lc = M.count_text(M.clean(line:sub(from + 1, to), d.kind[r] == "table"))
      w, c = w + lw, c + lc
    end
  end
  return result(w, c, true)
end

--- The visual selection of the current window as a `count()` range, or nil.
function M.visual_range()
  local mode = api.nvim_get_mode().mode
  local m = mode:sub(1, 1)
  if m ~= "v" and m ~= "V" and m ~= "\22" then
    return nil
  end
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then
    a, b = b, a
  end
  local srow, erow = a[2] - 1, b[2] - 1
  if m == "V" then
    return { srow, erow }
  end
  local scol, ecol = a[3] - 1, b[3]
  if m == "\22" then
    scol, ecol = math.min(a[3], b[3]) - 1, math.max(a[3], b[3])
  end
  -- include the whole last character
  local last = api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or ""
  local len = #(last:sub(ecol):match("^" .. CHAR) or "")
  ecol = ecol + math.max(len - 1, 0)
  return { srow, scol, erow, ecol, block = m == "\22" }
end

--- Counts for the current buffer, or its visual selection when one is active.
function M.get(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if buf == api.nvim_get_current_buf() then
    local range = M.visual_range()
    if range then
      return M.count(buf, range)
    end
  end
  return M.count(buf)
end

local function thousands(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

local function plural(n, word)
  return ("%s %s%s"):format(thousands(n), word, n == 1 and "" or "s")
end

--- Short text for a statusline: "1,234 words · 7 min", or "52 words
--- selected" in visual mode. Empty outside markwright buffers.
function M.statusline()
  local buf = api.nvim_get_current_buf()
  if not require("markwright")._attached[buf] then
    return ""
  end
  local s = M.get(buf)
  if s.selection then
    return plural(s.words, "word") .. " selected"
  end
  return ("%s · %d min"):format(plural(s.words, "word"), s.reading_minutes)
end

--- :Markwright stats (with a range: those lines).
function M.show(range)
  local s = M.count(0, range)
  local where = range and ("lines %d–%d: "):format(range[1] + 1, range[2] + 1) or ""
  local time = s.words == 0 and "nothing to read" or ("%d min read"):format(s.reading_minutes)
  require("markwright.util").notify(
    ("%s%s · %s · %s"):format(where, plural(s.words, "word"), plural(s.chars, "character"), time)
  )
end

function M._clear(buf)
  cache[buf] = nil
end

return M
