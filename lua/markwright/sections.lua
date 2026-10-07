-- Heading sections: move a section (heading, content and sub-sections) past
-- its siblings, promote / demote it with its sub-headings.
-- Spec: SPEC.md section 14.16.
local api = vim.api
local doc = require("markwright.doc")
local util = require("markwright.util")

local M = {}

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function blank(line)
  return line:match("^%s*$") ~= nil
end

-- footnote and reference definitions (`[^1]: …`, `[ref]: url`)
local function is_definition(line)
  return line:match("^%s*%[%^?[^%]]+%]:") ~= nil
end

---@class markwright.Section
---@field i integer index of the heading in `hs`
---@field level integer
---@field sr integer first row (the heading), 0-based
---@field er integer last row, 0-based

--- The section whose heading is `hs[i]`. The last section of the file stops
--- before a trailing block of footnote / reference definitions, which stays
--- at the end.
local function section(buf, hs, i)
  local h = hs[i]
  local er = api.nvim_buf_line_count(buf) - 1
  local last = true
  for k = i + 1, #hs do
    if hs[k].level <= h.level then
      er = hs[k].row - 1
      last = false
      break
    end
  end
  if last then
    -- keep definitions at the end of the file
    local r = er
    while r > h.row and (blank(get_line(buf, r)) or is_definition(get_line(buf, r))) do
      r = r - 1
    end
    local defs = false
    for k = r + 1, er do
      if is_definition(get_line(buf, k)) then
        defs = true
      end
    end
    if defs then
      er = r
    end
  end
  return { i = i, level = h.level, sr = h.row, er = er }
end

--- Index of the heading whose section holds `row` (the nearest above), or nil.
local function heading_index(hs, row)
  local found
  for k, h in ipairs(hs) do
    if h.row <= row then
      found = k
    else
      break
    end
  end
  return found
end

--- The section of the next / previous sibling (same level, same parent).
local function sibling(buf, hs, sec, dir)
  if dir > 0 then
    local nxt = section(buf, hs, sec.i)
    for k = sec.i + 1, #hs do
      if hs[k].row > nxt.er then
        if hs[k].level == sec.level then
          return section(buf, hs, k)
        end
        return nil
      end
    end
    return nil
  end
  for k = sec.i - 1, 1, -1 do
    if hs[k].level < sec.level then
      return nil
    elseif hs[k].level == sec.level then
      return section(buf, hs, k)
    end
  end
end

--- Split rows into the content and the count of trailing blank lines.
local function split(lines)
  local n = #lines
  while n > 0 and blank(lines[n]) do
    n = n - 1
  end
  return vim.list_slice(lines, 1, n), #lines - n
end

--- Move the section under the cursor down (dir = 1) or up (dir = -1) past
--- [count] siblings, with its sub-sections. The cursor moves with it.
function M.move(dir)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local hs = doc.headings(buf)
  local i = heading_index(hs, row)
  if not i then
    return util.warn("not in a section")
  end
  local moved = false
  for _ = 1, util.count1() do
    local cur = section(buf, hs, i)
    local other = sibling(buf, hs, cur, dir)
    if not other then
      break
    end
    local a, b = cur, other
    if dir < 0 then
      a, b = other, cur
    end
    -- swap a and b (a above b, adjacent); the gaps stay where they were
    local la, gap_a = split(api.nvim_buf_get_lines(buf, a.sr, a.er + 1, false))
    local lb, gap_b = split(api.nvim_buf_get_lines(buf, b.sr, b.er + 1, false))
    local out = vim.list_extend({}, lb)
    for _ = 1, gap_a do
      table.insert(out, "")
    end
    vim.list_extend(out, la)
    for _ = 1, gap_b do
      table.insert(out, "")
    end
    if not moved then
      util.undo_break(buf)
    end
    api.nvim_buf_set_lines(buf, a.sr, b.er + 1, false, out)
    moved = true
    local offset = row - cur.sr
    if dir > 0 then
      row = a.sr + #lb + gap_a + offset
    else
      row = a.sr + offset
    end
    hs = doc.headings(buf)
    i = heading_index(hs, row)
  end
  if moved then
    api.nvim_win_set_cursor(0, { row + 1, col })
  end
end

--- Add (delta > 0) or remove (delta < 0) `#` on the heading under the cursor
--- and all its sub-headings, [count] levels. Refused when a heading would
--- go past level 6, or the section's heading would stop being one.
function M.change(delta)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local hs = doc.headings(buf)
  local i = heading_index(hs, row)
  if not i then
    return util.warn("not in a section")
  end
  local sec = section(buf, hs, i)
  delta = delta * util.count1()
  local rows = {}
  for k = i, #hs do
    if hs[k].row > sec.er then
      break
    end
    local lv = hs[k].level + delta
    if lv > 6 then
      return util.warn("a sub-heading would go past level 6")
    elseif lv < 1 then
      return util.warn("can't promote a level-1 heading")
    end
    table.insert(rows, hs[k].row)
  end
  util.undo_break(buf)
  -- bottom-up: setext headings shrink to one line
  for k = #rows, 1, -1 do
    require("markwright.headings").change(buf, rows[k], rows[k], delta, { no_break = true, quiet = true })
  end
end

return M
