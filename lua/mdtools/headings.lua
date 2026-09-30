-- Headings: add / remove `#`. Spec: SPEC.md section 9.1.
local api = vim.api
local ts = require("mdtools.ts")
local util = require("mdtools.util")

local M = {}

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

--- Convert a setext heading containing `row` to ATX. Returns the row of the
--- resulting heading (or nil if `row` isn't in a setext heading).
local function setext_to_atx(buf, row)
  local p = ts.parse(buf, row, row + 1)
  if not p then
    return nil
  end
  local node = ts.ancestor(ts.block_node(p, row, 0), { setext_heading = true })
  if not node then
    return nil
  end
  local sr, _, er, ec = node:range()
  if ec == 0 then
    er = er - 1
  end
  local level = 1
  local parts = {}
  for c in node:iter_children() do
    if c:type() == "setext_h2_underline" then
      level = 2
    elseif c:type() == "paragraph" then
      for g in c:iter_children() do
        if g:type() == "inline" then
          local t = vim.treesitter.get_node_text(g, buf):gsub("%s*\n%s*", " ")
          table.insert(parts, t)
        end
      end
    end
  end
  local text = vim.trim(table.concat(parts, " "))
  api.nvim_buf_set_lines(buf, sr, er + 1, false, { string.rep("#", level) .. " " .. text })
  return sr
end

--- Change the `#` count of one line by `delta` (clamped to 0..6).
--- Returns true if the line changed.
local function change_line(buf, row, delta)
  local line = get_line(buf, row)
  if line:match("^%s*$") then
    return false
  end
  local indent, hashes, rest = line:match("^( ? ? ?)(#+)%s+(.*)$")
  if not hashes then
    indent, hashes = line:match("^( ? ? ?)(#+)$")
    rest = ""
  end
  if hashes and #hashes > 6 then
    hashes = nil
  end
  local level = hashes and #hashes or 0
  local text = hashes and rest or vim.trim(line)
  local new = math.max(0, math.min(6, level + delta))
  if new == level then
    return false
  end
  local out = new == 0 and text or (string.rep("#", new) .. (text ~= "" and " " .. text or ""))
  if new > 0 and hashes then
    out = indent .. out
  end
  api.nvim_buf_set_lines(buf, row, row + 1, false, { out })
  return true
end

--- Add (delta > 0) or remove (delta < 0) `#` on rows srow..erow (0-based).
function M.change(buf, srow, erow, delta)
  util.undo_break(buf)
  local changed = false
  local r = srow
  while r <= erow do
    if ts.code_context(ts.parse(buf, r), r, 0) ~= "block" then
      local before = api.nvim_buf_line_count(buf)
      local atx = setext_to_atx(buf, r)
      if atx then
        local removed = before - api.nvim_buf_line_count(buf)
        erow = erow - removed
        r = atx
        changed = true
      end
      if change_line(buf, r, delta) then
        changed = true
      end
    end
    r = r + 1
  end
  if not changed then
    util.notify(delta > 0 and "already at level 6" or "not a heading")
  end
  return changed
end

--- Normal mode: current line, `count` levels.
function M.change_cursor(delta)
  local count = math.max(vim.v.count1, 1)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  M.change(buf, row, row, delta * count)
  local line = get_line(buf, row)
  local text_col = #(line:match("^%s*#+%s+") or "")
  api.nvim_win_set_cursor(0, { row + 1, math.min(text_col, math.max(0, #line - 1)) })
end

function M.change_visual(delta)
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "<")[1] - 1
  local e = api.nvim_buf_get_mark(buf, ">")[1] - 1
  M.change(buf, s, e, delta * math.max(vim.v.count1, 1))
end

return M
