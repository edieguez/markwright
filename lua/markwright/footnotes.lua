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

return M
