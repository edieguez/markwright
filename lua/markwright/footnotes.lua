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

--- Insert `[^n]` after the cursor, add `[^n]: ` at the end of the file and
--- jump there in insert mode. `<C-o>` returns to the reference.
function M.insert()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  if ts.code_context(ts.parse(buf, row), row, col) then
    return util.warn("footnotes skipped inside code")
  end
  local n = M.next_id(buf)
  local ref = ("[^%d]"):format(n)
  local line = api.nvim_get_current_line()
  local at = (line == "") and 0 or col + util.char_len(line, col)

  util.undo_break(buf)
  api.nvim_buf_set_text(buf, row, at, row, at, { ref })

  -- definitions go at the end, grouped with existing ones
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local last = #lines
  while last > 0 and lines[last]:match("^%s*$") do
    last = last - 1
  end
  local def = ref .. ": "
  local new
  if last == 0 then
    new = { def }
  elseif lines[last]:match(DEF) then
    new = { def }
  else
    new = { "", def }
  end
  api.nvim_buf_set_lines(buf, last, last, false, new)

  api.nvim_win_set_cursor(0, { row + 1, at + #ref - 1 })
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { last + #new, #def })
  vim.cmd("startinsert!")
end

return M
