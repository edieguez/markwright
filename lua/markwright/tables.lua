-- Tables: create, CSV → table, row/column edits, cell navigation, alignment.
-- Spec: SPEC.md section 9.4.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

-- Parsing -----------------------------------------------------------------

---@class markwright.Cell
---@field text string trimmed content
---@field rs integer raw segment start (0-based byte)
---@field re integer raw segment end (exclusive; the next pipe sits here)
---@field s integer trimmed content start

--- Split a table row into cells. Pipes escaped with `\|` stay in the cell.
---@return markwright.Cell[]
function M.split_row(line)
  local indent = #line:match("^%s*")
  local segs, start, k = {}, indent, indent + 1
  while k <= #line do
    local c = line:sub(k, k)
    if c == "\\" then
      k = k + 2
    elseif c == "|" then
      table.insert(segs, { start, k - 1 })
      start = k
      k = k + 1
    else
      k = k + 1
    end
  end
  table.insert(segs, { start, #line })
  if line:sub(indent + 1, indent + 1) == "|" then
    table.remove(segs, 1)
  end
  local last = segs[#segs]
  if
    #segs > 1
    and line:sub(last[1] + 1, last[2]):match("^%s*$")
    and line:sub(last[1], last[1]) == "|"
    and line:sub(last[1] - 1, last[1] - 1) ~= "\\"
  then
    table.remove(segs)
  end
  local cells = {}
  for _, sg in ipairs(segs) do
    local raw = line:sub(sg[1] + 1, sg[2])
    local lead = #raw:match("^%s*")
    table.insert(cells, { text = trim(raw), rs = sg[1], re = sg[2], s = sg[1] + lead })
  end
  return cells
end

local function align_of(t)
  local l, r = t:sub(1, 1) == ":", t:sub(-1) == ":"
  if l and r then
    return "center"
  elseif r then
    return "right"
  elseif l then
    return "left"
  end
  return "none"
end

--- Does `line` contain a pipe that isn't escaped?
local function has_pipe(line)
  local k = 1
  while true do
    local i = line:find("[|\\]", k)
    if not i then
      return false
    end
    if line:sub(i, i) == "|" then
      return true
    end
    k = i + 2
  end
end

--- Is `line` a delimiter row (`| --- | :-: |`)? Returns its cell count.
local function delimiter_cells(line)
  local cells = M.split_row(line)
  if #cells == 0 then
    return nil
  end
  for _, c in ipairs(cells) do
    if not c.text:match("^:?%-+:?$") then
      return nil
    end
  end
  return #cells
end

--- Does `line` start another block (which ends a table)?
local function block_start(line)
  return line:match("^%s*#")
    or line:match("^%s*```")
    or line:match("^%s*~~~")
    or line:match("^%s*>")
    or line:match("^%s*[-*+]%s")
    or line:match("^%s*%d+[.)]%s")
    or line:match("^%s*<")
end

--- Rows (0-based, inclusive) of the table containing `row`, or nil.
---
--- Found from the lines rather than the syntax tree: the tree-sitter grammar
--- takes a row of empty cells (`|   |`) after a body row for a delimiter row
--- (GFM requires at least one `-`), which splits a table in two, or makes it
--- an ERROR. A table is a run of non-blank lines with an unescaped `|`; its
--- header is the line above the first valid delimiter row whose cell count
--- matches it. Tree-sitter only rules out code blocks.
function M.find(buf, row)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  if not has_pipe(line) then
    return nil
  end
  local n = api.nvim_buf_line_count(buf)
  local function pipe_line(r)
    local l = api.nvim_buf_get_lines(buf, r, r + 1, false)[1]
    return l and not l:match("^%s*$") and has_pipe(l)
  end
  -- up through the lines a table can hold (one-cell rows have no pipe),
  -- down through the pipe lines that may hold the header and delimiter
  local top, last = row, row
  while top > 0 do
    local l = api.nvim_buf_get_lines(buf, top - 1, top, false)[1]
    if l:match("^%s*$") or (not has_pipe(l) and block_start(l)) then
      break
    end
    top = top - 1
  end
  while last < n - 1 and pipe_line(last + 1) do
    last = last + 1
  end
  local lines = api.nvim_buf_get_lines(buf, top, last + 1, false)
  local header
  for i = 2, #lines do
    local cells = delimiter_cells(lines[i])
    if cells and #M.split_row(lines[i - 1]) == cells then
      header = top + i - 2
      break
    end
  end
  if not header or row < header then
    return nil
  end
  -- as in GFM, the body goes on until a blank line or another block, even
  -- through lines without a pipe (a one-cell row)
  local bottom = header + 1
  while bottom < n - 1 do
    local l = api.nvim_buf_get_lines(buf, bottom + 1, bottom + 2, false)[1]
    if l:match("^%s*$") or (not has_pipe(l) and block_start(l)) then
      break
    end
    bottom = bottom + 1
  end
  local p = ts.parse(buf, header, bottom)
  if p and ts.code_context(p, header, #line:match("^%s*")) == "block" then
    return nil
  end
  return header, bottom
end

---@class markwright.Table
---@field sr integer
---@field er integer
---@field indent string
---@field rows string[][] cell texts; rows[2] is the delimiter row
---@field aligns string[]

---@return markwright.Table?
function M.read(buf, sr, er)
  local lines = api.nvim_buf_get_lines(buf, sr, er + 1, false)
  local t = { sr = sr, er = er, indent = lines[1]:match("^%s*"), rows = {}, aligns = {} }
  for i, l in ipairs(lines) do
    local texts = {}
    for _, c in ipairs(M.split_row(l)) do
      table.insert(texts, c.text)
    end
    t.rows[i] = texts
  end
  for c, txt in ipairs(t.rows[2] or {}) do
    t.aligns[c] = align_of(txt)
  end
  return t
end

-- Rendering ---------------------------------------------------------------

local function ncols(t)
  local n = #t.aligns
  for _, r in ipairs(t.rows) do
    n = math.max(n, #r)
  end
  return math.max(n, 1)
end

local function pad(text, w, align)
  local gap = w - width(text)
  if gap <= 0 then
    return text
  end
  if align == "right" then
    return string.rep(" ", gap) .. text
  elseif align == "center" then
    local l = math.floor(gap / 2)
    return string.rep(" ", l) .. text .. string.rep(" ", gap - l)
  end
  return text .. string.rep(" ", gap)
end

local function delim(w, align)
  if align == "left" then
    return ":" .. string.rep("-", w - 1)
  elseif align == "right" then
    return string.rep("-", w - 1) .. ":"
  elseif align == "center" then
    return ":" .. string.rep("-", w - 2) .. ":"
  end
  return string.rep("-", w)
end

--- Render a table. Returns lines and, per row, the byte column where each
--- cell's content starts (plus content byte length).
---@return string[] lines, {s: integer, len: integer}[][] cells
function M.render(t)
  local n = ncols(t)
  local widths = {}
  for c = 1, n do
    widths[c] = 3
    t.aligns[c] = t.aligns[c] or "none"
  end
  for i, r in ipairs(t.rows) do
    if i ~= 2 then
      for c = 1, n do
        widths[c] = math.max(widths[c], width(r[c] or ""))
      end
    end
  end
  local lines, pos = {}, {}
  for i, r in ipairs(t.rows) do
    local parts, cells = {}, {}
    local col = #t.indent + 2
    for c = 1, n do
      local text = r[c] or ""
      local cell
      if i == 2 then
        cell = delim(widths[c], t.aligns[c])
        cells[c] = { s = col, len = 0 }
      else
        cell = pad(text, widths[c], t.aligns[c])
        local lead = text == "" and 0 or #cell:match("^%s*")
        cells[c] = { s = col + lead, len = #text }
      end
      parts[c] = cell
      col = col + #cell + 3
    end
    lines[i] = t.indent .. "| " .. table.concat(parts, " | ") .. " |"
    pos[i] = cells
  end
  return lines, pos
end

--- Write a table back (only if changed). `cur` = {row_index, col_index, offset}
--- places the cursor inside that cell afterwards.
local function write(buf, t, cur, opts)
  local lines, pos = M.render(t)
  local old = api.nvim_buf_get_lines(buf, t.sr, t.er + 1, false)
  if not vim.deep_equal(old, lines) then
    if opts and opts.join then
      pcall(vim.cmd, "undojoin")
    elseif not (opts and opts.no_break) then
      util.undo_break(buf)
    end
    api.nvim_buf_set_lines(buf, t.sr, t.er + 1, false, lines)
  end
  t.er = t.sr + #lines - 1
  if cur and buf == api.nvim_get_current_buf() then
    local i = math.max(1, math.min(cur[1], #lines))
    local cells = pos[i]
    local c = math.max(1, math.min(cur[2], #cells))
    local cell = cells[c]
    local off = cur[3] == "end" and cell.len or math.min(cur[3] or 0, cell.len)
    api.nvim_win_set_cursor(0, { t.sr + i, cell.s + off })
  end
  return lines, pos
end

--- Which cell the cursor is in: row index (1-based in table), column index, offset.
local function cursor_cell(buf, t)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local i = row - t.sr
  local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local cells = M.split_row(line)
  if #cells == 0 then
    return i, 1, 0
  end
  local c = #cells
  for idx, cell in ipairs(cells) do
    if col < cell.re then
      c = idx
      break
    end
  end
  if col < cells[1].rs then
    c = 1
  end
  local off = math.max(0, col - cells[c].s)
  return i, c, off
end

local function current(buf)
  buf = buf or api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local sr, er = M.find(buf, row)
  if not sr then
    return nil
  end
  return M.read(buf, sr, er), buf
end

-- Commands ----------------------------------------------------------------

--- Align the table under the cursor, keeping the cursor in its cell.
function M.align(opts)
  local t, buf = current()
  if not t then
    if not (opts and opts.silent) then
      util.warn("not in a table")
    end
    return
  end
  local i, c, off = cursor_cell(buf, t)
  write(buf, t, { i, c, off }, opts)
end

local function empty_row(n)
  local r = {}
  for c = 1, n do
    r[c] = ""
  end
  return r
end

--- Build a table from rows of cell texts (first row = header) and insert it.
local function insert_table(buf, row, rows, replace)
  local n = 0
  for _, r in ipairs(rows) do
    n = math.max(n, #r)
  end
  local t = { indent = "", aligns = {}, rows = {} }
  table.insert(t.rows, rows[1])
  table.insert(t.rows, empty_row(n))
  for k = 2, #rows do
    table.insert(t.rows, rows[k])
  end
  local lines = M.render(t)
  util.undo_break(buf)
  if replace then
    api.nvim_buf_set_lines(buf, row, replace, false, lines)
  else
    api.nvim_buf_set_lines(buf, row, row, false, lines)
  end
  t.sr, t.er = row, row + #lines - 1
  return t
end

--- Prompt "rows x cols" and insert an empty table below the cursor.
function M.create()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  if ts.code_context(ts.parse(buf, row), row, 0) then
    return util.warn("tables skipped inside code")
  end
  util.input({ prompt = "Table size (rows x cols): ", default = "2x3" }, function(input)
    if not input then
      return
    end
    local r, c = input:match("^%s*(%d+)%s*[xX×*, ]%s*(%d+)%s*$")
    r, c = tonumber(r), tonumber(c)
    if not r or not c or r < 0 or c < 1 then
      return util.warn("expected a size like 3x4")
    end
    local rows = { empty_row(c) }
    for _ = 1, r do
      table.insert(rows, empty_row(c))
    end
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local at, replace = row + 1, nil
    if line:match("^%s*$") then
      at, replace = row, row + 1
    end
    local t = insert_table(buf, at, rows, replace)
    local _, pos = M.render(t)
    api.nvim_win_set_cursor(0, { t.sr + 1, pos[1][1].s })
    vim.cmd("startinsert")
  end)
end

--- Parse one CSV/TSV line (quotes and "" escapes supported).
function M.csv_fields(line, sep)
  local out, field, i, inq = {}, "", 1, false
  while i <= #line do
    local ch = line:sub(i, i)
    if inq then
      if ch == '"' then
        if line:sub(i + 1, i + 1) == '"' then
          field = field .. '"'
          i = i + 1
        else
          inq = false
        end
      else
        field = field .. ch
      end
    elseif ch == '"' and field:match("^%s*$") then
      inq, field = true, ""
    elseif line:sub(i, i + #sep - 1) == sep then
      table.insert(out, field)
      field = ""
      i = i + #sep - 1
    else
      field = field .. ch
    end
    i = i + 1
  end
  table.insert(out, field)
  for k, f in ipairs(out) do
    out[k] = trim(f):gsub("|", "\\|")
  end
  return out
end

--- Most frequent separator in the line (outside quotes): tab, comma, semicolon.
M.SEP_CANDIDATES = { "\t", ",", ";", "|", ":" }

--- Guess the separator of CSV-like lines (a string or a list of lines).
--- Prefers a candidate that splits every line into the same number (> 1) of
--- fields, the most fields first; otherwise the one that splits the first line
--- the most. Falls back to ",".
function M.detect_sep(lines)
  if type(lines) == "string" then
    lines = { lines }
  end
  local best, best_n = nil, 1
  for _, sep in ipairs(M.SEP_CANDIDATES) do
    local n, consistent = nil, true
    for _, l in ipairs(lines) do
      local c = #M.csv_fields(l, sep)
      if n == nil then
        n = c
      elseif c ~= n then
        consistent = false
        break
      end
    end
    if consistent and n and n > best_n then
      best, best_n = sep, n
    end
  end
  if best then
    return best
  end
  best, best_n = ",", 1
  for _, sep in ipairs(M.SEP_CANDIDATES) do
    local c = #M.csv_fields(lines[1] or "", sep)
    if c > best_n then
      best, best_n = sep, c
    end
  end
  return best
end

--- Convert rows srow..erow (0-based, inclusive) of CSV/TSV into a table.
local function non_blank(buf, srow, erow)
  local src = {}
  for _, l in ipairs(api.nvim_buf_get_lines(buf, srow, erow + 1, false)) do
    if not l:match("^%s*$") then
      table.insert(src, l)
    end
  end
  return src
end

--- Convert rows srow..erow (0-based, inclusive) of CSV-like text into a table,
--- split on `sep` (detected when nil).
function M.from_csv(buf, srow, erow, sep)
  local src = non_blank(buf, srow, erow)
  if #src == 0 then
    return
  end
  sep = sep or M.detect_sep(src)
  local rows = {}
  for _, l in ipairs(src) do
    table.insert(rows, M.csv_fields(l, sep))
  end
  local t = insert_table(buf, srow, rows, erow + 1)
  if buf == api.nvim_get_current_buf() then
    api.nvim_win_set_cursor(0, { t.sr + 1, #t.indent })
  end
end

--- Ask for the separator (prefilled with the detected one), then convert.
function M.from_csv_prompt(buf, srow, erow)
  local src = non_blank(buf, srow, erow)
  if #src == 0 then
    return
  end
  local detected = M.detect_sep(src)
  local shown = detected == "\t" and "\\t" or detected
  local ns = api.nvim_create_namespace("markwright_fromcsv")
  local id = api.nvim_buf_set_extmark(buf, ns, srow, 0, { end_row = erow, end_col = 0, right_gravity = false })
  util.input({ prompt = "Separator: ", default = shown }, function(input)
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
    pcall(api.nvim_buf_del_extmark, buf, ns, id)
    if input == nil or not m[1] then
      return
    end
    M.from_csv(buf, m[1], m[3].end_row, M.parse_sep(input) or detected)
  end)
end

--- <P>tc in normal mode: convert the paragraph (non-blank lines) around the cursor.
function M.from_csv_paragraph()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local function blank(r)
    return (api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""):match("^%s*$") ~= nil
  end
  if blank(row) then
    return
  end
  local sr, er, last = row, row, api.nvim_buf_line_count(buf) - 1
  while sr > 0 and not blank(sr - 1) do
    sr = sr - 1
  end
  while er < last and not blank(er + 1) do
    er = er + 1
  end
  M.from_csv_prompt(buf, sr, er)
end

function M.from_csv_visual()
  local buf = api.nvim_get_current_buf()
  M.from_csv_prompt(buf, api.nvim_buf_get_mark(buf, "<")[1] - 1, api.nvim_buf_get_mark(buf, ">")[1] - 1)
end

--- Interpret a typed separator: "\t" or "tab" mean a tab; empty means nil.
function M.parse_sep(input)
  if input == nil or input == "" then
    return nil
  end
  if input == "\\t" or input:lower() == "tab" then
    return "\t"
  end
  return input
end

--- One CSV field: quoted when it contains the separator, a quote, or
--- leading/trailing spaces (RFC 4180 style, quotes doubled).
function M.csv_field(text, sep)
  text = text:gsub("\\|", "|") -- markdown escape, not part of the value
  if text:find(sep, 1, true) or text:find('"', 1, true) or text:match("^%s") or text:match("%s$") then
    return '"' .. text:gsub('"', '""') .. '"'
  end
  return text
end

--- CSV lines for a table model (delimiter row dropped, short rows padded).
function M.to_csv_lines(t, sep)
  local n = ncols(t)
  local out = {}
  for i, r in ipairs(t.rows) do
    if i ~= 2 then
      local fields = {}
      for c = 1, n do
        fields[c] = M.csv_field(r[c] or "", sep)
      end
      table.insert(out, t.indent .. table.concat(fields, sep))
    end
  end
  return out
end

--- Replace the table under the cursor with CSV, asking for the separator
--- (prefilled with `tables.csv_separator`). The opposite of from_csv().
function M.to_csv()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local default = config.options.tables.csv_separator
  local shown = default == "\t" and "\\t" or default
  local sr, er = t.sr, t.er
  local ns = api.nvim_create_namespace("markwright_tocsv")
  local id = api.nvim_buf_set_extmark(buf, ns, sr, 0, { end_row = er, end_col = 0, right_gravity = false })
  util.input({ prompt = "Separator: ", default = shown }, function(input)
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
    pcall(api.nvim_buf_del_extmark, buf, ns, id)
    if input == nil or not m[1] then
      return
    end
    local sep = M.parse_sep(input) or default
    local fresh = M.read(buf, m[1], m[3].end_row)
    local lines = M.to_csv_lines(fresh, sep)
    util.undo_break(buf)
    api.nvim_buf_set_lines(buf, fresh.sr, fresh.er + 1, false, lines)
    if buf == api.nvim_get_current_buf() then
      api.nvim_win_set_cursor(0, { fresh.sr + 1, #fresh.indent })
    end
  end)
end

--- Add an empty row below the cursor (below the delimiter when on the header),
--- or above it with `above = true` (not above the header: a table's first row
--- is always its header).
--- Add [count] empty rows below the cursor's row, or above it with `above = true`.
function M.add_row(above, n)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  n = n or util.count1()
  local i, c = cursor_cell(buf, t)
  if above and i <= 2 then
    return util.warn("can't add a row above the header")
  end
  local at = above and i or math.max(i, 2) + 1
  for _ = 1, n do
    table.insert(t.rows, at, empty_row(ncols(t)))
  end
  write(buf, t, { at, c, 0 })
end

--- Body rows `i1`..`i2` (model indices, the header is 1), clamped; nil if none.
local function body_range(t, i1, i2)
  i1, i2 = math.max(3, i1), math.min(#t.rows, i2)
  if i1 > i2 then
    return nil
  end
  return i1, i2
end

--- Delete the cursor's row and the [count] - 1 below it, or rows `range`
--- ({ i1, i2 }, model indices). The header and the delimiter row stay.
function M.delete_row(range, n)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  local i1, i2
  if range then
    i1, i2 = body_range(t, range[1], range[2])
  elseif i > 2 then
    i1, i2 = body_range(t, i, i + (n or util.count1()) - 1)
  end
  if not i1 then
    return util.warn("can't delete the header or delimiter row")
  end
  for _ = i1, i2 do
    table.remove(t.rows, i1)
  end
  local old_er = t.er
  local lines, pos = M.render(t)
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, t.sr, old_er + 1, false, lines)
  local ni = math.min(range and i1 or i, #lines)
  api.nvim_win_set_cursor(0, { t.sr + ni, pos[ni][math.min(c, #pos[ni])].s })
end

--- Add [count] empty columns right of the cursor, or left of it with `left = true`.
function M.add_col(left, n)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  n = n or util.count1()
  local i, c = cursor_cell(buf, t)
  if left then
    c = c - 1 -- insert after the previous column
  end
  local cols = ncols(t)
  for _, r in ipairs(t.rows) do
    while #r < cols do
      table.insert(r, "")
    end
    for _ = 1, n do
      table.insert(r, c + 1, "")
    end
  end
  for k = #t.aligns + 1, cols do
    t.aligns[k] = "none"
  end
  for _ = 1, n do
    table.insert(t.aligns, c + 1, "none")
  end
  write(buf, t, { i, c + 1, 0 })
end

--- Delete the cursor's column and the [count] - 1 right of it, or columns
--- `range` ({ c1, c2 }). At least one column stays.
function M.delete_col(range, n)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  local cols = ncols(t)
  local c1, c2 = c, c + (n or util.count1()) - 1
  if range then
    c1, c2 = range[1], range[2]
  end
  c1, c2 = math.max(1, c1), math.min(cols, c2)
  if c2 - c1 + 1 >= cols then
    return util.warn(cols == 1 and "can't delete the only column" or "can't delete every column")
  end
  for _, r in ipairs(t.rows) do
    for _ = c1, math.min(c2, #r) do
      table.remove(r, c1)
    end
  end
  for _ = c1, math.min(c2, #t.aligns) do
    table.remove(t.aligns, c1)
  end
  write(buf, t, { i, math.min(c1, ncols(t)), 0 })
end

-- Table extras ------------------------------------------------------------

--- Pad every row (and the alignments) to the table's column count.
local function square(t)
  local n = ncols(t)
  for _, r in ipairs(t.rows) do
    for c = #r + 1, n do
      r[c] = ""
    end
  end
  for c = #t.aligns + 1, n do
    t.aligns[c] = "none"
  end
  return n
end

--- Move the column under the cursor left (dir = -1) or right (dir = 1),
--- [count] times. Alignment markers move with it; the cursor follows.
--- Move the cursor's column (or columns `range`, { c1, c2 }) left (dir = -1)
--- or right (dir = 1), [count] times; alignments move with them.
function M.move_col(dir, range)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c, off = cursor_cell(buf, t)
  local n = square(t)
  local c1, c2 = c, c
  if range then
    c1, c2 = math.max(1, range[1]), math.min(n, range[2])
  end
  local by = dir * util.count1()
  local t1 = math.max(1, math.min(n - (c2 - c1), c1 + by))
  if t1 == c1 then
    return
  end
  local function shift(list)
    local block = {}
    for _ = c1, c2 do
      table.insert(block, table.remove(list, c1))
    end
    for k, v in ipairs(block) do
      table.insert(list, t1 + k - 1, v)
    end
  end
  for _, r in ipairs(t.rows) do
    shift(r)
  end
  shift(t.aligns)
  write(buf, t, { i, c + (t1 - c1), off })
end

--- Move the cursor's body row (or rows `range`, { i1, i2 }) up (dir = -1) or
--- down (dir = 1), [count] times. The header and the delimiter row stay.
function M.move_row(dir, range)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c, off = cursor_cell(buf, t)
  local i1, i2
  if range then
    i1, i2 = body_range(t, range[1], range[2])
  elseif i > 2 then
    i1, i2 = i, i
  end
  if not i1 then
    return util.warn("can't move the header row")
  end
  local t1 = math.max(3, math.min(#t.rows - (i2 - i1), i1 + dir * util.count1()))
  if t1 == i1 then
    return
  end
  local block = {}
  for _ = i1, i2 do
    table.insert(block, table.remove(t.rows, i1))
  end
  for k, r in ipairs(block) do
    table.insert(t.rows, t1 + k - 1, r)
  end
  local ci = (i >= i1 and i <= i2) and i + (t1 - i1) or t1
  write(buf, t, { ci, c, off })
end

--- Visual mode: run a row or column action on the selection. Rows `srow`..
--- `erow` are 0-based buffer rows; columns come from the cells under `scol`
--- (on `srow`) and `ecol` (on `erow`) for a charwise or blockwise selection.
---@param action "delete_row"|"delete_col"|"move_row"|"move_col"|"sort"
function M.visual(action, arg, srow, erow, scol, ecol, mtype)
  local buf = api.nvim_get_current_buf()
  local sr = M.find(buf, srow)
  if not sr then
    return util.warn("not in a table")
  end
  pcall(api.nvim_win_set_cursor, 0, { srow + 1, scol or 0 })
  local rows = { srow - sr + 1, erow - sr + 1 }
  if action == "delete_col" or action == "move_col" then
    if mtype == "line" then
      return util.warn("select the columns with v or <C-v>")
    end
    local function cell_at(row, col)
      local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      local cells = M.split_row(line)
      for k, cell in ipairs(cells) do
        if col < cell.re then
          return k
        end
      end
      return #cells
    end
    local c1, c2 = cell_at(srow, scol), cell_at(erow, ecol)
    if c1 > c2 then
      c1, c2 = c2, c1
    end
    if action == "delete_col" then
      return M.delete_col({ c1, c2 })
    end
    return M.move_col(arg, { c1, c2 })
  elseif action == "delete_row" then
    return M.delete_row(rows)
  elseif action == "move_row" then
    return M.move_row(arg, rows)
  elseif action == "sort" then
    return M.sort(arg, rows)
  end
end

--- Sort key of a cell: a number when the text is one (thousands separators,
--- currency signs, `%` and Markdown emphasis ignored), else lowercase text.
local function sort_key(text)
  local plain = vim.trim((text:gsub("[*_`~=]", "")))
  local num = plain:gsub("^[%$€£¥]", ""):gsub("%%$", ""):gsub("(%d),(%d%d%d)", "%1%2")
  num = num:gsub("(%d),(%d%d%d)", "%1%2")
  return tonumber(num), vim.fn.tolower(plain), plain == ""
end

--- Sort the body rows by the column under the cursor, ascending (or
--- descending with `desc = true`). Numbers compare as numbers
--- when the whole column is numeric (ISO dates sort correctly as text);
--- empty cells go last. The sort is stable.
function M.sort(desc, range)
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c, off = cursor_cell(buf, t)
  square(t)
  local first, last = 3, #t.rows
  if range then
    first, last = body_range(t, range[1], range[2])
    if not first then
      return util.warn("select body rows to sort")
    end
  end
  local body = {}
  for k = first, last do
    local num, txt, empty = sort_key(t.rows[k][c] or "")
    table.insert(body, { row = t.rows[k], num = num, txt = txt, empty = empty, idx = k })
  end
  if #body < 2 then
    return
  end
  local numeric = true
  for _, b in ipairs(body) do
    if not b.empty and not b.num then
      numeric = false
    end
  end
  local function less(a, b)
    if a.empty ~= b.empty then
      return b.empty -- empty cells last, either way
    end
    local ka, kb = numeric and a.num or a.txt, numeric and b.num or b.txt
    if not a.empty and ka ~= kb then
      if desc then
        return ka > kb
      end
      return ka < kb
    end
    return a.idx < b.idx
  end
  local sorted = vim.deepcopy(body)
  table.sort(sorted, less)
  for k, b in ipairs(sorted) do
    t.rows[first + k - 1] = b.row
  end
  write(buf, t, { i, c, off })
end

--- Swap rows and columns: the first column becomes the header row.
--- Alignments are reset (they belonged to the old columns).
function M.transpose()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  local n = square(t)
  local data = {}
  for k, r in ipairs(t.rows) do
    if k ~= 2 then
      table.insert(data, r)
    end
  end
  local rows = {}
  for col = 1, n do
    local r = {}
    for d = 1, #data do
      r[d] = data[d][col]
    end
    table.insert(rows, r)
  end
  local delim_row = {}
  t.aligns = {}
  for d = 1, #data do
    delim_row[d] = "---"
    t.aligns[d] = "none"
  end
  table.insert(rows, 2, delim_row)
  t.rows = rows
  -- the cell under the cursor moves to (row = old column, column = old row)
  local d = i <= 2 and 1 or i - 1
  write(buf, t, { c == 1 and 1 or c + 1, d, 0 })
end

--- Copy the table under the cursor to the clipboard (and the unnamed
--- register) as CSV, asking for the separator like table → CSV. The table
--- stays as it is.
function M.yank_csv()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local default = config.options.tables.csv_separator
  local shown = default == "\t" and "\\t" or default
  util.input({ prompt = "Separator: ", default = shown }, function(input)
    if input == nil then
      return
    end
    local sep = M.parse_sep(input) or default
    local fresh = M.read(buf, t.sr, t.er)
    fresh.indent = ""
    local lines = M.to_csv_lines(fresh, sep)
    local text = table.concat(lines, "\n") .. "\n"
    vim.fn.setreg('"', text, "l")
    if vim.fn.has("clipboard") == 1 then
      pcall(vim.fn.setreg, "+", text, "l")
    end
    vim.notify(("markwright: copied %d line%s as CSV"):format(#lines, #lines == 1 and "" or "s"))
  end)
end

--- Move to the next (dir = 1) or previous (dir = -1) cell. From the last
--- cell, <Tab> adds a new row. Used from insert mode.
function M.next_cell(dir)
  local t, buf = current()
  if not t then
    return
  end
  local i, c = cursor_cell(buf, t)
  local n = ncols(t)
  if dir > 0 then
    c = c + 1
    if c > n then
      c, i = 1, i + 1
      if i == 2 then
        i = 3
      end
      if i > #t.rows then
        table.insert(t.rows, empty_row(n))
      end
    end
  else
    c = c - 1
    if c < 1 then
      if i <= 1 then
        c = 1
      else
        c, i = n, i - 1
        if i == 2 then
          i = 1
        end
      end
    end
  end
  if i == 2 then
    i = dir > 0 and 3 or 1
  end
  write(buf, t, { i, c, "end" }, { no_break = true })
end

-- <Tab> -------------------------------------------------------------------

--- Is the cursor row inside a table?
function M.at_cursor(buf)
  buf = buf or api.nvim_get_current_buf()
  return M.find(buf, api.nvim_win_get_cursor(0)[1] - 1) ~= nil
end

--- Insert-mode <Tab>/<S-Tab>: next/previous cell inside a table, otherwise
--- whatever the key did before (completion, snippets, indent).
function M.expr_tab(dir)
  local lhs = dir > 0 and "<Tab>" or "<S-Tab>"
  local buf = api.nvim_get_current_buf()
  if util.completion_active(dir) or not M.at_cursor(buf) then
    return util.fallback(buf, "i", lhs)
  end
  return ("<Cmd>lua require('markwright.tables').next_cell(%d)<CR>"):format(dir)
end

--- InsertLeave: realign if the cursor is in a table (joined to the insert's undo step).
function M.on_insert_leave()
  if not config.options.tables.align_on_insert_leave then
    return
  end
  M.align({ silent = true, join = true })
end

return M
