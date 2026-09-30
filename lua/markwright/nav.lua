-- Heading navigation and outline. Spec: SPEC.md section 14.9.
local api = vim.api
local config = require("markwright.config")
local doc = require("markwright.doc")

local M = {}

local function cursor_row()
  return api.nvim_win_get_cursor(0)[1] - 1
end

local function is_pending()
  return vim.fn.mode(true):match("^no") ~= nil
end

--- Move to a heading row: adds a jumplist entry in normal/visual mode.
local function go(row)
  if not is_pending() then
    vim.cmd("normal! m'")
  end
  api.nvim_win_set_cursor(0, { row + 1, 0 })
end

--- Index of the heading whose section contains `row` (nil before the first).
local function current_index(hs, row)
  local idx
  for i, h in ipairs(hs) do
    if h.row <= row then
      idx = i
    else
      break
    end
  end
  return idx
end

--- ]] / [[: next or previous heading of any level (count times).
function M.heading(dir, count)
  local hs = doc.headings(api.nvim_get_current_buf())
  local row = cursor_row()
  local target
  count = count or vim.v.count1
  if dir > 0 then
    local n = 0
    for _, h in ipairs(hs) do
      if h.row > row then
        n = n + 1
        target = h.row
        if n == count then
          break
        end
      end
    end
  else
    local n = 0
    for i = #hs, 1, -1 do
      if hs[i].row < row then
        n = n + 1
        target = hs[i].row
        if n == count then
          break
        end
      end
    end
  end
  if target then
    go(target)
  end
end

--- ][ / []: next or previous heading of the same level, within the parent
--- section. From inside a section, [] first goes to that section's heading.
function M.sibling(dir, count)
  local hs = doc.headings(api.nvim_get_current_buf())
  local row = cursor_row()
  local idx = current_index(hs, row)
  count = count or vim.v.count1
  if not idx then
    if dir > 0 and hs[1] then
      go(hs[1].row)
    end
    return
  end
  if dir < 0 and hs[idx].row ~= row then
    count = count - 1 -- reaching the own heading is the first step
  end
  local level = hs[idx].level
  for _ = 1, count do
    local found
    local i = idx + dir
    while i >= 1 and i <= #hs do
      if hs[i].level < level then
        break -- left the parent section
      end
      if hs[i].level == level then
        found = i
        break
      end
      i = i + dir
    end
    if not found then
      break
    end
    idx = found
  end
  if hs[idx].row ~= row then
    go(hs[idx].row)
  end
end

--- [u: parent heading (count levels up).
function M.parent(count)
  local hs = doc.headings(api.nvim_get_current_buf())
  local idx = current_index(hs, cursor_row())
  if not idx then
    return
  end
  for _ = 1, count or vim.v.count1 do
    local level = hs[idx].level
    local found
    for i = idx - 1, 1, -1 do
      if hs[i].level < level then
        found = i
        break
      end
    end
    if not found then
      break
    end
    idx = found
  end
  if hs[idx].row ~= cursor_row() then
    go(hs[idx].row)
  end
end

-- Outline ---------------------------------------------------------------------------

--- Picker entries for the buffer's headings.
function M.outline_items(buf)
  local hs = doc.headings(buf)
  local cur = current_index(hs, cursor_row())
  local items = {}
  for i, h in ipairs(hs) do
    table.insert(items, {
      row = h.row,
      level = h.level,
      text = h.text,
      current = i == cur,
      label = ("%s%s%s %s"):format(
        i == cur and "› " or "  ",
        string.rep("  ", h.level - 1),
        string.rep("#", h.level),
        h.text
      ),
    })
  end
  return items
end

--- Pick a heading and jump to it (vim.ui.select: snacks/telescope/fzf-lua when
--- they provide it, the built-in list otherwise).
function M.outline()
  local buf = api.nvim_get_current_buf()
  local items = M.outline_items(buf)
  if #items == 0 then
    return require("markwright.util").notify("no headings")
  end
  local win = api.nvim_get_current_win()
  vim.ui.select(items, {
    prompt = "Headings",
    kind = "markwright_outline",
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if not item or not api.nvim_win_is_valid(win) then
      return
    end
    api.nvim_set_current_win(win)
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(win, { item.row + 1, 0 })
    vim.cmd("normal! zv")
  end)
end

-- Mappings --------------------------------------------------------------------------

local function motion(fn_call)
  return ("<Cmd>lua require('markwright.nav').%s<CR>"):format(fn_call)
end

function M.attach(buf)
  local o = config.options.nav
  if not o or o.enabled == false then
    return
  end
  local function map(lhs, rhs, desc, modes)
    if lhs and lhs ~= "" then
      vim.keymap.set(
        modes or { "n", "x", "o" },
        lhs,
        rhs,
        { buffer = buf, silent = true, desc = "markwright: " .. desc }
      )
    end
  end
  -- counts are read inside the functions (vim.v.count1), so pass nothing here
  map(o.next, motion("heading(1)"), "Next heading")
  map(o.prev, motion("heading(-1)"), "Previous heading")
  map(o.next_sibling, motion("sibling(1)"), "Next heading, same level")
  map(o.prev_sibling, motion("sibling(-1)"), "Previous heading, same level")
  map(o.parent, motion("parent()"), "Parent heading")
  local outline = o.outline
  if outline == nil then
    outline = config.options.keymaps.enabled and (config.options.keymaps.prefix .. "o") or nil
  end
  map(outline, M.outline, "Outline (jump to a heading)", { "n" })
end

return M
