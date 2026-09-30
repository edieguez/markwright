-- Table of contents between markers. Spec: SPEC.md section 9.6.
local api = vim.api
local config = require("markwright.config")
local util = require("markwright.util")
local doc = require("markwright.doc")
local slug = require("markwright.slug")

local M = {}

--- TOC entry lines for the buffer's headings.
function M.entries(buf)
  local o = config.options.toc
  local hs = {}
  for _, h in ipairs(doc.headings(buf)) do
    if h.level >= o.min_level and h.level <= o.max_level and h.text ~= "" then
      table.insert(hs, h)
    end
  end
  local base = math.huge
  for _, h in ipairs(hs) do
    base = math.min(base, h.level)
  end
  local out = {}
  for _, h in ipairs(hs) do
    local text = slug.strip_links(h.text)
    table.insert(out, ("%s- [%s](#%s)"):format(string.rep("  ", h.level - base), text, h.slug))
  end
  return out
end

--- Rows (0-based) of the start and end markers, or nil.
function M.markers(buf)
  local o = config.options.toc
  local code = doc.code_rows(buf, { html = false }) -- markers are HTML comments
  local s
  for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = i - 1
    if not code[row] then
      local l = vim.trim(line)
      if not s and l == o.marker_start then
        s = row
      elseif s and l == o.marker_end then
        return s, row
      end
    end
  end
end

--- Regenerate the TOC between existing markers. Returns true if it changed.
function M.update(buf, opts)
  buf = buf or api.nvim_get_current_buf()
  local s, e = M.markers(buf)
  if not s then
    return false
  end
  local o = config.options.toc
  local indent = api.nvim_buf_get_lines(buf, s, s + 1, false)[1]:match("^%s*")
  local new = { indent .. o.marker_start }
  for _, l in ipairs(M.entries(buf)) do
    table.insert(new, indent .. l)
  end
  table.insert(new, indent .. o.marker_end)
  local old = api.nvim_buf_get_lines(buf, s, e + 1, false)
  if vim.deep_equal(old, new) then
    return false
  end
  if not (opts and opts.no_break) then
    util.undo_break(buf)
  end
  api.nvim_buf_set_lines(buf, s, e + 1, false, new)
  return true
end

--- <leader>mT: update the TOC, or insert one at the cursor.
function M.insert()
  local buf = api.nvim_get_current_buf()
  if M.markers(buf) then
    if M.update(buf) then
      util.notify("TOC updated")
    else
      util.notify("TOC already up to date")
    end
    return
  end
  local o = config.options.toc
  local row = api.nvim_win_get_cursor(0)[1] - 1
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local block = { o.marker_start }
  vim.list_extend(block, M.entries(buf))
  table.insert(block, o.marker_end)
  util.undo_break(buf)
  if line:match("^%s*$") then
    api.nvim_buf_set_lines(buf, row, row + 1, false, block)
    api.nvim_win_set_cursor(0, { row + 1, 0 })
  else
    table.insert(block, 1, "")
    api.nvim_buf_set_lines(buf, row + 1, row + 1, false, block)
    api.nvim_win_set_cursor(0, { row + 3, 0 })
  end
end

--- BufWritePre hook.
function M.on_save(buf)
  if config.options.toc.update_on_save then
    M.update(buf)
  end
end

return M
