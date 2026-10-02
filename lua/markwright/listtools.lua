-- List tools: move items with their children, sort, convert lines <-> list styles.
-- Spec: SPEC.md section 14.12.
local api = vim.api
local ts = require("markwright.ts")
local util = require("markwright.util")
local lists = require("markwright.lists")

local M = {}

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function blank(line)
  return line:sub(util.bq_len(line) + 1):match("^%s*$") ~= nil
end

-- Items ---------------------------------------------------------------------------

--- The tree-sitter list_item on `row` (the innermost one starting there).
local function item_node(buf, row)
  local p = ts.parser(buf)
  if not p then
    return nil
  end
  p:parse()
  local line = get_line(buf, row)
  local item = lists.parse(line)
  if not item or ts.code_context(ts.parse(buf, row), row, 0) == "block" then
    return nil
  end
  local node = ts.block_node(p, row, item.marker_col)
  while node and node:type() ~= "list_item" do
    node = node:parent()
  end
  -- on a continuation line the innermost item may start above: fine, it's the item
  return node
end

--- First and last content row of an item (trailing blank lines excluded).
local function rows_of(buf, node)
  local sr, _, er, ec = node:range()
  local last = er
  if ec == 0 or get_line(buf, er):sub(1, ec):match("^[%s>]*$") then
    last = er - 1
  end
  while last > sr and blank(get_line(buf, last)) do
    last = last - 1
  end
  return sr, last
end

local function siblings(node)
  local out = {}
  local list = node:parent()
  if not list then
    return out
  end
  for c in list:iter_children() do
    if c:type() == "list_item" then
      table.insert(out, c)
    end
  end
  return out
end

--- The items of the list under the cursor as blocks of lines, with the gaps
--- (blank lines) between them. Returns blocks, gaps, index of the cursor's item.
local function collect(buf, node)
  local sibs = siblings(node)
  local blocks, idx = {}, 1
  for k, s in ipairs(sibs) do
    local sr, er = rows_of(buf, s)
    table.insert(blocks, { sr = sr, er = er, lines = api.nvim_buf_get_lines(buf, sr, er + 1, false) })
    if s:id() == node:id() then
      idx = k
    end
  end
  local gaps = {}
  for k = 1, #blocks - 1 do
    gaps[k] = api.nvim_buf_get_lines(buf, blocks[k].er + 1, blocks[k + 1].sr, false)
  end
  return blocks, gaps, idx
end

--- Shift the non-blank lines of a block (except the first) by `delta` columns,
--- after any blockquote prefix, so children stay under their (re-marked) parent.
local function shift(lines, delta)
  if delta == 0 then
    return
  end
  for i = 2, #lines do
    local l = lines[i]
    if not blank(l) then
      local q = util.bq_len(l)
      local pre, rest = l:sub(1, q), l:sub(q + 1)
      if delta > 0 then
        lines[i] = pre .. string.rep(" ", delta) .. rest
      else
        local sp = #rest:match("^ *")
        lines[i] = pre .. rest:sub(math.min(sp, -delta) + 1)
      end
    end
  end
end

M._shift = shift

--- Write `order` (block indices) back over the list's rows; gaps stay in place.
--- Ordered items are renumbered from the list's original first number.
local function write_back(buf, blocks, gaps, order)
  local first = lists.parse(blocks[1].lines[1])
  local start = first and first.num
  local out = {}
  for k, b in ipairs(order) do
    local lines = vim.deepcopy(blocks[b].lines)
    local it = start and lists.parse(lines[1])
    if it and it.num then
      local marker = tostring(start + k - 1) .. it.delim
      local delta = #marker - #it.marker
      lines[1] = it.bq .. it.indent .. marker .. lines[1]:sub(it.marker_col + #it.marker + 1)
      if delta ~= 0 then
        M._shift(lines, delta)
      end
    end
    vim.list_extend(out, lines)
    if gaps[k] then
      vim.list_extend(out, gaps[k])
    end
  end
  api.nvim_buf_set_lines(buf, blocks[1].sr, blocks[#blocks].er + 1, false, out)
  -- start row of each new position
  local starts, r = {}, blocks[1].sr
  for k, b in ipairs(order) do
    starts[k] = r
    r = r + #blocks[b].lines + (gaps[k] and #gaps[k] or 0)
  end
  return starts
end

local function after_edit(buf)
  lists.update_progress(buf)
end

-- Move ----------------------------------------------------------------------------

--- Move the item under the cursor, with its children, past `[count]` siblings
--- (dir = 1 down, -1 up). Ordered lists are renumbered.
function M.move(dir)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local node = item_node(buf, row - 1)
  if not node then
    return util.warn("not on a list item")
  end
  local blocks, gaps, idx = collect(buf, node)
  local target = math.max(1, math.min(#blocks, idx + dir * vim.v.count1))
  if target == idx then
    return
  end
  local order = {}
  for k = 1, #blocks do
    order[k] = k
  end
  table.insert(order, target, table.remove(order, idx))
  local offset = (row - 1) - blocks[idx].sr
  util.undo_break(buf)
  local starts = write_back(buf, blocks, gaps, order)
  local new_row = starts[target] + offset
  after_edit(buf)
  api.nvim_win_set_cursor(0, { new_row + 1, math.min(col, #get_line(buf, new_row)) })
end

-- Sort ----------------------------------------------------------------------------

local function sort_key(block)
  local item = lists.parse(block.lines[1]) or { text = block.lines[1] }
  local text = vim.trim((item.text:gsub("[*_`~=]", "")))
  return vim.fn.tolower(text), item.check
end

--- Sort the items of the list under the cursor (children move with their
--- parent). `mode` = "alpha": A→Z, or Z→A when already sorted; "checked":
--- unchecked items first, done ones last, otherwise keeping their order.
function M.sort(mode)
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local node = item_node(buf, row - 1)
  if not node then
    return util.warn("not on a list item")
  end
  local blocks, gaps, idx = collect(buf, node)
  if #blocks < 2 then
    return
  end
  local keys = {}
  for k, b in ipairs(blocks) do
    local txt, check = sort_key(b)
    keys[k] = { k = k, txt = txt, done = check ~= nil and check ~= " " }
  end
  local function sorted(less)
    local o = vim.deepcopy(keys)
    table.sort(o, function(a, b)
      local r = less(a, b)
      if r == nil then
        return a.k < b.k -- stable
      end
      return r
    end)
    return vim.tbl_map(function(x)
      return x.k
    end, o)
  end
  local order
  if mode == "checked" then
    order = sorted(function(a, b)
      if a.done ~= b.done then
        return b.done
      end
    end)
  else
    order = sorted(function(a, b)
      if a.txt ~= b.txt then
        return a.txt < b.txt
      end
    end)
    local already = true
    for k, v in ipairs(order) do
      if v ~= k then
        already = false
        break
      end
    end
    if already then
      order = sorted(function(a, b)
        if a.txt ~= b.txt then
          return a.txt > b.txt
        end
      end)
    end
  end
  local same = true
  for k, v in ipairs(order) do
    if v ~= k then
      same = false
      break
    end
  end
  if same then
    return
  end
  local offset = (row - 1) - blocks[idx].sr
  util.undo_break(buf)
  local starts = write_back(buf, blocks, gaps, order)
  local pos
  for k, v in ipairs(order) do
    if v == idx then
      pos = k
    end
  end
  local new_row = starts[pos] + offset
  after_edit(buf)
  api.nvim_win_set_cursor(0, { new_row + 1, math.min(col, #get_line(buf, new_row)) })
end

-- Lines <-> list ------------------------------------------------------------------

--- Rows of the paragraph (non-blank lines) around `row`.
local function paragraph(buf, row)
  if blank(get_line(buf, row)) then
    return nil
  end
  local sr, er, last = row, row, api.nvim_buf_line_count(buf) - 1
  while sr > 0 and not blank(get_line(buf, sr - 1)) do
    sr = sr - 1
  end
  while er < last and not blank(get_line(buf, er + 1)) do
    er = er + 1
  end
  return sr, er
end

local function skip(buf, row, line)
  return blank(line)
    or ts.code_context(ts.parse(buf, row), row, 0) == "block"
    or line:sub(util.bq_len(line) + 1):match("^%s*#") ~= nil
    or line:sub(util.bq_len(line) + 1):match("^%s*```") ~= nil
    or line:sub(util.bq_len(line) + 1):match("^%s*~~~") ~= nil
end

local function style_of(it)
  if not it then
    return nil
  elseif it.check then
    return "checkbox"
  elseif it.num then
    return "number"
  end
  return "bullet"
end

--- Convert rows srow..erow to a list `style` ("bullet", "number" or
--- "checkbox"), or back to plain lines when they all already are one.
--- Plain lines get a marker; items of another style change style. Existing
--- bullet characters (`-` `*` `+`) and number delimiters (`.` `)`) are kept;
--- new ones come from `lists.bullet` / `lists.number_delim`. Numbers restart
--- at 1 for each indentation level. Blank lines, headings and code are skipped.
function M.convert_lines(style, srow, erow)
  local buf = api.nvim_get_current_buf()
  local o = require("markwright.config").options.lists
  local lines = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  local all_same, any = true, false
  for i, l in ipairs(lines) do
    if not skip(buf, srow + i - 1, l) then
      any = true
      if style_of(lists.parse(l)) ~= style then
        all_same = false
      end
    end
  end
  if not any then
    return
  end
  local counters = {} -- number per indentation width
  local stack = {} -- { orig = indent width, content = new content column } of open parents
  for i, l in ipairs(lines) do
    if not skip(buf, srow + i - 1, l) then
      local it = lists.parse(l)
      local q = util.bq_len(l)
      local pre, ind, text
      if it then
        pre, ind, text = it.bq, it.indent, it.text
      else
        local rest = l:sub(q + 1)
        pre, ind = l:sub(1, q), rest:match("^%s*")
        text = rest:sub(#ind + 1)
      end
      if all_same then
        lines[i] = pre .. ind .. text -- list → plain
      else
        local depth = #ind
        -- nest under the closest less-indented line, at its new content column,
        -- so `1. a` / `  x` becomes `1. a` / `   1. x` (a real sub-list)
        while #stack > 0 and stack[#stack].orig >= depth do
          table.remove(stack)
        end
        local new_ind = #stack > 0 and string.rep(" ", stack[#stack].content) or ind
        for d in pairs(counters) do
          if d > depth then
            counters[d] = nil -- a shallower item restarts deeper numbering
          end
        end
        local marker
        if style == "number" then
          counters[depth] = (counters[depth] or 0) + 1
          marker = counters[depth] .. ((it and it.delim) or o.number_delim)
        elseif it and (not it.num or style == "checkbox") then
          marker = it.marker -- keep `*` / `+`; a numbered task list stays numbered
        else
          marker = o.bullet
        end
        local box = ""
        if style == "checkbox" then
          box = "[" .. ((it and it.check) or " ") .. "] "
        end
        lines[i] = pre .. new_ind .. marker .. " " .. box .. text
        table.insert(stack, { orig = depth, content = #new_ind + #marker + 1 })
      end
    end
  end
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, srow, erow + 1, false, lines)
  lists.update_progress(buf)
end

--- Normal mode: the paragraph (or list) under the cursor.
function M.convert_paragraph(style)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local sr, er = paragraph(buf, row)
  if not sr then
    return
  end
  M.convert_lines(style, sr, er)
end

--- Visual mode: the selected lines.
function M.convert_visual(style)
  local buf = api.nvim_get_current_buf()
  M.convert_lines(style, api.nvim_buf_get_mark(buf, "<")[1] - 1, api.nvim_buf_get_mark(buf, ">")[1] - 1)
end

-- Optional <M-j>/<M-k>-style keys ---------------------------------------------------

--- expr mapping: move the item on a list item, else run the key's previous
--- mapping (e.g. LazyVim's move-line).
function M.expr_move(dir, key)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  if not item_node(buf, row) then
    return util.fallback(buf, "n", key)
  end
  return ("<Cmd>lua require('markwright.listtools').move(%d)<CR>"):format(dir)
end

return M
