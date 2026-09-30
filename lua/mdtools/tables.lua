-- Tables: create, CSV → table, row/column edits, cell navigation, alignment.
-- Spec: SPEC.md section 9.4.
local api = vim.api
local config = require("mdtools.config")
local ts = require("mdtools.ts")
local util = require("mdtools.util")

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

-- Parsing -----------------------------------------------------------------

---@class mdtools.Cell
---@field text string trimmed content
---@field rs integer raw segment start (0-based byte)
---@field re integer raw segment end (exclusive; the next pipe sits here)
---@field s integer trimmed content start

--- Split a table row into cells. Pipes escaped with `\|` stay in the cell.
---@return mdtools.Cell[]
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
  if #segs > 1 and line:sub(last[1] + 1, last[2]):match("^%s*$")
    and line:sub(last[1], last[1]) == "|" and line:sub(last[1] - 1, last[1] - 1) ~= "\\" then
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

--- Rows (0-based, inclusive) of the table containing `row`, or nil.
function M.find(buf, row)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  if not line:find("|", 1, true) then
    return nil
  end
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local col = #line:match("^%s*")
  local node = ts.ancestor(ts.block_node(p, row, col), { pipe_table = true })
  if not node then
    return nil
  end
  local sr, _, er, ec = node:range()
  if ec == 0 then
    er = er - 1
  end
  return sr, er
end

---@class mdtools.Table
---@field sr integer
---@field er integer
---@field indent string
---@field rows string[][] cell texts; rows[2] is the delimiter row
---@field aligns string[]

---@return mdtools.Table?
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
  vim.ui.input({ prompt = "Table size (rows x cols): ", default = "2x3" }, function(input)
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
    elseif ch == sep then
      table.insert(out, field)
      field = ""
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
function M.detect_sep(line)
  local best, best_n = ",", 0
  for _, sep in ipairs({ "\t", ",", ";" }) do
    local n = #M.csv_fields(line, sep) - 1
    if n > best_n then
      best, best_n = sep, n
    end
  end
  return best
end

--- Convert rows srow..erow (0-based, inclusive) of CSV/TSV into a table.
function M.from_csv(buf, srow, erow)
  local lines = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  local src = {}
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      table.insert(src, l)
    end
  end
  if #src == 0 then
    return
  end
  local sep = M.detect_sep(src[1])
  local rows = {}
  for _, l in ipairs(src) do
    table.insert(rows, M.csv_fields(l, sep))
  end
  local t = insert_table(buf, srow, rows, erow + 1)
  if buf == api.nvim_get_current_buf() then
    api.nvim_win_set_cursor(0, { t.sr + 1, #t.indent })
  end
end

function M.from_csv_visual()
  local buf = api.nvim_get_current_buf()
  M.from_csv(buf, api.nvim_buf_get_mark(buf, "<")[1] - 1, api.nvim_buf_get_mark(buf, ">")[1] - 1)
end

--- Add an empty row below the cursor (below the delimiter when on the header).
function M.add_row()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  local at = math.max(i, 2) + 1
  table.insert(t.rows, at, empty_row(ncols(t)))
  write(buf, t, { at, c, 0 })
end

function M.delete_row()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  if i <= 2 then
    return util.warn("can't delete the header or delimiter row")
  end
  table.remove(t.rows, i)
  local old_er = t.er
  local lines, pos = M.render(t)
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, t.sr, old_er + 1, false, lines)
  local ni = math.min(i, #lines)
  api.nvim_win_set_cursor(0, { t.sr + ni, pos[ni][math.min(c, #pos[ni])].s })
end

--- Add an empty column right of the cursor.
function M.add_col()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  local n = ncols(t)
  for _, r in ipairs(t.rows) do
    while #r < n do
      table.insert(r, "")
    end
    table.insert(r, c + 1, "")
  end
  for k = #t.aligns + 1, n do
    t.aligns[k] = "none"
  end
  table.insert(t.aligns, c + 1, "none")
  write(buf, t, { i, c + 1, 0 })
end

function M.delete_col()
  local t, buf = current()
  if not t then
    return util.warn("not in a table")
  end
  local i, c = cursor_cell(buf, t)
  if ncols(t) <= 1 then
    return util.warn("can't delete the only column")
  end
  for _, r in ipairs(t.rows) do
    if r[c] ~= nil then
      table.remove(r, c)
    end
  end
  table.remove(t.aligns, c)
  write(buf, t, { i, math.min(c, ncols(t)), 0 })
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

-- <Tab> handling with fallback -------------------------------------------

--- Completion menu or snippet active? Then <Tab> belongs to them.
local function completion_active(dir)
  local blink = package.loaded["blink.cmp"]
  if blink and blink.is_visible and blink.is_visible() then
    return true
  end
  local cmp = package.loaded["cmp"]
  if cmp and cmp.visible and cmp.visible() then
    return true
  end
  if vim.fn.pumvisible() == 1 then
    return true
  end
  if vim.snippet and vim.snippet.active({ direction = dir }) then
    return true
  end
  return false
end

M._fallback = {} ---@type table<string, table>

--- Remember the mapping that existed before ours, so it keeps working
--- outside tables.
function M.save_fallback(buf, lhs)
  local m = vim.fn.maparg(lhs, "i", false, true)
  M._fallback[buf .. lhs] = (m and not vim.tbl_isempty(m)) and m or nil
end

function M._run_fallback(key)
  local m = M._fallback[key]
  if m and m.callback then
    m.callback()
  end
end

local function fallback(buf, lhs)
  local m = M._fallback[buf .. lhs]
  if not m then
    return lhs
  end
  if m.callback then
    if m.expr == 1 then
      return m.callback() or ""
    end
    return ("<Cmd>lua require('mdtools.tables')._run_fallback(%q)<CR>"):format(buf .. lhs)
  end
  if m.rhs and m.rhs ~= "" then
    if m.expr == 1 then
      return api.nvim_eval(m.rhs)
    end
    if m.noremap == 1 then
      return m.rhs
    end
    api.nvim_feedkeys(api.nvim_replace_termcodes(m.rhs, true, false, true), "m", false)
    return ""
  end
  return lhs
end

--- Insert-mode <Tab>/<S-Tab>: next/previous cell inside a table, otherwise
--- whatever the key did before (completion, snippets, indent).
function M.expr_tab(dir)
  local lhs = dir > 0 and "<Tab>" or "<S-Tab>"
  local buf = api.nvim_get_current_buf()
  if completion_active(dir) then
    return fallback(buf, lhs)
  end
  local row = api.nvim_win_get_cursor(0)[1] - 1
  if not M.find(buf, row) then
    return fallback(buf, lhs)
  end
  return ("<Cmd>lua require('mdtools.tables').next_cell(%d)<CR>"):format(dir)
end

--- InsertLeave: realign if the cursor is in a table (joined to the insert's undo step).
function M.on_insert_leave()
  if not config.options.tables.align_on_insert_leave then
    return
  end
  M.align({ silent = true, join = true })
end

return M
