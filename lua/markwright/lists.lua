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

--- Find the first ordered item with a wrong number under `node`.
local function first_wrong(buf, node)
  if node:type() == "list" then
    local items = list_items(node)
    local nums = {}
    for i, it in ipairs(items) do
      nums[i] = (item_number(buf, it))
    end
    if nums[1] and not all_same(nums) then
      for i, it in ipairs(items) do
        local expected = nums[1] + i - 1
        if nums[i] and nums[i] ~= expected then
          return it, expected
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
    local new = state or (item.check == " " and "x" or " ")
    api.nvim_buf_set_text(buf, row, c + 1, row, c + 2, { new })
  elseif opts().checkbox_add then
    local box = "[" .. (state or " ") .. "] "
    if item.space == "" then
      box = " " .. box:gsub(" $", "")
    end
    api.nvim_buf_set_text(buf, row, c, row, c, { box })
  end
  return true
end

--- Normal-mode <CR>: toggle the checkbox on the current list item.
function M.toggle_checkbox()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  util.undo_break(buf)
  set_checkbox(buf, row - 1, nil)
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
  return cmd("toggle_checkbox")
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

--- TextChanged / InsertLeave: renumber the list around the cursor.
function M.on_change()
  if not opts().auto_renumber then
    return
  end
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  -- only when an ordered item is nearby (cheap check before parsing)
  for r = math.max(0, row - 1), math.min(api.nvim_buf_line_count(buf) - 1, row + 1) do
    if get_line(buf, r):match("^[%s>]*%d+[.)]") then
      M.renumber(buf, row, { join = true })
      return
    end
  end
end

return M
