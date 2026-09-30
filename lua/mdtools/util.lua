local M = {}

function M.notify(msg, level)
  vim.notify("mdtools: " .. msg, level or vim.log.levels.INFO)
end

function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

--- Byte length of the block prefix that formatting must never touch:
--- indentation, blockquote markers, list markers, task checkboxes, heading hashes.
---@param line string
---@return integer
function M.prefix_len(line)
  local pos = 1
  local function eat(pat)
    local s, e = line:find(pat, pos)
    if s == pos then
      pos = e + 1
      return true
    end
    return false
  end
  eat("^%s*")
  while eat("^>%s?") do
    eat("^%s*")
  end
  if eat("^#+%s+") then
    return pos - 1
  end
  if eat("^[-*+]%s+") or eat("^%d+[.)]%s+") then
    eat("^%[[ xX%-]%]%s+")
  end
  return pos - 1
end

--- Tracks byte-column edits so a saved position can follow them.
---@class mdtools.EditTracker
local Tracker = {}
Tracker.__index = Tracker

function M.tracker()
  return setmetatable({ edits = {} }, Tracker)
end

--- Record an edit at (row, col) that changed the line length by `delta`.
function Tracker:add(row, col, delta)
  table.insert(self.edits, { row = row, col = col, delta = delta })
end

--- Shift a 0-based {row, col} position through all recorded edits.
function Tracker:shift(pos)
  local row, col = pos[1], pos[2]
  for _, e in ipairs(self.edits) do
    if e.row == row and col >= e.col then
      col = math.max(e.col, col + e.delta)
    end
  end
  return { row, col }
end

--- Replace text in the buffer and record it in the tracker.
---@param buf integer
---@param tr mdtools.EditTracker
function M.set_text(buf, tr, row, scol, ecol, text)
  vim.api.nvim_buf_set_text(buf, row, scol, row, ecol, { text })
  tr:add(row, scol, #text - (ecol - scol))
end

--- Start a new undo block so each plugin action is one undo step
--- (API edits are otherwise joined with the previous change).
function M.undo_break(buf)
  vim.bo[buf].undolevels = vim.bo[buf].undolevels
end

--- Byte length of the (possibly multibyte) character starting at `col` (0-based).
function M.char_len(line, col)
  local b = line:byte(col + 1)
  if not b then
    return 0
  end
  if b >= 0xF0 then
    return 4
  elseif b >= 0xE0 then
    return 3
  elseif b >= 0xC0 then
    return 2
  end
  return 1
end

return M
