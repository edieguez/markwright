local api = vim.api
local M = {}

function M.notify(msg, level)
  vim.notify("markwright: " .. msg, level or vim.log.levels.INFO)
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
---@class markwright.EditTracker
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
---@param tr markwright.EditTracker
function M.set_text(buf, tr, row, scol, ecol, text)
  vim.api.nvim_buf_set_text(buf, row, scol, row, ecol, { text })
  tr:add(row, scol, #text - (ecol - scol))
end

--- Start a new undo block so each plugin action is one undo step
--- (API edits are otherwise joined with the previous change).
function M.undo_break(buf)
  -- setting 'undolevels' syncs undo for the *current* buffer: run it in `buf`,
  -- since callbacks (pickers, prompts) can fire while another window is current
  vim.api.nvim_buf_call(buf, function()
    vim.bo[buf].undolevels = vim.bo[buf].undolevels
  end)
end

-- Key fallbacks ------------------------------------------------------------
-- markwright overrides keys like <Tab>/<CR> only in specific contexts; everywhere
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
    return ("<Cmd>lua require('markwright.util')._run_fallback(%q)<CR>"):format(key)
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

-- Dot-repeat --------------------------------------------------------------------
--
-- Actions that aren't operators become repeatable with `.` by running them
-- from an operator function: the key returns `g@l` (normal mode, the cursor
-- stays where it is) or `g@` (visual mode, the selected lines), and `.`
-- runs the operator again at the new cursor or over as many lines. Prompts
-- go through M.input / M.select: the first run records the answers, `.`
-- reuses them (like vim-surround), and asks only for what it doesn't have.

---@class markwright.Repeat
---@field fn fun(r: markwright.Repeat, srow: integer, erow: integer)
---@field count integer
---@field visual boolean
---@field replay boolean false on the first run, true when repeated with `.`
---@field answers any[]
---@field n integer prompts asked in this run

M._rep = nil ---@type markwright.Repeat?
M._active = nil ---@type markwright.Repeat?
M._count = nil ---@type integer?

--- `vim.v.count1`, or the count of the action being repeated.
function M.count1()
  return M._count or vim.v.count1
end

local function with_active(r, fn, ...)
  local prev_active, prev_count = M._active, M._count
  M._active, M._count = r, r.count
  local ok, err = pcall(fn, ...)
  M._active, M._count = prev_active, prev_count
  if not ok then
    error(err, 0)
  end
end

function M._repeat_op(mtype)
  local r = M._rep
  if not r then
    return
  end
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "[")
  local e = api.nvim_buf_get_mark(buf, "]")
  if not r.visual then
    -- `g@l` leaves the cursor where the key was pressed
    pcall(api.nvim_win_set_cursor, 0, { s[1], s[2] })
  end
  r.n = 0
  with_active(r, r.fn, r, s[1] - 1, e[1] - 1, mtype)
  r.replay = true
end

local function start(fn, visual)
  M._rep = { fn = fn, count = vim.v.count1, visual = visual, replay = false, answers = {}, n = 0 }
  vim.o.operatorfunc = "v:lua.require'markwright.util'._repeat_op"
end

--- `expr` rhs for a normal-mode action repeatable with `.`. `fn(r)` runs
--- with the cursor where the key was pressed; `M.count1()` gives the count.
---@param fn fun(r: markwright.Repeat)
function M.repeatable(fn)
  return function()
    start(fn, false)
    return "g@l"
  end
end

--- `expr` rhs for a visual-mode action over the selected lines, repeatable
--- with `.` over as many lines. `fn(r, srow, erow)`, 0-based rows.
---@param fn fun(r: markwright.Repeat, srow: integer, erow: integer)
function M.repeatable_visual(fn)
  return function()
    start(fn, true)
    return "g@"
  end
end

--- Run `fn` as the action of the next `g@l` from an `expr` mapping that
--- already decided to act (e.g. after inspecting the cursor).
function M.repeat_keys(fn)
  start(fn, false)
  return "g@l"
end

-- prompts: record answers on the first run, reuse them when repeated
local function prompt(kind, items, opts, cb)
  local r = M._active
  if r then
    r.n = r.n + 1
    local i = r.n
    if r.replay and r.answers[i] ~= nil then
      local a = r.answers[i]
      return with_active(r, cb, a ~= vim.NIL and a or nil)
    end
    local real = cb
    cb = function(answer)
      r.answers[i] = answer == nil and vim.NIL or answer
      with_active(r, real, answer)
    end
  end
  if kind == "input" then
    vim.ui.input(opts, cb)
  else
    vim.ui.select(items, opts, cb)
  end
end

--- `vim.ui.input`, answered from memory when the action is repeated with `.`.
function M.input(opts, cb)
  prompt("input", nil, opts, cb)
end

--- `vim.ui.select`, answered from memory when the action is repeated with `.`.
function M.select(items, opts, cb)
  prompt("select", items, opts, cb)
end

return M
