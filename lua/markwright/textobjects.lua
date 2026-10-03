-- Text objects: links, URLs, inline code, code fences, heading sections, table cells, list items,
-- emphasis. Spec: SPEC.md section 14.8.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")

local M = {}

---@class markwright.Range
---@field sr integer 0-based start row
---@field sc integer 0-based start byte column
---@field er integer 0-based end row
---@field ec integer end byte column, exclusive (ignored when linewise)
---@field linewise? boolean

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function node_range(node)
  local sr, sc, er, ec = node:range()
  return { sr = sr, sc = sc, er = er, ec = ec }
end

local function child(node, t)
  for c in node:iter_children() do
    if c:type() == t then
      return c
    end
  end
end

local function contains(r, row, col)
  if row < r.sr or row > r.er then
    return false
  end
  if row == r.sr and col < r.sc then
    return false
  end
  if row == r.er and col >= r.ec then
    return false
  end
  return true
end

local function size(r)
  return (r.er - r.sr) * 100000 + (r.ec - r.sc)
end

--- Inline nodes of the given types on `row`, in document order.
local function inline_nodes_on_row(p, row, types)
  local out = {}
  local inl = p:children()["markdown_inline"]
  if not inl then
    return out
  end
  for _, tree in ipairs(inl:trees()) do
    local root = tree:root()
    local sr, _, er = root:range()
    if sr <= row and er >= row then
      local function walk(n)
        local nsr, _, ner = n:range()
        if ner < row or nsr > row then
          return
        end
        if types[n:type()] then
          table.insert(out, n)
        end
        for c in n:iter_children() do
          walk(c)
        end
      end
      walk(root)
    end
  end
  table.sort(out, function(a, b)
    local _, ac = a:range()
    local _, bc = b:range()
    return ac < bc
  end)
  return out
end

--- Innermost node of `types` containing the cursor; otherwise the first one
--- after the cursor on the same line (like Vim's quote objects).
local function node_at_or_after(p, row, col, types)
  local node = ts.ancestor(ts.inline_node(p, row, col), types)
  if node and not ts.is_callout_marker(node, p) then
    return node
  end
  for _, n in ipairs(inline_nodes_on_row(p, row, types)) do
    local sr, sc = n:range()
    if sr == row and sc >= col and not ts.is_callout_marker(n, p) then
      return n
    end
  end
end

-- Links -------------------------------------------------------------------------

local LINK_TYPES = {
  inline_link = true,
  image = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
  uri_autolink = true,
  email_autolink = true,
}

local function bare_url(buf, row, col)
  local line = get_line(buf, row)
  local links = require("markwright.links")
  local sc, ec = links.url_at(line, col)
  if sc then
    return { sr = row, sc = sc, er = row, ec = ec }
  end
  -- first bare URL after the cursor
  for c = col + 1, #line - 1 do
    sc, ec = links.url_at(line, c)
    if sc and sc >= col then
      return { sr = row, sc = sc, er = row, ec = ec }
    end
  end
end

function M.link(buf, row, col, inner)
  local p = ts.parse(buf, row)
  local node = p and node_at_or_after(p, row, col, LINK_TYPES)
  if not node then
    return bare_url(buf, row, col)
  end
  local t = node:type()
  if not inner then
    return node_range(node)
  end
  if t == "uri_autolink" or t == "email_autolink" then
    local r = node_range(node)
    r.sc, r.ec = r.sc + 1, r.ec - 1
    return r
  end
  local text = child(node, t == "image" and "image_description" or "link_text")
  if text then
    return node_range(text)
  end
  -- empty text: "[](url)" → the position between the brackets
  local r = node_range(node)
  local off = t == "image" and 2 or 1
  return { sr = r.sr, sc = r.sc + off, er = r.sr, ec = r.sc + off }
end

function M.url(buf, row, col)
  local p = ts.parse(buf, row)
  local node = p and node_at_or_after(p, row, col, LINK_TYPES)
  if not node then
    return bare_url(buf, row, col)
  end
  local t = node:type()
  if t == "uri_autolink" or t == "email_autolink" then
    return M.link(buf, row, col, true)
  end
  local dest = child(node, "link_destination")
  if dest then
    local r = node_range(dest)
    local line = get_line(buf, r.sr)
    if line:sub(r.sc + 1, r.sc + 1) == "<" and line:sub(r.ec, r.ec) == ">" then
      r.sc, r.ec = r.sc + 1, r.ec - 1
    end
    return r
  end
  -- reference link: the URL of its definition line
  local label = child(node, t == "full_reference_link" and "link_label" or "link_text")
  if label then
    local doc = require("markwright.doc")
    local key = vim.treesitter.get_node_text(label, buf):gsub("^%[", ""):gsub("%]$", "")
    local def = doc.definitions(buf)[doc.normalize_label(key)]
    if def then
      return { sr = def.row, sc = def.col, er = def.row, ec = def.col + #def.dest }
    end
  end
end

-- Code ---------------------------------------------------------------------------

local BLOCKS = { fenced_code_block = true, indented_code_block = true }

--- Inline code (`ic` / `ac`).
function M.code(buf, row, col, inner)
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local span = ts.ancestor(ts.inline_node(p, row, col), { code_span = true })
  if span then
    local r = node_range(span)
    if not inner then
      return r
    end
    local line = get_line(buf, r.sr)
    local ticks = #line:sub(r.sc + 1):match("^`+")
    local s, e = r.sc + ticks, r.ec - ticks
    local text = line:sub(s + 1, e)
    if #text >= 2 and text:sub(1, 1) == " " and text:sub(-1) == " " and text:find("%S") then
      s, e = s + 1, e - 1 -- padding added for backticks inside
    end
    return { sr = r.sr, sc = s, er = r.sr, ec = e }
  end
end

--- Code block (`if` / `af`): the lines between the fences / the whole block.
function M.fence(buf, row, col, inner)
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local block = ts.ancestor(ts.block_node(p, row, col), BLOCKS)
  if not block then
    return nil
  end
  local sr, _, er, ec = block:range()
  if ec == 0 then
    er = er - 1
  end
  while er > sr and get_line(buf, er):match("^%s*$") do
    er = er - 1
  end
  if block:type() == "indented_code_block" or not inner then
    return { sr = sr, sc = 0, er = er, ec = 0, linewise = true }
  end
  -- fenced: the lines between the fences
  local last = get_line(buf, er)
  local closed = last:match("^%s*```") or last:match("^%s*~~~")
  local cer = closed and er - 1 or er
  if cer < sr + 1 then
    return { sr = sr + 1, sc = 0, er = sr, ec = 0, linewise = true, empty = true }
  end
  return { sr = sr + 1, sc = 0, er = cer, ec = 0, linewise = true }
end

-- Heading sections ---------------------------------------------------------------

local function heading_end_row(buf, h)
  -- setext headings take two lines
  local line = get_line(buf, h.row)
  if not line:match("^%s*#") and get_line(buf, h.row + 1):match("^%s*[=-]+%s*$") then
    return h.row + 1
  end
  return h.row
end

function M.section(buf, row, _, inner, count)
  local doc = require("markwright.doc")
  local hs = doc.headings(buf)
  local idx
  for i, h in ipairs(hs) do
    if h.row <= row then
      idx = i
    end
  end
  if not idx then
    return nil
  end
  -- count > 1: climb to enclosing (lower-level) headings
  for _ = 2, count or 1 do
    local level = hs[idx].level
    local parent
    for i = idx - 1, 1, -1 do
      if hs[i].level < level then
        parent = i
        break
      end
    end
    if not parent then
      break
    end
    idx = parent
  end
  local h = hs[idx]
  local last = api.nvim_buf_line_count(buf) - 1
  for i = idx + 1, #hs do
    if hs[i].level <= h.level then
      last = hs[i].row - 1
      break
    end
  end
  if not inner then
    return { sr = h.row, sc = 0, er = last, ec = 0, linewise = true }
  end
  local s, e = heading_end_row(buf, h) + 1, last
  while s <= e and get_line(buf, s):match("^%s*$") do
    s = s + 1
  end
  while e >= s and get_line(buf, e):match("^%s*$") do
    e = e - 1
  end
  if e < s then
    return { sr = s, sc = 0, er = s - 1, ec = 0, linewise = true, empty = true }
  end
  return { sr = s, sc = 0, er = e, ec = 0, linewise = true }
end

-- Table cells --------------------------------------------------------------------

function M.cell(buf, row, col, inner)
  local tables = require("markwright.tables")
  if not tables.find(buf, row) then
    return nil
  end
  local cells = tables.split_row(get_line(buf, row))
  if #cells == 0 then
    return nil
  end
  local cell = cells[#cells]
  for _, c in ipairs(cells) do
    if col < c.re then
      cell = c
      break
    end
  end
  if not inner then
    return { sr = row, sc = cell.rs, er = row, ec = cell.re }
  end
  if cell.text == "" then
    local at = math.min(cell.rs + 1, cell.re)
    return { sr = row, sc = at, er = row, ec = at }
  end
  return { sr = row, sc = cell.s, er = row, ec = cell.s + #cell.text }
end

-- List items ---------------------------------------------------------------------

function M.item(buf, row, col, inner, count)
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local line = get_line(buf, row)
  local node = ts.ancestor(ts.block_node(p, row, math.max(col, #line:match("^%s*"))), { list_item = true })
  for _ = 2, count or 1 do
    local parent = node and node:parent() and ts.ancestor(node:parent(), { list_item = true })
    if not parent then
      break
    end
    node = parent
  end
  if not node then
    return nil
  end
  local sr, _, er, ec = node:range()
  if ec == 0 then
    er = er - 1
  end
  while er > sr and get_line(buf, er):match("^%s*$") do
    er = er - 1
  end
  if not inner then
    return { sr = sr, sc = 0, er = er, ec = 0, linewise = true }
  end
  local item = require("markwright.lists").parse(get_line(buf, sr))
  if not item then
    return nil
  end
  -- the item's own text: its first line, plus continuation lines of the same paragraph
  local e_row = sr
  local para = child(node, "paragraph")
  local inl = para and child(para, "inline")
  if inl then
    local _, _, ier = inl:range()
    e_row = math.max(sr, math.min(ier, er))
  end
  local e_line = get_line(buf, e_row)
  local ecol = #e_line:gsub("%s+$", "")
  if e_row == sr and ecol <= item.text_col then
    return { sr = sr, sc = #get_line(buf, sr), er = sr, ec = #get_line(buf, sr) }
  end
  return { sr = sr, sc = item.text_col, er = e_row, ec = ecol }
end

-- Emphasis -----------------------------------------------------------------------

local EMPH = { emphasis = 1, strong_emphasis = 2, strikethrough = 2 }

local function emphasis_candidates(buf, p, row, col)
  local out = {}
  local node = ts.inline_node(p, row, col)
  while node do
    local t = node:type()
    if EMPH[t] then
      -- ~~x~~ parses as nested strikethrough nodes: keep the outer one
      local nested = t == "strikethrough" and node:parent() and node:parent():type() == "strikethrough"
      if not nested then
        table.insert(out, { range = node_range(node), marker = EMPH[t] })
      end
    end
    node = node:parent()
  end
  -- ==highlight== is not in the grammar: scan the line
  local line = get_line(buf, row)
  local open
  local i = 1
  while true do
    local s = line:find("==", i, true)
    if not s then
      break
    end
    if open then
      local r = { sr = row, sc = open - 1, er = row, ec = s + 1 }
      if contains(r, row, col) then
        table.insert(out, { range = r, marker = 2 })
      end
      open = nil
    else
      open = s
    end
    i = s + 2
  end
  table.sort(out, function(a, b)
    return size(a.range) < size(b.range)
  end)
  return out
end

function M.emphasis(buf, row, col, inner, count)
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local cands = emphasis_candidates(buf, p, row, col)
  if #cands == 0 then
    -- first emphasis after the cursor on this line
    for _, n in ipairs(inline_nodes_on_row(p, row, EMPH)) do
      local sr, sc = n:range()
      if sr == row and sc >= col then
        cands = emphasis_candidates(buf, p, row, sc)
        break
      end
    end
  end
  local c = cands[math.min(count or 1, #cands)]
  if not c then
    return nil
  end
  local r = vim.deepcopy(c.range)
  if inner then
    r.sc, r.ec = r.sc + c.marker, r.ec - c.marker
  end
  return r
end

-- Forward search ------------------------------------------------------------------
-- When the cursor isn't inside an object, the next one after the cursor is used
-- (like mini.ai's default "cover_or_next"), up to `textobjects.search_lines`
-- lines ahead. Each object lists the positions where its instances start; the
-- object function is then evaluated at the first position after the cursor.

local function walk(node, fn)
  fn(node)
  for c in node:iter_children() do
    walk(c, fn)
  end
end

--- Start positions of inline nodes of `types` in rows [from, to].
local function inline_anchors(p, types, from, to, out)
  local inl = p:children()["markdown_inline"]
  if not inl then
    return
  end
  for _, tree in ipairs(inl:trees()) do
    local root = tree:root()
    local sr, _, er = root:range()
    if er >= from and sr <= to then
      walk(root, function(n)
        if types[n:type()] and not ts.is_callout_marker(n, p) then
          local r, c = n:range()
          if r >= from and r <= to then
            table.insert(out, { r, c })
          end
        end
      end)
    end
  end
end

--- Start positions of block nodes of `types` in rows [from, to] (`col` picks
--- the column: "start" = node start, a number = that column).
local function block_anchors(p, types, from, to, out)
  local trees = p:trees()
  if not trees[1] then
    return
  end
  walk(trees[1]:root(), function(n)
    if types[n:type()] then
      local r, c = n:range()
      if r >= from and r <= to then
        table.insert(out, { r, c })
      end
    end
  end)
end

local URL_STARTS = { "%a[%w+.-]*://", "www%.", "mailto:" }

local function bare_url_anchors(buf, from, to, out)
  local links = require("markwright.links")
  for r = from, to do
    local line = get_line(buf, r)
    for _, pat in ipairs(URL_STARTS) do
      local init = 1
      while true do
        local s = line:find(pat, init)
        if not s then
          break
        end
        local sc = links.url_at(line, s - 1)
        if sc then
          table.insert(out, { r, sc })
        end
        init = s + 1
      end
    end
  end
end

local ANCHORS = {}

ANCHORS.link = function(buf, p, from, to, out)
  inline_anchors(p, LINK_TYPES, from, to, out)
  bare_url_anchors(buf, from, to, out)
end
ANCHORS.url = ANCHORS.link

ANCHORS.code = function(_, p, from, to, out)
  inline_anchors(p, { code_span = true }, from, to, out)
end

ANCHORS.fence = function(_, p, from, to, out)
  block_anchors(p, BLOCKS, from, to, out)
end

ANCHORS.section = function(buf, _, from, to, out)
  for _, h in ipairs(require("markwright.doc").headings(buf)) do
    if h.row >= from and h.row <= to then
      table.insert(out, { h.row, 0 })
    end
  end
end

ANCHORS.cell = function(buf, p, from, to, out)
  local tables = require("markwright.tables")
  local found = {}
  block_anchors(p, { pipe_table = true }, from, to, found)
  for _, a in ipairs(found) do
    local cells = tables.split_row(get_line(buf, a[1]))
    if cells[1] then
      table.insert(out, { a[1], cells[1].s })
    end
  end
end

ANCHORS.item = function(_, p, from, to, out)
  block_anchors(p, { list_item = true }, from, to, out)
end

ANCHORS.emphasis = function(buf, p, from, to, out)
  inline_anchors(p, EMPH, from, to, out)
  for r = from, to do
    local line = get_line(buf, r)
    local open, i = nil, 1
    while true do
      local st = line:find("==", i, true)
      if not st then
        break
      end
      if open then
        table.insert(out, { r, open - 1 })
        open = nil
      else
        open = st
      end
      i = st + 2
    end
  end
end

--- Positions (0-based {row, col}) where objects of `name` start, from `row`
--- to `row + lines`, in document order.
function M.anchors(name, buf, row, lines)
  local last = math.min(api.nvim_buf_line_count(buf) - 1, row + lines)
  local p = ts.parse(buf, row, last)
  local out = {}
  if p then
    ANCHORS[name](buf, p, row, last, out)
  end
  table.sort(out, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)
  return out
end

-- Selecting ------------------------------------------------------------------------

local function is_empty(r)
  if r.linewise then
    return r.empty == true
  end
  return r.er == r.sr and r.ec <= r.sc
end

--- Select `r` visually so the pending operator (or visual mode) uses it.
function M.select(r)
  if vim.fn.mode(true):match("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  if r.linewise then
    api.nvim_win_set_cursor(0, { r.sr + 1, 0 })
    vim.cmd("normal! V")
    api.nvim_win_set_cursor(0, { r.er + 1, 0 })
    return
  end
  local ec, er = r.ec - 1, r.er
  if ec < 0 then
    er = er - 1
    ec = math.max(0, #get_line(0, er) - 1)
  end
  api.nvim_win_set_cursor(0, { r.sr + 1, r.sc })
  vim.cmd("normal! v")
  api.nvim_win_set_cursor(0, { er + 1, ec })
end

local function compute(name, inner, count)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local fn = M.OBJECTS[name].fn
  local r = fn(buf, row, col, inner, count)
  if r then
    return r
  end
  -- not inside one: the next one after the cursor
  local lines = config.options.textobjects.search_lines or 500
  for _, a in ipairs(M.anchors(name, buf, row, lines)) do
    if a[1] > row or (a[1] == row and a[2] > col) then
      r = fn(buf, a[1], a[2], inner, count)
      if r then
        return r
      end
    end
  end
end

--- Called from the mapping's <Cmd>; recomputes the range so dot-repeat works
--- at the new cursor position.
function M._select(name, inner, count)
  local r = compute(name, inner, count)
  if r and not is_empty(r) then
    M.select(r)
  end
end

--- Empty region with `c`: start inserting where the text would be.
function M._insert_at(name, inner, count)
  local r = compute(name, inner, count)
  if not r then
    return
  end
  local line = get_line(0, r.sr)
  if r.linewise then
    api.nvim_buf_set_lines(0, r.sr, r.sr, false, { "" })
    api.nvim_win_set_cursor(0, { r.sr + 1, 0 })
  else
    api.nvim_win_set_cursor(0, { r.sr + 1, math.min(r.sc, #line) })
  end
  if r.linewise or r.sc < #line then
    vim.cmd("startinsert")
  else
    vim.cmd("startinsert!")
  end
end

local function cmd(fn, name, inner, count)
  return ("<Cmd>lua require('markwright.textobjects').%s(%q, %s, %d)<CR>"):format(fn, name, tostring(inner), count)
end

--- expr mapping: check the range now, select it via <Cmd> (recomputed there).
function M.expr(name, inner)
  local count = vim.v.count1
  local r = compute(name, inner, count)
  local pending = vim.fn.mode(true):match("^no") ~= nil
  if not r then
    return pending and "<Esc>" or ""
  end
  if is_empty(r) then
    if pending and vim.v.operator == "c" then
      return "<Esc>" .. cmd("_insert_at", name, inner, count)
    end
    return pending and "<Esc>" or ""
  end
  return cmd("_select", name, inner, count)
end

M.OBJECTS = {
  link = { fn = M.link, around = true },
  url = { fn = M.url, around = false },
  code = { fn = M.code, around = true },
  fence = { fn = M.fence, around = true },
  section = { fn = M.section, around = true },
  cell = { fn = M.cell, around = true },
  item = { fn = M.item, around = true },
  emphasis = { fn = M.emphasis, around = true },
}

local function lhs_key(k)
  return k == "|" and "<Bar>" or k -- for anyone who configures a pipe
end

function M.attach(buf)
  local o = config.options.textobjects
  if not o or o.enabled == false then
    return
  end
  for name, obj in pairs(M.OBJECTS) do
    local key = o[name]
    if key and key ~= "" then
      local k = lhs_key(key)
      vim.keymap.set({ "o", "x" }, "i" .. k, function()
        return M.expr(name, true)
      end, { buffer = buf, silent = true, expr = true, desc = "markwright: inner " .. name })
      if obj.around then
        vim.keymap.set({ "o", "x" }, "a" .. k, function()
          return M.expr(name, false)
        end, { buffer = buf, silent = true, expr = true, desc = "markwright: around " .. name })
      end
    end
  end
end

return M
