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

-- Key fallbacks ------------------------------------------------------------
-- mdtools overrides keys like <Tab>/<CR> only in specific contexts; everywhere
-- else the mapping that existed before (completion, autopairs...) must run.

--- Completion menu or snippet active? Then the key belongs to them.
function M.completion_active(dir)
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
  if dir and vim.snippet and vim.snippet.active({ direction = dir }) then
    return true
  end
  return false
end

M._fallback = {} ---@type table<string, table>

local function fkey(buf, mode, lhs)
  return buf .. ":" .. mode .. ":" .. lhs
end

--- Remember the mapping that exists before ours (call before mapping).
function M.save_fallback(buf, mode, lhs)
  local m = vim.fn.maparg(lhs, mode, false, true)
  M._fallback[fkey(buf, mode, lhs)] = (m and not vim.tbl_isempty(m)) and m or nil
end

function M._run_fallback(key)
  local m = M._fallback[key]
  if m and m.callback then
    m.callback()
  end
end

--- Keys to return from an `expr` mapping to run the previous behavior.
function M.fallback(buf, mode, lhs)
  local key = fkey(buf, mode, lhs)
  local m = M._fallback[key]
  if not m then
    return lhs
  end
  if m.callback then
    if m.expr == 1 then
      return m.callback() or ""
    end
    return ("<Cmd>lua require('mdtools.util')._run_fallback(%q)<CR>"):format(key)
  end
  if m.rhs and m.rhs ~= "" then
    if m.expr == 1 then
      return vim.api.nvim_eval(m.rhs)
    end
    if m.noremap == 1 then
      return m.rhs
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(m.rhs, true, false, true), "m", false)
    return ""
  end
  return lhs
end

--- Length of blockquote prefixes ("> ", "> > ") at the start of a line.
function M.bq_len(line)
  local pos = 1
  while true do
    local s, e = line:find("^ ? ? ?>%s?", pos)
    if not s then
      break
    end
    pos = e + 1
  end
  return pos - 1
end

--- Shift a line's indentation (after any blockquote prefix) by `delta` columns.
function M.shift_line(line, delta)
  local bq = M.bq_len(line)
  if delta > 0 then
    return line:sub(1, bq) .. string.rep(" ", delta) .. line:sub(bq + 1)
  end
  local ws = #line:sub(bq + 1):match("^ *")
  local n = math.min(ws, -delta)
  return line:sub(1, bq) .. line:sub(bq + 1 + n)
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
