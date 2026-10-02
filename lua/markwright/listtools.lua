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
--- parent). `mode` = "asc": A→Z, "desc": Z→A, "done": unchecked items first,
--- done ones last, otherwise keeping their order.
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
  if mode == "done" then
    order = sorted(function(a, b)
      if a.done ~= b.done then
        return b.done
      end
    end)
  else
    local desc = mode == "desc"
    order = sorted(function(a, b)
      if a.txt ~= b.txt then
        if desc then
          return a.txt > b.txt
        end
        return a.txt < b.txt
      end
    end)
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

--- Would converting item `it` remove its checkbox?
local function loses_box(it, style, to_plain)
  return it ~= nil and it.check ~= nil and (style ~= "checkbox" or to_plain)
end

--- Marker for item number `n` of a converted level.
local function new_marker(style, it, n, o)
  if style == "number" then
    return n .. ((it and it.delim) or o.number_delim)
  elseif it and (not it.num or style == "checkbox") then
    return it.marker -- keep `*` / `+`; a numbered task list stays numbered
  end
  return o.bullet
end

--- Plan the conversion of rows srow..erow, every level (indentation decides
--- nesting). Returns new lines and info { boxes, done, others }: the checklist
--- items that would lose their checkbox (done: how many are checked) and the
--- other lines that would change. With `keep_checklists`, every list level
--- holding such an item (a checklist) is left as it is, so a list never mixes
--- checkboxes with bullets or numbers; nil when there's nothing to convert.
local function plan_lines(buf, style, srow, erow, keep_checklists)
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
    return nil
  end
  -- the list level (tree-sitter list node) of each item line; checklist levels
  local group, checklist = {}, {}
  local info = { boxes = 0, done = 0, others = 0 }
  for i, l in ipairs(lines) do
    if not skip(buf, srow + i - 1, l) then
      local it = lists.parse(l)
      local node = it and item_node(buf, srow + i - 1)
      group[i] = node and node:parent() and node:parent():id() or ("line" .. i)
      if loses_box(it, style, all_same) then
        checklist[group[i]] = true
        info.boxes = info.boxes + 1
        info.done = info.done + (it.check ~= " " and 1 or 0)
      end
    end
  end
  for i, l in ipairs(lines) do
    if group[i] and not checklist[group[i]] and not skip(buf, srow + i - 1, l) then
      info.others = info.others + 1
    end
  end
  local counters = {} -- number per indentation width
  local stack = {} -- { orig = indent width, content = new content column } of open parents
  for i, l in ipairs(lines) do
    if not skip(buf, srow + i - 1, l) then
      local it = lists.parse(l)
      local keep = keep_checklists and checklist[group[i]] and it ~= nil
      local q = util.bq_len(l)
      local pre, ind, text
      if it then
        pre, ind, text = it.bq, it.indent, it.text
      else
        local rest = l:sub(q + 1)
        pre, ind = l:sub(1, q), rest:match("^%s*")
        text = rest:sub(#ind + 1)
      end
      if keep then
        -- marker and box stay; only re-indented to stay under its parent
        local depth = #ind
        while #stack > 0 and stack[#stack].orig >= depth do
          table.remove(stack)
        end
        local new_ind = #stack > 0 and string.rep(" ", stack[#stack].content) or ind
        lines[i] = pre .. new_ind .. l:sub(#pre + #ind + 1)
        table.insert(stack, { orig = depth, content = #new_ind + it.content_col - it.marker_col })
      elseif all_same then
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
        counters[depth] = (counters[depth] or 0) + 1
        local marker = new_marker(style, it, counters[depth], o)
        local box = style == "checkbox" and ("[" .. ((it and it.check) or " ") .. "] ") or ""
        lines[i] = pre .. new_ind .. marker .. " " .. box .. text
        table.insert(stack, { orig = depth, content = #new_ind + #marker + 1 })
      end
    end
  end
  return lines, info
end

--- Plan the conversion of one level: the list item `node` and its siblings.
--- Their children and continuation lines aren't converted, only re-indented
--- when the marker width changes, so they stay inside their item. Returns
--- srow, erow, new lines and info (see plan_lines; a level is all-or-nothing,
--- so `others` is 0 when it's a checklist).
local function plan_level(buf, style, node)
  local o = require("markwright.config").options.lists
  local sibs = siblings(node)
  local blocks = {}
  for _, sib in ipairs(sibs) do
    local sr, er = rows_of(buf, sib)
    table.insert(blocks, { sr = sr, er = er })
  end
  local srow, erow = blocks[1].sr, blocks[#blocks].er
  local lines = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  local all_same = true
  for _, b in ipairs(blocks) do
    if style_of(lists.parse(lines[b.sr - srow + 1])) ~= style then
      all_same = false
    end
  end
  local info, n = { boxes = 0, done = 0, others = 0 }, 0
  for _, b in ipairs(blocks) do
    local k = b.sr - srow + 1
    local it = lists.parse(lines[k])
    if loses_box(it, style, all_same) then
      info.boxes = info.boxes + 1
      info.done = info.done + (it.check ~= " " and 1 or 0)
    end
    local start = #it.bq + #it.indent
    if all_same then
      lines[k] = it.bq .. it.indent .. it.text
    else
      n = n + 1
      local marker = new_marker(style, it, n, o)
      local box = style == "checkbox" and ("[" .. (it.check or " ") .. "] ") or ""
      lines[k] = it.bq .. it.indent .. marker .. " " .. box .. it.text
      start = start + #marker + 1
    end
    local block = { lines[k] }
    for r = b.sr + 1, b.er do
      table.insert(block, lines[r - srow + 1])
    end
    shift(block, start - it.content_col)
    for r = b.sr + 1, b.er do
      lines[r - srow + 1] = block[r - b.sr + 1]
    end
  end
  if info.boxes == 0 then
    info.others = #blocks
  end
  return srow, erow, lines, info
end

--- Run a conversion. `plan(keep_checklists)` returns srow, erow, new lines
--- and info. When checklist items would lose their checkbox, ask: Yes
--- converts the checklists too; No (only offered when there's something else
--- to convert) converts the rest and leaves the checklists as they are;
--- Cancel (or Esc) changes nothing.
local function run(buf, plan)
  local srow, erow, new, info = plan(false)
  if not new then
    return
  end
  local old = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  local function go(keep_checklists)
    if not vim.deep_equal(api.nvim_buf_get_lines(buf, srow, erow + 1, false), old) then
      return util.warn("the text changed; nothing converted")
    end
    if keep_checklists then
      srow, erow, new = plan(true)
    end
    util.undo_break(buf)
    api.nvim_buf_set_lines(buf, srow, erow + 1, false, new)
    lists.update_progress(buf)
  end
  if info.boxes == 0 then
    return go(false)
  end
  local prompt = ("%d checklist item%s%s would lose %s checkbox. Convert %s?"):format(
    info.boxes,
    info.boxes == 1 and "" or "s",
    info.done > 0 and (" (%d done)"):format(info.done) or "",
    info.boxes == 1 and "its" or "their",
    info.boxes == 1 and "it" or "them"
  )
  local choices = info.others > 0 and { "Yes", "No", "Cancel" } or { "Yes", "Cancel" }
  vim.ui.select(choices, { prompt = prompt }, function(choice)
    if choice == "Yes" then
      go(false)
    elseif choice == "No" then
      go(true)
    end
  end)
end

--- Convert rows srow..erow (every level) to `style` ("bullet", "number" or
--- "checkbox"), or back to plain lines when they all already have it. Plain
--- lines get a marker; items of another style switch. Existing bullet
--- characters and number delimiters are kept; new ones come from
--- `lists.bullet` / `lists.number_delim`. Numbers restart per level. Blank
--- lines, headings and code are skipped.
function M.convert_lines(style, srow, erow)
  local buf = api.nvim_get_current_buf()
  run(buf, function(keep_checklists)
    local new, info = plan_lines(buf, style, srow, erow, keep_checklists)
    return srow, erow, new, info
  end)
end

--- The list item containing `row` (also from a continuation line), or nil.
local function item_around(buf, row)
  local node = item_node(buf, row)
  if node then
    return node
  end
  local p = ts.parser(buf)
  if not p or blank(get_line(buf, row)) or ts.code_context(ts.parse(buf, row), row, 0) == "block" then
    return nil
  end
  local line = get_line(buf, row)
  node = ts.block_node(p, row, #line:match("^[%s>]*"))
  while node and node:type() ~= "list_item" do
    node = node:parent()
  end
  return node
end

--- Normal mode. On a list: the cursor's level (its item and siblings), or
--- with `all` that level and every sub-list below it (parents stay as they
--- are). On plain lines: the paragraph.
function M.convert(style, all)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local node = item_around(buf, row)
  if node and not all then
    return run(buf, function()
      return plan_level(buf, style, node)
    end)
  end
  local sr, er
  if node then
    local sibs = siblings(node)
    sr = rows_of(buf, sibs[1])
    _, er = rows_of(buf, sibs[#sibs])
  else
    sr, er = paragraph(buf, row)
    if not sr then
      return
    end
  end
  M.convert_lines(style, sr, er)
end

--- Visual mode: exactly the selected lines, every level.
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
