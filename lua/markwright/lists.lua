-- Lists: continuation, nesting, checkboxes, renumbering. Spec: SPEC.md section 9.2.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")

local M = {}

local function opts()
  return config.options.lists
end

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function is_hr(line)
  local s = line:gsub("%s", "")
  return s:match("^%-%-%-+$") or s:match("^%*%*%*+$") or s:match("^___+$")
end

---@class markwright.ListItem
---@field bq string blockquote prefix
---@field indent string
---@field marker string "-", "*", "+", "1.", "2)" ...
---@field num? integer
---@field delim? string "." or ")"
---@field space string whitespace after the marker
---@field check? string " ", "x" or "X"
---@field text string content after marker (and checkbox)
---@field marker_col integer
---@field content_col integer where the checkbox or text starts
---@field text_col integer where the text starts

--- Parse a list item line, or nil.
---@return markwright.ListItem?
function M.parse(line)
  if is_hr(line) then
    return nil
  end
  local bqn = util.bq_len(line)
  local bq, rest = line:sub(1, bqn), line:sub(bqn + 1)
  local indent, marker, space, text = rest:match("^( *)([-*+])(%s+)(.*)$")
  local num, delim
  if not marker then
    indent, marker = rest:match("^( *)([-*+])$")
    space, text = "", ""
  end
  if not marker then
    indent, num, delim, space, text = rest:match("^( *)(%d+)([.)])(%s+)(.*)$")
    if not num then
      indent, num, delim = rest:match("^( *)(%d+)([.)])$")
      space, text = "", ""
    end
    if not num or #num > 9 then
      return nil
    end
    marker = num .. delim
  end
  local item = {
    bq = bq,
    indent = indent,
    marker = marker,
    num = tonumber(num),
    delim = delim,
    space = space,
    text = text,
  }
  local check, cspace, after = text:match("^%[([ xX])%](%s+)(.*)$")
  if not check then
    check = text:match("^%[([ xX])%]$")
    cspace, after = "", ""
  end
  item.marker_col = #bq + #indent
  item.content_col = item.marker_col + #marker + #space
  item.text_col = item.content_col
  if check then
    item.check, item.text = check, after
    item.text_col = item.content_col + 3 + #cspace
  end
  return item
end

local function in_code(buf, row)
  return ts.code_context(ts.parse(buf, row), row, 0) == "block"
end

--- List item on `row`, unless it's inside a code block.
function M.item_at(buf, row)
  local item = M.parse(get_line(buf, row))
  if item and not in_code(buf, row) then
    return item
  end
end

-- Renumbering ---------------------------------------------------------------

local ORDERED = { list_marker_dot = true, list_marker_parenthesis = true }

local function marker_node(item)
  for c in item:iter_children() do
    if c:type():match("^list_marker") then
      return c
    end
  end
end

local function item_number(buf, item)
  local m = marker_node(item)
  if not m or not ORDERED[m:type()] then
    return nil
  end
  local txt = vim.treesitter.get_node_text(m, buf)
  return tonumber(txt:match("%d+")), m
end

local function list_items(list)
  local out = {}
  for c in list:iter_children() do
    if c:type() == "list_item" then
      table.insert(out, c)
    end
  end
  return out
end

--- Numbers of the ordered list items that are siblings of `row` (or nil).
local function sibling_numbers(buf, row)
  local p = ts.parse(buf, row)
  if not p then
    return nil
  end
  local col = #get_line(buf, row):match("^%s*")
  local item = ts.ancestor(ts.block_node(p, row, col), { list_item = true })
  local list = item and item:parent()
  if not list or list:type() ~= "list" then
    return nil
  end
  local nums = {}
  for _, it in ipairs(list_items(list)) do
    table.insert(nums, (item_number(buf, it)))
  end
  return nums
end

--- Lazy numbering ("1. 1. 1.") is kept as it is.
local function all_same(nums)
  if not nums or #nums < 2 then
    return false
  end
  for i = 2, #nums do
    if nums[i] ~= nums[1] then
      return false
    end
  end
  return true
end

-- Start numbers ------------------------------------------------------------------
--
-- A list's first number is where it starts (`5.` `6.` `7.` stays at 5), but
-- after deleting or moving the first item the new first number is just
-- whatever that item had. So each ordered list's start is remembered on an
-- extmark spanning its first item's line: if that line is deleted the mark
-- becomes invalid, and if lines are pasted above it the mark moves down with
-- the old first item. Either way the list keeps its remembered start; when
-- the marked line is still the first item, its number wins (the user may
-- have typed a new one).

local start_ns = api.nvim_create_namespace("markwright_list_start")
---@type table<integer, table<integer, { start: integer, col: integer, lazy: boolean }>>
local starts = {}

local function ordered_marker(buf, list)
  local first = list_items(list)[1]
  local n, m = nil, nil
  if first then
    n, m = item_number(buf, first)
  end
  return n, m, first
end

--- Remembered start and lazy flag of `list` (nil when nothing is remembered).
local function remembered(buf, list, first_row, col)
  local sr, _, er, ec = list:range()
  if ec == 0 and er > sr then
    er = er - 1
  end
  local data = starts[buf] or {}
  local first, other, invalid
  for _, mk in ipairs(api.nvim_buf_get_extmarks(buf, start_ns, { sr, 0 }, { er, -1 }, { details = true })) do
    local d = data[mk[1]]
    if d and d.col == col then
      if mk[4].invalid then
        invalid = invalid or d
      elseif mk[2] == first_row then
        first = d
      else
        other = other or d
      end
    end
  end
  return first, other or invalid
end

--- Start number and laziness of an ordered `list` with numbers `nums`.
local function list_start(buf, list, nums)
  local _, m, item = ordered_marker(buf, list)
  if not m then
    return nums[1], all_same(nums)
  end
  local _, col = m:range()
  local first, moved = remembered(buf, list, (item:range()), col)
  if first then
    return nums[1], first.lazy and all_same(nums)
  elseif moved then
    return moved.start, moved.lazy and all_same(nums)
  end
  return nums[1], all_same(nums)
end

--- Remember the start of every ordered list whose first item is in rows
--- [lo, hi], replacing what was remembered there.
local function remember(buf, lo, hi)
  starts[buf] = starts[buf] or {}
  for _, mk in ipairs(api.nvim_buf_get_extmarks(buf, start_ns, { lo, 0 }, { hi, -1 }, {})) do
    api.nvim_buf_del_extmark(buf, start_ns, mk[1])
    starts[buf][mk[1]] = nil
  end
  local p = ts.parser(buf)
  local tree = p and p:parse()[1]
  if not tree then
    return
  end
  local function walk(node)
    local sr, _, er = node:range()
    if er < lo or sr > hi then
      return
    end
    if node:type() == "list" then
      local n, m, item = ordered_marker(buf, node)
      local row = item and item:range()
      if n and row >= lo and row <= hi then
        local nums = {}
        for i, it in ipairs(list_items(node)) do
          nums[i] = (item_number(buf, it))
        end
        local _, col = m:range()
        local id = api.nvim_buf_set_extmark(buf, start_ns, row, col, {
          end_row = row,
          end_col = #get_line(buf, row),
          invalidate = true,
          right_gravity = true,
          end_right_gravity = true,
        })
        starts[buf][id] = { start = n, col = col, lazy = all_same(nums) }
      end
    end
    for c in node:iter_children() do
      walk(c)
    end
  end
  walk(tree:root())
end

--- Find the first ordered item with a wrong number under `node`.
local function first_wrong(buf, node)
  if node:type() == "list" then
    local items = list_items(node)
    local nums = {}
    for i, it in ipairs(items) do
      nums[i] = (item_number(buf, it))
    end
    if nums[1] then
      local start, lazy = list_start(buf, node, nums)
      if not lazy then
        for i, it in ipairs(items) do
          local expected = start + i - 1
          if nums[i] and nums[i] ~= expected then
            return it, expected
          end
        end
      end
    end
  end
  for c in node:iter_children() do
    local it, expected = first_wrong(buf, c)
    if it then
      return it, expected
    end
  end
end

--- Renumber the ordered lists around `row`. Returns true if anything changed.
---@param o? { join?: boolean }
function M.renumber(buf, row, o)
  local changed = false
  for _ = 1, 500 do
    local p = ts.parser(buf)
    if not p then
      return changed
    end
    p:parse()
    local line = get_line(buf, row)
    local node = ts.block_node(p, row, #line:match("^%s*"))
    local top
    while node do
      if node:type() == "list" then
        top = node
      end
      node = node:parent()
    end
    if not top then
      return changed
    end
    local item, expected = first_wrong(buf, top)
    if not item then
      return changed
    end
    local _, m = item_number(buf, item)
    local mr, mc = m:range()
    local mtext = get_line(buf, mr)
    local s, e = mtext:find("%d+", mc + 1)
    local new = tostring(expected)
    local delta = #new - (e - s + 1)
    if not changed then
      if o and o.join then
        pcall(vim.cmd, "undojoin")
      end
    end
    changed = true
    api.nvim_buf_set_text(buf, mr, s - 1, mr, e, { new })
    if delta ~= 0 then
      -- keep the item's other lines aligned with its content column
      local sr, _, er, ec = item:range()
      if ec == 0 then
        er = er - 1
      end
      for r = sr + 1, er do
        local l = get_line(buf, r)
        if not l:match("^%s*$") then
          api.nvim_buf_set_lines(buf, r, r + 1, false, { util.shift_line(l, delta) })
        end
      end
    end
  end
  return changed
end

-- Continuation ----------------------------------------------------------------

local function next_marker(buf, row, item)
  if not item.num then
    return item.marker
  end
  if all_same(sibling_numbers(buf, row)) then
    return item.marker
  end
  return (item.num + 1) .. item.delim
end

local function new_prefix(item, marker)
  local space = item.space ~= "" and item.space or " "
  return item.bq .. item.indent .. marker .. space .. (item.check and "[ ] " or "")
end

--- Insert-mode <CR> on a list item.
function M.enter()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local line = get_line(buf, row)
  local item = M.parse(line)
  if not item then
    return
  end
  if item.text == "" and col >= item.content_col then
    -- empty item: end the list
    local keep = item.bq
    api.nvim_buf_set_lines(buf, row, row + 1, false, { keep })
    api.nvim_win_set_cursor(0, { row + 1, #keep })
    return
  end
  if col <= item.marker_col then
    -- at the start of the line: open a blank line above, like a plain <CR>
    api.nvim_buf_set_lines(buf, row, row, false, { (item.bq:gsub("%s+$", "")) })
    api.nvim_win_set_cursor(0, { row + 2, col })
    return
  end
  col = math.max(col, item.text_col)
  local before = line:sub(1, col):gsub("%s+$", "")
  local after = line:sub(col + 1):gsub("^%s+", "")
  local prefix = new_prefix(item, next_marker(buf, row, item))
  api.nvim_buf_set_lines(buf, row, row + 1, false, { before, prefix .. after })
  api.nvim_win_set_cursor(0, { row + 2, #prefix })
  if item.num and opts().auto_renumber then
    M.renumber(buf, row + 1)
  end
end

--- Normal-mode o / O on a list item.
function M.open(below)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local item = M.parse(get_line(buf, row))
  if not item then
    return
  end
  local marker = below and next_marker(buf, row, item) or item.marker
  local prefix = new_prefix(item, marker)
  local at = below and row + 1 or row
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, at, at, false, { prefix })
  if item.num and opts().auto_renumber then
    M.renumber(buf, at)
  end
  local line = get_line(buf, at)
  api.nvim_win_set_cursor(0, { at + 1, #line })
  vim.cmd("startinsert!")
end

-- Nesting -----------------------------------------------------------------------

local function indent_width(line)
  local bq = util.bq_len(line)
  return #line:sub(bq + 1):match("^ *")
end

--- Last row of the item's subtree (its continuation lines and children).
local function subtree_end(buf, row, item)
  local last = row
  local n = api.nvim_buf_line_count(buf)
  for r = row + 1, n - 1 do
    local l = get_line(buf, r)
    if l:match("^%s*$") or indent_width(l) <= #item.indent then
      break
    end
    last = r
  end
  return last
end

--- Indent (dir = 1) or outdent (dir = -1) the list item under the cursor,
--- together with its children.
function M.indent(dir)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local item = M.parse(get_line(buf, row))
  if not item then
    return
  end
  local cur = #item.indent
  local target
  if dir > 0 then
    -- child of the previous sibling: align with its content
    for r = row - 1, 0, -1 do
      local l = get_line(buf, r)
      if l:match("^%s*$") then
        break
      end
      local prev = M.parse(l)
      local w = indent_width(l)
      if prev and w == cur then
        target = #prev.indent + #prev.marker + #prev.space
        break
      end
      if w < cur then
        break
      end
    end
    target = target or (cur + #item.marker + #item.space)
  else
    if cur == 0 then
      return
    end
    target = 0
    for r = row - 1, 0, -1 do
      local l = get_line(buf, r)
      if l:match("^%s*$") then
        break
      end
      local parent = M.parse(l)
      if parent and #parent.indent < cur then
        target = #parent.indent
        break
      end
    end
  end
  local delta = target - cur
  if delta == 0 then
    return
  end
  local last = subtree_end(buf, row, item)
  local lines = api.nvim_buf_get_lines(buf, row, last + 1, false)
  for i, l in ipairs(lines) do
    if not l:match("^%s*$") then
      lines[i] = util.shift_line(l, delta)
    end
  end
  api.nvim_buf_set_lines(buf, row, last + 1, false, lines)
  api.nvim_win_set_cursor(0, { row + 1, math.max(0, col + delta) })

  if item.num and opts().auto_renumber then
    -- a new sublist starts at 1. (Treesitter can't help here: a nested list
    -- starting at 2 can't interrupt a paragraph, so it isn't a list yet.)
    local moved = M.parse(get_line(buf, row))
    if dir > 0 and moved and moved.num and moved.num ~= 1 then
      local first = true
      for r = row - 1, 0, -1 do
        local l = get_line(buf, r)
        if l:match("^%s*$") then
          break
        end
        local w = indent_width(l)
        if w <= target then
          local prev = M.parse(l)
          first = not (prev and prev.num and #prev.indent == target)
          break
        end
      end
      if first then
        local l = get_line(buf, row)
        local s, e = l:find("%d+", moved.marker_col + 1)
        api.nvim_buf_set_text(buf, row, s - 1, row, e, { "1" })
        local d = 1 - (e - s + 1)
        if d ~= 0 then
          api.nvim_win_set_cursor(0, { row + 1, math.max(0, col + delta + d) })
        end
      end
    end
    local c = api.nvim_win_get_cursor(0)
    M.renumber(buf, row)
    -- renumbering may resize markers; keep the cursor on its text
    local after = get_line(buf, row)
    api.nvim_win_set_cursor(0, { row + 1, math.min(c[2], #after) })
  end
end

-- Checkboxes ----------------------------------------------------------------------

M.clock = os.time -- replaced in tests

-- os.date conversions → Lua patterns (digits); anything else matches loosely
local DATE_PAT = {
  Y = "%d%d%d%d",
  y = "%d%d",
  m = "%d%d",
  d = "%d%d",
  e = " ?%d?%d",
  H = "%d%d",
  I = "%d%d",
  M = "%d%d",
  S = "%d%d",
  p = "%a%a",
  j = "%d%d%d",
  F = "%d%d%d%d%-%d%d%-%d%d",
  R = "%d%d:%d%d",
  T = "%d%d:%d%d:%d%d",
}

--- Lua pattern matching a stamp written with `fmt`, at the end of a line.
function M.stamp_pattern(fmt)
  local out, i = {}, 1
  while i <= #fmt do
    local ch = fmt:sub(i, i)
    if ch == "%" and i < #fmt then
      local spec = fmt:sub(i + 1, i + 1)
      table.insert(out, spec == "%" and "%%" or (DATE_PAT[spec] or ".-"))
      i = i + 2
    else
      table.insert(out, (ch:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")))
      i = i + 1
    end
  end
  return "%s+" .. table.concat(out) .. "%s*$"
end

-- stamps written with the default or the Obsidian format are recognized even
-- if `done_date` has changed since
local KNOWN = { "✅ %Y-%m-%d %H:%M", "✅ %Y-%m-%d" }

--- Remove a completion stamp from the end of `line`; returns the new line or nil.
function M.strip_stamp(line, fmt)
  for _, f in ipairs(fmt and { fmt, unpack(KNOWN) } or KNOWN) do
    local s = line:find(M.stamp_pattern(f))
    if s then
      return line:sub(1, s - 1)
    end
  end
end

--- Add or remove the completion stamp after the checkbox changed on `row`.
local function stamp(buf, row, checked)
  local fmt = opts().done_date
  if not fmt then
    return
  end
  local line = get_line(buf, row)
  local stripped = M.strip_stamp(line, fmt)
  if checked then
    if stripped then
      return -- already stamped
    end
    local base = line:gsub("%s+$", "")
    api.nvim_buf_set_text(buf, row, #base, row, #line, { " " .. os.date(fmt, M.clock()) })
  elseif stripped then
    api.nvim_buf_set_text(buf, row, #stripped, row, #line, { "" })
  end
end

--- Set (state = "x" / " "), toggle (state = nil) or add a checkbox on `row`.
--- Returns true if the row is a list item.
local function set_checkbox(buf, row, state)
  local line = get_line(buf, row)
  local item = M.parse(line)
  if not item then
    return false
  end
  local c = item.content_col
  if item.check then
    local was = item.check ~= " "
    local new = state or (was and " " or "x")
    api.nvim_buf_set_text(buf, row, c + 1, row, c + 2, { new })
    if was ~= (new ~= " ") then
      stamp(buf, row, new ~= " ")
    end
  elseif opts().checkbox_add then
    local box = "[" .. (state or " ") .. "] "
    if item.space == "" then
      box = " " .. box:gsub(" $", "")
    end
    api.nvim_buf_set_text(buf, row, c, row, c, { box })
    if state == "x" then
      stamp(buf, row, true)
    end
  end
  return true
end

-- Progress cookies --------------------------------------------------------------

-- `[/]`, `[2/5]`, `[%]`, `[40%]` (not followed by "(": that's a link)
local COOKIES = { "()%[(%d*)/(%d*)%]()", "()%[(%d*)%%%]()" }

--- Every cookie on `line` from byte `from`, left to right: { s, e, pct }
--- (`e` is the byte after the closing bracket).
local function find_cookies(line, from)
  local found = {}
  for k, pat in ipairs(COOKIES) do
    local init = from
    while true do
      local caps = { line:match(pat, init) }
      if not caps[1] then
        break
      end
      local s, e = caps[1], caps[#caps]
      if line:sub(e, e) ~= "(" then
        table.insert(found, { s = s, e = e, pct = k == 2 })
      end
      init = e
    end
  end
  table.sort(found, function(a, b)
    return a.s < b.s
  end)
  return found
end

local function has_cookies(buf)
  for _, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find("%[%d*/%d*%]") or l:find("%[%d*%%%]") then
      return true
    end
  end
  return false
end

--- The line that labels a block-level `list`: the heading or the last line
--- of the paragraph right above it (blank lines between are fine). 0-based
--- row, or nil when the block above is something else.
local function label_row(buf, list)
  local prev = list:prev_named_sibling()
  while prev and (prev:type() == "block_quote_marker" or prev:type() == "block_continuation") do
    prev = prev:prev_named_sibling()
  end
  if not prev then
    return nil
  end
  local t = prev:type()
  if t == "atx_heading" then
    return (prev:range())
  elseif t == "setext_heading" then
    for c in prev:iter_children() do
      if c:type():match("^setext_h%d_underline$") then
        return (c:range()) - 1
      end
    end
  elseif t == "paragraph" then
    local first = prev:range()
    for row = list:range() - 1, first, -1 do
      if not get_line(buf, row):match("^[%s>]*$") then
        return row
      end
    end
  end
end

--- Fill every progress cookie in `buf`. A list item's cookies count its
--- direct children: those with a checkbox count (done when checked); a child
--- without a checkbox but with its own cookie counts too (done when complete),
--- so counts roll up. A heading or paragraph line right above a list counts
--- that list's items the same way.
---@param o? { join?: boolean }
function M.update_progress(buf, o)
  if not opts().progress or not has_cookies(buf) then
    return false
  end
  local p = ts.parser(buf)
  if not p then
    return false
  end
  local tree = p:parse()[1]
  if not tree then
    return false
  end
  local edits = {}
  -- fill the cookies on `row` from byte `from`; returns how many it found
  local function fill(row, from, done, total)
    local line = get_line(buf, row)
    local n = 0
    for _, cookie in ipairs(find_cookies(line, from)) do
      -- `[/]` written in inline code is an example, not a cookie
      if not ts.code_context(ts.parse(buf, row), row, cookie.s - 1) then
        n = n + 1
        local text
        if cookie.pct then
          text = ("[%d%%]"):format(total == 0 and 0 or math.floor(done * 100 / total))
        else
          text = ("[%d/%d]"):format(done, total)
        end
        if line:sub(cookie.s, cookie.e - 1) ~= text then
          table.insert(edits, { row, cookie.s - 1, cookie.e - 1, text })
        end
      end
    end
    return n
  end
  local visit
  -- done / total over the items of `list` that count as tasks
  local function count(list)
    local done, total = 0, 0
    for _, li in ipairs(list_items(list)) do
      local state = visit(li)
      if state ~= nil then
        total = total + 1
        done = done + (state and 1 or 0)
      end
    end
    return done, total
  end
  -- returns: the task state (checked / unchecked) of `node` as a child, or nil
  visit = function(node)
    local done, total = 0, 0
    for c in node:iter_children() do
      if c:type() == "list" then
        local d, t = count(c)
        done, total = done + d, total + t
      end
    end
    local row = node:range()
    local item = M.parse(get_line(buf, row))
    if not item then
      return nil
    end
    local found = fill(row, item.text_col + 1, done, total)
    if item.check then
      return item.check ~= " "
    elseif found > 0 then
      return total > 0 and done == total
    end
    return nil
  end
  local function walk(n)
    local t = n:type()
    if t == "list_item" then
      return visit(n) -- visit() recurses into nested lists itself
    elseif t == "list" then
      local done, total = count(n)
      local row = label_row(buf, n)
      if row and not M.parse(get_line(buf, row)) then
        fill(row, 1, done, total)
      end
      return
    end
    for c in n:iter_children() do
      walk(c)
    end
  end
  walk(tree:root())
  if #edits == 0 then
    return false
  end
  table.sort(edits, function(a, b)
    return a[1] > b[1] or (a[1] == b[1] and a[2] > b[2])
  end)
  if o and o.join then
    pcall(vim.cmd, "undojoin")
  end
  for _, e in ipairs(edits) do
    api.nvim_buf_set_text(buf, e[1], e[2], e[1], e[3], { e[4] })
  end
  return true
end

--- Normal-mode <CR>: toggle the checkbox on the current list item.
function M.toggle_checkbox()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  util.undo_break(buf)
  set_checkbox(buf, row - 1, nil)
  M.update_progress(buf)
  local line = get_line(buf, row - 1)
  api.nvim_win_set_cursor(0, { row, math.min(col, math.max(0, #line - 1)) })
end

--- Visual <CR>: check every item in the range, or uncheck all if all are checked.
function M.toggle_range(srow, erow)
  local buf = api.nvim_get_current_buf()
  local all_checked = true
  local any = false
  for r = srow, erow do
    local item = M.parse(get_line(buf, r))
    if item and not in_code(buf, r) then
      any = true
      if item.check == nil or item.check == " " then
        all_checked = false
      end
    end
  end
  if not any then
    return
  end
  util.undo_break(buf)
  local state = all_checked and " " or "x"
  for r = srow, erow do
    if not in_code(buf, r) then
      set_checkbox(buf, r, state)
    end
  end
  M.update_progress(buf)
end

function M.toggle_visual()
  local buf = api.nvim_get_current_buf()
  M.toggle_range(api.nvim_buf_get_mark(buf, "<")[1] - 1, api.nvim_buf_get_mark(buf, ">")[1] - 1)
end

-- Keymap entry points -------------------------------------------------------------

local function cmd(fn, arg)
  return ("<Cmd>lua require('markwright.lists').%s(%s)<CR>"):format(fn, arg or "")
end

local function cursor_item()
  local buf = api.nvim_get_current_buf()
  return M.item_at(buf, api.nvim_win_get_cursor(0)[1] - 1), buf
end

--- Insert-mode <CR>.
local function quote_continues(buf)
  local callouts = require("markwright.callouts")
  return callouts.continues(buf, api.nvim_win_get_cursor(0)[1] - 1)
end

function M.expr_enter()
  local item, buf = cursor_item()
  if util.completion_active() then
    return util.fallback(buf, "i", "<CR>")
  end
  if item and opts().continue_on_enter then
    return cmd("enter")
  end
  if not item and quote_continues(buf) then
    local col = api.nvim_win_get_cursor(0)[2]
    local prefix = require("markwright.callouts").quote_prefix(api.nvim_get_current_line())
    if col >= #prefix:gsub("%s+$", "") then
      return "<Cmd>lua require('markwright.callouts').enter()<CR>"
    end
  end
  return util.fallback(buf, "i", "<CR>")
end

--- Normal-mode o / O.
function M.expr_open(below)
  local key = below and "o" or "O"
  local item, buf = cursor_item()
  if item and opts().continue_on_enter then
    return cmd("open", tostring(below))
  end
  if not item and quote_continues(buf) then
    return ("<Cmd>lua require('markwright.callouts').open(%s)<CR>"):format(tostring(below))
  end
  return key
end

--- Normal-mode checkbox key (<CR> by default).
function M.expr_checkbox()
  local item, buf = cursor_item()
  if not item then
    return util.fallback(buf, "n", opts().checkbox_key)
  end
  -- repeatable with `.`
  return util.repeat_keys(function()
    M.toggle_checkbox()
  end)
end

--- Insert-mode <Tab>/<S-Tab>: table cell navigation, list nesting, or fallback.
function M.expr_tab(dir)
  local lhs = dir > 0 and "<Tab>" or "<S-Tab>"
  local buf = api.nvim_get_current_buf()
  if util.completion_active(dir) then
    return util.fallback(buf, "i", lhs)
  end
  local tables = require("markwright.tables")
  if tables.at_cursor(buf) then
    return ("<Cmd>lua require('markwright.tables').next_cell(%d)<CR>"):format(dir)
  end
  if opts().tab_indent and cursor_item() then
    return cmd("indent", tostring(dir))
  end
  return util.fallback(buf, "i", lhs)
end

---@type table<integer, integer[]> rows changed since the last pass: { lo, hi }
local dirty = {}
local busy = {}

--- Track changed rows, so lists changed away from the cursor (`:g`, `:m`,
--- `.` elsewhere) are renumbered too, and remember the lists' starts.
function M.attach(buf)
  dirty[buf] = nil
  remember(buf, 0, api.nvim_buf_line_count(buf) - 1)
  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, first, _, last_new)
      if busy[b] then
        return
      end
      local d = dirty[b]
      dirty[b] = d and { math.min(d[1], first), math.max(d[2], last_new) } or { first, last_new }
    end,
    on_reload = function(_, b)
      -- :e! — remember the reloaded lists, but don't renumber what the
      -- user didn't touch
      dirty[b] = nil
      vim.schedule(function()
        if api.nvim_buf_is_valid(b) then
          remember(b, 0, api.nvim_buf_line_count(b) - 1)
        end
      end)
    end,
    on_detach = function(_, b)
      dirty[b], busy[b], starts[b] = nil, nil, nil
    end,
  })
end

--- Ordered lists (outermost) intersecting rows [lo, hi]: their first rows
--- and the rows they span.
local function lists_in(buf, lo, hi)
  local p = ts.parser(buf)
  local tree = p and p:parse()[1]
  local out = {}
  if not tree then
    return out
  end
  local function walk(node)
    local sr, _, er, ec = node:range()
    if ec == 0 and er > sr then
      er = er - 1
    end
    if er < lo or sr > hi then
      return
    end
    if node:type() == "list" then
      table.insert(out, { sr, er })
      return -- nested lists are renumbered with their parent
    end
    for c in node:iter_children() do
      walk(c)
    end
  end
  walk(tree:root())
  return out
end

--- A list whose first item was deleted may stop being a list: an ordered
--- item can only interrupt a paragraph (or start a sub-list right under its
--- parent's text) when it is numbered 1, so `   2. y` left under `1. a` is
--- plain text. Where a list that started at 1 lost its first item, put the 1
--- back on the item now in its place.
local function revive(buf, lo, hi)
  local data = starts[buf] or {}
  local p
  for _, mk in ipairs(api.nvim_buf_get_extmarks(buf, start_ns, { lo, 0 }, { hi, -1 }, { details = true })) do
    local d = data[mk[1]]
    local row = mk[2]
    if d and d.start == 1 and mk[4].invalid then
      local line = get_line(buf, row)
      local ind, num = line:match("^([%s>]*)(%d+)[.)]%s")
      if num and num ~= "1" and #ind == d.col then
        p = p or ts.parse(buf, lo, hi)
        local item = p and ts.ancestor(ts.block_node(p, row, #ind), { list_item = true })
        if not (item and item:range() == row) then
          pcall(vim.cmd, "undojoin")
          api.nvim_buf_set_text(buf, row, #ind, row, #ind + #num, { "1" })
          p = nil
        end
      end
    end
  end
end

--- TextChanged / InsertLeave: renumber the lists that changed (and the one
--- around the cursor), then remember their starts.
---@param o? { undo?: boolean } after undo/redo: don't edit, just remember
function M.on_change(o)
  local buf = api.nvim_get_current_buf()
  if not (o and o.undo) then
    busy[buf] = true
    local ok, err = pcall(M.update_progress, buf, { join = true })
    busy[buf] = nil
    if not ok then
      error(err)
    end
  end
  local d = dirty[buf]
  dirty[buf] = nil
  if not opts().auto_renumber then
    return
  end
  local last = api.nvim_buf_line_count(buf) - 1
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local lo, hi = row, row
  if d then
    lo, hi = math.min(lo, d[1]), math.max(hi, d[2])
  end
  lo, hi = math.max(0, lo - 1), math.min(last, hi + 1)
  -- cheap check before parsing: an ordered item or a remembered start nearby
  local near = #api.nvim_buf_get_extmarks(buf, start_ns, { lo, 0 }, { hi, -1 }, { limit = 1 }) > 0
  if not near then
    for _, l in ipairs(api.nvim_buf_get_lines(buf, lo, hi + 1, false)) do
      if l:match("^[%s>]*%d+[.)]") then
        near = true
        break
      end
    end
  end
  if not near then
    return
  end
  busy[buf] = true
  local ok, err = pcall(function()
    if not (o and o.undo) then
      revive(buf, lo, hi)
    end
    for _, l in ipairs(lists_in(buf, lo, hi)) do
      lo, hi = math.min(lo, l[1]), math.max(hi, l[2])
      if not (o and o.undo) then
        M.renumber(buf, l[1], { join = true })
      end
    end
    remember(buf, lo, hi)
  end)
  busy[buf] = nil
  if not ok then
    error(err)
  end
end

return M
