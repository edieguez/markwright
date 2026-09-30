-- GitHub callouts (alerts): > [!NOTE] ... Spec: SPEC.md section 14.11.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")

local M = {}

local function opts()
  return config.options.callouts
end

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function is_quote(line)
  return line:match("^ ? ? ?>") ~= nil
end

--- `[!TYPE]` marker on a blockquote line: indent, type, rest (after `]`), or nil.
function M.parse_marker(line)
  local indent, typ, rest = line:match("^( ? ? ?)>%s*%[!(%a+)%](.*)$")
  if typ then
    return indent, typ, rest
  end
end

--- Rows (0-based, inclusive) of the blockquote containing `row`, or nil.
function M.blockquote_at(buf, row)
  if not is_quote(get_line(buf, row)) then
    return nil
  end
  local sr, er = row, row
  local last = api.nvim_buf_line_count(buf) - 1
  while sr > 0 and is_quote(get_line(buf, sr - 1)) do
    sr = sr - 1
  end
  while er < last and is_quote(get_line(buf, er + 1)) do
    er = er + 1
  end
  return sr, er
end

--- Rows to wrap in normal mode: the code block, or the paragraph (contiguous
--- non-blank lines) around `row`. nil on a blank line.
local function block_rows(buf, row)
  local p = ts.parse(buf, row)
  local node = p and ts.ancestor(ts.block_node(p, row, 0), { fenced_code_block = true })
  if node then
    local sr, _, er, ec = node:range()
    if ec == 0 then
      er = er - 1
    end
    return sr, er
  end
  if is_blank(get_line(buf, row)) then
    return nil
  end
  local sr, er = row, row
  local last = api.nvim_buf_line_count(buf) - 1
  while sr > 0 and not is_blank(get_line(buf, sr - 1)) do
    sr = sr - 1
  end
  while er < last and not is_blank(get_line(buf, er + 1)) do
    er = er + 1
  end
  return sr, er
end

local function common_indent(lines)
  local ind
  for _, l in ipairs(lines) do
    if not is_blank(l) then
      local w = l:match("^%s*")
      if not ind or #w < #ind then
        ind = w
      end
    end
  end
  return ind or ""
end

--- Wrap rows sr..er (0-based, inclusive) in a callout of `typ`.
function M.wrap(buf, sr, er, typ)
  local lines = api.nvim_buf_get_lines(buf, sr, er + 1, false)
  local ind = common_indent(lines)
  local out = { ind .. "> [!" .. typ .. "]" }
  for _, l in ipairs(lines) do
    if is_blank(l) then
      table.insert(out, ind .. ">")
    else
      table.insert(out, ind .. "> " .. l:sub(#ind + 1))
    end
  end
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, sr, er + 1, false, out)
  if buf == api.nvim_get_current_buf() then
    api.nvim_win_set_cursor(0, { sr + 2, #ind + 2 })
  end
end

--- Insert an empty callout at `row` (a blank line) and start typing in it.
function M.insert_empty(buf, row, typ)
  local ind = get_line(buf, row):match("^%s*")
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, row, row + 1, false, { ind .. "> [!" .. typ .. "]", ind .. "> " })
  if buf == api.nvim_get_current_buf() then
    api.nvim_win_set_cursor(0, { row + 2, #ind + 2 })
    vim.cmd("startinsert!")
  end
end

--- Set the type of the callout starting at `sr` (or turn a plain blockquote
--- into a callout by adding the marker line).
function M.set_type(buf, sr, typ)
  local line = get_line(buf, sr)
  local indent, _, rest = M.parse_marker(line)
  util.undo_break(buf)
  if indent then
    api.nvim_buf_set_lines(buf, sr, sr + 1, false, { indent .. "> [!" .. typ .. "]" .. rest })
  else
    local ind = line:match("^( ? ? ?)>")
    api.nvim_buf_set_lines(buf, sr, sr, false, { ind .. "> [!" .. typ .. "]" })
  end
end

--- Remove the callout (or blockquote) containing `row`: one `>` level is
--- removed from every line, and the `[!TYPE]` marker line is dropped.
function M.remove(buf, row)
  local sr, er = M.blockquote_at(buf, row)
  if not sr then
    util.warn("not in a callout")
    return false
  end
  local out = {}
  for r = sr, er do
    local line = get_line(buf, r)
    local indent, _, rest = M.parse_marker(line)
    if r == sr and indent then
      rest = vim.trim(rest)
      if rest ~= "" then
        table.insert(out, indent .. rest) -- a title after the marker (Obsidian style) stays as text
      end
    else
      local ind, body = line:match("^( ? ? ?)> ?(.*)$")
      table.insert(out, ind .. body)
    end
  end
  util.undo_break(buf)
  api.nvim_buf_set_lines(buf, sr, er + 1, false, out)
  if buf == api.nvim_get_current_buf() then
    api.nvim_win_set_cursor(0, { math.min(sr + 1, api.nvim_buf_line_count(buf)), 0 })
  end
  return true
end

-- Entry points --------------------------------------------------------------------

local function valid_type(typ)
  for _, t in ipairs(opts().types) do
    if t:upper() == typ:upper() then
      return t:upper()
    end
  end
end

--- Pick a type from `callouts.types`; `current` is marked in the list.
local function pick(current, cb)
  vim.ui.select(opts().types, {
    prompt = current and "Change callout type" or "Callout type",
    kind = "markwright_callout",
    format_item = function(t)
      if current and t:upper() == current:upper() then
        return t .. "  (current)"
      end
      return t
    end,
  }, function(choice)
    if choice then
      cb(choice:upper())
    end
  end)
end

--- Type for a new callout: given, the configured default, or picked.
local function with_type(typ, cb)
  if typ then
    return cb(typ)
  end
  if opts().default then
    return cb(opts().default:upper())
  end
  pick(nil, cb)
end

local function in_code_block(buf, row)
  return ts.code_context(ts.parse(buf, row), row, 0) == "block"
end

--- <P>a in normal mode: on a callout pick a new type; on a plain blockquote
--- make it a callout; elsewhere wrap the paragraph or code block. `typ`
--- (optional) sets the type directly.
function M.toggle(typ)
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  if typ then
    typ = valid_type(typ)
    if not typ then
      return util.warn("unknown callout type")
    end
  end
  local sr = M.blockquote_at(buf, row)
  if sr and not in_code_block(buf, row) then
    local _, cur = M.parse_marker(get_line(buf, sr))
    if cur then
      if typ then
        return M.set_type(buf, sr, typ)
      end
      return pick(cur, function(t)
        M.set_type(buf, sr, t)
      end)
    end
    return with_type(typ, function(t)
      M.set_type(buf, sr, t)
    end)
  end
  local bsr, ber = block_rows(buf, row)
  with_type(typ, function(t)
    if bsr then
      M.wrap(buf, bsr, ber, t)
    else
      M.insert_empty(buf, row, t)
    end
  end)
end

--- <P>a in visual mode: wrap the selected lines.
function M.wrap_visual(typ)
  local buf = api.nvim_get_current_buf()
  local sr = api.nvim_buf_get_mark(buf, "<")[1] - 1
  local er = api.nvim_buf_get_mark(buf, ">")[1] - 1
  if typ then
    typ = valid_type(typ)
    if not typ then
      return util.warn("unknown callout type")
    end
  end
  with_type(typ, function(t)
    M.wrap(buf, sr, er, t)
  end)
end

--- <P>A: remove the callout under the cursor.
function M.unwrap()
  local buf = api.nvim_get_current_buf()
  M.remove(buf, api.nvim_win_get_cursor(0)[1] - 1)
end

return M
