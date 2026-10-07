-- Footnotes. Spec: SPEC.md section 9.5 (navigation lives in follow.lua).
local api = vim.api
local ts = require("markwright.ts")
local util = require("markwright.util")
local doc = require("markwright.doc")

local M = {}

local DEF = "^%s*%[%^[^%]%s]+%]:"

--- Next free numeric footnote id.
function M.next_id(buf)
  local refs, defs = doc.footnotes(buf)
  local max = 0
  for _, r in ipairs(refs) do
    max = math.max(max, tonumber(r.id) or 0)
  end
  for id in pairs(defs) do
    max = math.max(max, tonumber(id) or 0)
  end
  return max + 1
end

--- Insert `[^n]` at byte column `at` of 0-based `row` and add an empty
--- `[^n]: ` definition at the end of the file.
---@return string ref, integer def_row 0-based row of the definition
function M.add(buf, row, at)
  local n = M.next_id(buf)
  local ref = ("[^%d]"):format(n)
  api.nvim_buf_set_text(buf, row, at, row, at, { ref })

  -- definitions go at the end, grouped with existing ones
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local last = #lines
  while last > 0 and lines[last]:match("^%s*$") do
    last = last - 1
  end
  local def = ref .. ": "
  local new
  if last == 0 or lines[last]:match(DEF) then
    new = { def }
  else
    new = { "", def }
  end
  api.nvim_buf_set_lines(buf, last, last, false, new)
  return ref, last + #new - 1
end

local function in_code(buf, row, col)
  return ts.code_context(ts.parse(buf, row), row, col) ~= nil
end

--- Insert `[^n]` after the cursor, add `[^n]: ` at the end of the file and
--- jump there in insert mode. `<C-o>` returns to the reference.
function M.insert()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  if in_code(buf, row, col) then
    return util.warn("footnotes skipped inside code")
  end
  local line = api.nvim_get_current_line()
  local at = (line == "") and 0 or col + util.char_len(line, col)

  util.undo_break(buf)
  local ref, def_row = M.add(buf, row, at)

  api.nvim_win_set_cursor(0, { row + 1, at + #ref - 1 })
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { def_row + 1, #ref + 2 })
  vim.cmd("startinsert!")
end

--- Insert mode (`;;n`): insert `[^n]` at the cursor and add its definition,
--- but keep typing after the reference. `gx` on it jumps to the definition.
function M.insert_inline()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  if in_code(buf, row, math.max(0, col - 1)) then
    return util.warn("footnotes skipped inside code")
  end
  local ref = M.add(buf, row, col)
  api.nvim_win_set_cursor(0, { row + 1, col + #ref })
end

-- Renumbering ----------------------------------------------------------------

local function is_def_line(line)
  return line:match("^%s*%[%^[^%]%s]+%]:") ~= nil
end

--- Last row (0-based) of the definition starting at `row`: continuation
--- lines are indented, and may follow blank lines.
local function def_end(lines, row)
  local last, r = row, row + 1
  while r < #lines do
    local l = lines[r + 1]
    if l:match("^%s*$") then
      r = r + 1
    elseif l:match("^%s+%S") and not is_def_line(l) then
      last = r
      r = r + 1
    else
      break
    end
  end
  return last
end

--- Renumber numeric footnotes by their first reference: the first one in
--- the text becomes [^1], and so on. Named footnotes ([^note]) are left
--- alone; numeric definitions nobody references come after the referenced
--- ones. Definitions that stand together (only blank lines between them)
--- are put in the new order; a definition elsewhere is relabeled in place.
---@return boolean changed
function M.renumber(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  local refs, defs = doc.footnotes(buf)
  local new, n = {}, 0
  for _, r in ipairs(refs) do
    if r.id:match("^%d+$") and not new[r.id] then
      n = n + 1
      new[r.id] = tostring(n)
    end
  end
  local orphans = {}
  for id, d in pairs(defs) do
    if id:match("^%d+$") and not new[id] then
      table.insert(orphans, { id = id, row = d.row })
    end
  end
  table.sort(orphans, function(a, b)
    return a.row < b.row
  end)
  for _, o in ipairs(orphans) do
    n = n + 1
    new[o.id] = tostring(n)
  end
  local changed = false
  for old, nw in pairs(new) do
    if old ~= nw then
      changed = true
    end
  end

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local out = vim.deepcopy(lines)
  -- references, right to left on each line
  local by_row = {}
  for _, r in ipairs(refs) do
    if new[r.id] then
      by_row[r.row] = by_row[r.row] or {}
      table.insert(by_row[r.row], r)
    end
  end
  for row, list in pairs(by_row) do
    table.sort(list, function(a, b)
      return a.col > b.col
    end)
    local l = out[row + 1]
    for _, r in ipairs(list) do
      l = l:sub(1, r.col) .. "[^" .. new[r.id] .. "]" .. l:sub(r.ecol + 1)
    end
    out[row + 1] = l
  end
  -- definition labels
  local blocks = {} -- numeric definitions: { sr, er, num }
  for id, d in pairs(defs) do
    if new[id] then
      local l = out[d.row + 1]
      local s, e = l:find("%[%^[^%]%s]+%]:", d.col + 1)
      out[d.row + 1] = l:sub(1, s - 1) .. "[^" .. new[id] .. "]:" .. l:sub(e + 1)
      table.insert(blocks, { sr = d.row, er = def_end(lines, d.row), num = tonumber(new[id]) })
    end
  end
  table.sort(blocks, function(a, b)
    return a.sr < b.sr
  end)
  -- runs of definitions with only blank lines (or other definitions) between
  local function only_defs_between(a, b)
    local r = a.er + 1
    while r < b.sr do
      local l = lines[r + 1]
      if not l:match("^%s*$") then
        if not is_def_line(l) then
          return false
        end
        r = def_end(lines, r) + 1
      else
        r = r + 1
      end
    end
    return true
  end
  local runs, cur = {}, nil
  for _, b in ipairs(blocks) do
    if cur and only_defs_between(cur[#cur], b) then
      table.insert(cur, b)
    else
      cur = { b }
      table.insert(runs, cur)
    end
  end
  for _, run in ipairs(runs) do
    local sorted = vim.list_slice(run)
    table.sort(sorted, function(a, b)
      return a.num < b.num
    end)
    local moved = false
    for k = 1, #run do
      if sorted[k] ~= run[k] then
        moved = true
      end
    end
    if moved then
      changed = true
      -- fill the slots bottom-up with the blocks in their new order
      local texts = {}
      for k, b in ipairs(sorted) do
        texts[k] = vim.list_slice(out, b.sr + 1, b.er + 1)
      end
      for k = #run, 1, -1 do
        local slot = run[k]
        local repl = texts[k]
        for _ = slot.sr, slot.er do
          table.remove(out, slot.sr + 1)
        end
        for j = #repl, 1, -1 do
          table.insert(out, slot.sr + 1, repl[j])
        end
      end
    end
  end

  if not changed then
    util.notify("footnotes are already in order")
    return false
  end
  -- write only the rows that differ
  local first, last_old, last_new = 1, #lines, #out
  while first <= last_old and first <= last_new and lines[first] == out[first] do
    first = first + 1
  end
  while last_old >= first and last_new >= first and lines[last_old] == out[last_new] do
    last_old, last_new = last_old - 1, last_new - 1
  end
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, first - 1, last_old, false, vim.list_slice(out, first, last_new))
  util.notify(("renumbered %d footnote%s"):format(n, n == 1 and "" or "s"))
  return true
end

return M
