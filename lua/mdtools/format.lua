-- Formatting toggle engine: italic, bold, strikethrough, inline code, highlight.
-- Spec: SPEC.md section 6.
local api = vim.api
local config = require("mdtools.config")
local ts = require("mdtools.ts")
local util = require("mdtools.util")

local M = {}

---@class mdtools.FormatSpec
---@field node? string       Treesitter node type in markdown_inline
---@field outermost? boolean climb nested nodes of the same type (strikethrough parses `~~x~~` as nested)
---@field max_run? integer   max marker run length counted when removing

---@type table<string, mdtools.FormatSpec>
M.formats = {
  italic = { node = "emphasis", max_run = 1 },
  bold = { node = "strong_emphasis", max_run = 2 },
  strike = { node = "strikethrough", outermost = true, max_run = 2 },
  code = { node = "code_span" },
  highlight = {}, -- not in the grammar: text scan
}

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function marker_for(fmt)
  return config.options.format[fmt].marker
end

-- Removal ---------------------------------------------------------------

--- Length of the run of `ch` starting at 0-based `col`, capped at `max`.
local function run_len(line, col, ch, max)
  local n = 0
  while line:sub(col + n + 1, col + n + 1) == ch and (not max or n < max) do
    n = n + 1
  end
  return n
end

local function find_span_node(p, row, scol, ecol, spec)
  local types = { [spec.node] = true }
  local node = ts.ancestor(ts.inline_node(p, row, scol), types)
  if not node and ecol > scol then
    node = ts.ancestor(ts.inline_node(p, row, ecol - 1), types)
  end
  if node and spec.outermost then
    while node:parent() and node:parent():type() == spec.node do
      node = node:parent()
    end
  end
  return node
end

---@param tr mdtools.EditTracker
local function remove_node(buf, tr, node, spec)
  local sr, sc, er, ec = node:range()
  local first = get_line(buf, sr)
  local ch = first:sub(sc + 1, sc + 1)
  local n = run_len(first, sc, ch, spec.max_run)
  if n == 0 then
    return
  end
  util.set_text(buf, tr, er, ec - n, ec, "")
  util.set_text(buf, tr, sr, sc, sc + n, "")
  -- code spans escalated with padding: `` `a` `` -> `a`
  if spec.node == "code_span" and sr == er then
    local line = get_line(buf, sr)
    local content = line:sub(sc + 1, ec - 2 * n)
    if n > 1 and #content >= 2 and content:sub(1, 1) == " " and content:sub(-1) == " " and content:find("`", 1, true) then
      local cend = ec - 2 * n
      util.set_text(buf, tr, sr, cend - 1, cend, "")
      util.set_text(buf, tr, sr, sc, sc + 1, "")
    end
  end
end

--- `==x==` pairs on a line as 0-based {start, end_exclusive}.
local function highlight_spans(line)
  local spans, open, i = {}, nil, 1
  while true do
    local s = line:find("==", i, true)
    if not s then
      break
    end
    if open then
      table.insert(spans, { open - 1, s + 1 })
      open = nil
    else
      open = s
    end
    i = s + 2
  end
  return spans
end

--- Text-based removal: highlight always, other formats only without a parser.
local function text_remove(buf, tr, row, scol, ecol, fmt)
  local line = get_line(buf, row)
  if fmt == "highlight" then
    for _, sp in ipairs(highlight_spans(line)) do
      if (scol >= sp[1] and scol < sp[2]) or (ecol - 1 >= sp[1] and ecol - 1 < sp[2]) then
        util.set_text(buf, tr, row, sp[2] - 2, sp[2], "")
        util.set_text(buf, tr, row, sp[1], sp[1] + 2, "")
        return true
      end
    end
    return false
  end
  local m = marker_for(fmt)
  local ch = m:sub(1, 1)
  local n = #m
  -- markers inside the range: "*word*" selected
  local text = line:sub(scol + 1, ecol)
  if #text > 2 * n and text:sub(1, n) == m and text:sub(-n) == m
    and text:sub(n + 1, n + 1) ~= ch and text:sub(-n - 1, -n - 1) ~= ch then
    util.set_text(buf, tr, row, ecol - n, ecol, "")
    util.set_text(buf, tr, row, scol, scol + n, "")
    return true
  end
  -- markers just outside the range: *[word]*
  if line:sub(scol - n + 1, scol) == m and line:sub(ecol + 1, ecol + n) == m
    and line:sub(scol - n, scol - n) ~= ch and line:sub(ecol + n + 1, ecol + n + 1) ~= ch then
    util.set_text(buf, tr, row, ecol, ecol + n, "")
    util.set_text(buf, tr, row, scol - n, scol, "")
    return true
  end
  return false
end

-- Wrapping --------------------------------------------------------------

local function code_markers(text)
  local longest = 0
  for run in text:gmatch("`+") do
    longest = math.max(longest, #run)
  end
  if longest == 0 then
    local m = marker_for("code")
    return m, m
  end
  local fence = string.rep("`", longest + 1)
  local pad = (text:sub(1, 1) == "`" or text:sub(-1) == "`") and " " or ""
  return fence .. pad, pad .. fence
end

local function wrap(buf, tr, row, scol, ecol, fmt)
  local open, close
  if fmt == "code" then
    open, close = code_markers(get_line(buf, row):sub(scol + 1, ecol))
  else
    open = marker_for(fmt)
    close = open
  end
  util.set_text(buf, tr, row, ecol, ecol, close)
  util.set_text(buf, tr, row, scol, scol, open)
end

-- Segments --------------------------------------------------------------

--- Toggle `fmt` on one single-line segment [scol, ecol).
local function toggle_segment(buf, tr, fmt, row, scol, ecol, state)
  local spec = M.formats[fmt]
  local p = ts.parse(buf, row, row)
  local ctx = ts.code_context(p, row, scol)
  if ctx == "block" or (ctx == "span" and fmt ~= "code") then
    state.skipped = true
    return
  end
  if p and spec.node then
    local node = find_span_node(p, row, scol, ecol, spec)
    if node then
      remove_node(buf, tr, node, spec)
      return
    end
  elseif text_remove(buf, tr, row, scol, ecol, fmt) then
    return
  end
  wrap(buf, tr, row, scol, ecol, fmt)
end

--- Build per-line segments from a range. Columns are 0-based bytes;
--- `ecol` is inclusive (position of the last character, like marks).
local function segments(buf, mtype, srow, scol, erow, ecol)
  local segs = {}
  local trim = config.options.format.trim_whitespace
  for row = srow, erow do
    local line = get_line(buf, row)
    local a, b
    if mtype == "line" then
      a, b = 0, #line
    elseif mtype == "block" then
      local lo, hi = math.min(scol, ecol), math.max(scol, ecol)
      a, b = lo, hi + math.max(util.char_len(line, hi), 1)
    else
      a = (row == srow) and scol or 0
      b = (row == erow) and (ecol + math.max(util.char_len(line, ecol), 1)) or #line
    end
    a = math.max(0, math.min(a, #line))
    b = math.max(0, math.min(b, #line))
    a = math.max(a, util.prefix_len(line))
    if trim then
      while a < b and line:sub(a + 1, a + 1):match("%s") do
        a = a + 1
      end
      while b > a and line:sub(b, b):match("%s") do
        b = b - 1
      end
    end
    if b > a then
      table.insert(segs, { row, a, b })
    end
  end
  return segs
end

--- Toggle a format over a range. Rows/cols are 0-based, `ecol` inclusive.
---@param mtype "char"|"line"|"block"
function M.apply(buf, fmt, mtype, srow, scol, erow, ecol, cursor)
  local segs = segments(buf, mtype, srow, scol, erow, ecol)
  if #segs == 0 then
    return
  end
  local tr = util.tracker()
  local state = { skipped = false }
  util.undo_break(buf)
  for i = #segs, 1, -1 do -- bottom-up keeps rows valid
    local s = segs[i]
    toggle_segment(buf, tr, fmt, s[1], s[2], s[3], state)
  end
  if state.skipped and config.options.format.warn_in_code then
    util.warn("formatting skipped inside code")
  end
  if buf == api.nvim_get_current_buf() then
    local pos = cursor and { cursor[1] - 1, cursor[2] } or { segs[1][1], segs[1][2] }
    pos = tr:shift(pos)
    local line = get_line(buf, pos[1])
    api.nvim_win_set_cursor(0, { pos[1] + 1, math.max(0, math.min(pos[2], #line - 1)) })
  end
end

-- Operators / keymap entry points ---------------------------------------

M._pending = nil ---@type string?
M._cursor = nil ---@type integer[]?

function M.opfunc(mtype)
  local fmt = M._pending
  if not fmt then
    return
  end
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "[")
  local e = api.nvim_buf_get_mark(buf, "]")
  local cursor = M._cursor
  M._cursor = nil -- only the first run restores the cursor; dot-repeat lands on the text
  M.apply(buf, fmt, mtype, s[1] - 1, s[2], e[1] - 1, e[2], cursor)
end

local OPFUNC = "v:lua.require'mdtools.format'.opfunc"

--- Normal mode: word under cursor, or empty markers on whitespace.
function M.expr_normal(fmt)
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  local ch = line:sub(col + 1, col + 1)
  if ch == "" or ch:match("%s") then
    return ("<Cmd>lua require('mdtools.format').insert_empty(%q)<CR>"):format(fmt)
  end
  M._pending = fmt
  M._cursor = api.nvim_win_get_cursor(0)
  vim.o.operatorfunc = OPFUNC
  return "g@iw"
end

--- Operator (normal, awaits a motion) and visual mode.
function M.expr_operator(fmt)
  M._pending = fmt
  M._cursor = nil
  vim.o.operatorfunc = OPFUNC
  return "g@"
end

--- Insert an empty marker pair at the cursor and enter insert mode between them.
function M.insert_empty(fmt)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local ctx = ts.code_context(ts.parse(buf, row - 1), row - 1, col)
  if ctx then
    if config.options.format.warn_in_code then
      util.warn("formatting skipped inside code")
    end
    return
  end
  local m = marker_for(fmt)
  local at = (line == "") and 0 or col + 1 -- after the whitespace under the cursor
  local nextc = line:sub(at + 1, at + 1)
  local trail = (nextc ~= "" and not nextc:match("%s")) and " " or ""
  util.undo_break(buf)
  api.nvim_buf_set_text(buf, row - 1, at, row - 1, at, { m .. m .. trail })
  api.nvim_win_set_cursor(0, { row, at + #m })
  vim.cmd("startinsert")
end

--- Programmatic entry: toggle the word under the cursor (used by :Mdtools).
function M.toggle(fmt)
  local keys = api.nvim_replace_termcodes(M.expr_normal(fmt), true, false, true)
  api.nvim_feedkeys(keys, "nx", false)
end

return M
