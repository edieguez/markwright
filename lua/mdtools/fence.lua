-- Code fences. Spec: SPEC.md section 9.3.
local api = vim.api
local ts = require("mdtools.ts")
local util = require("mdtools.util")

local M = {}

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function in_block(buf, row)
  return ts.code_context(ts.parse(buf, row), row, 0) == "block"
end

--- Indentation a new block should use to belong to the line's container
--- (list item content, blockquote).
local function container_prefix(line)
  local bq = line:match("^%s*>[>%s]*")
  if bq then
    return bq:match("%s$") and bq or bq .. " "
  end
  local lead = line:match("^%s*[-*+]%s+") or line:match("^%s*%d+[.)]%s+")
  if lead then
    return string.rep(" ", #lead)
  end
  return line:match("^%s*")
end

--- Fence long enough to contain `lines`.
function M.fence_for(lines)
  local longest = 0
  for _, l in ipairs(lines) do
    local run = l:match("^%s*(`+)")
    if run then
      longest = math.max(longest, #run)
    end
  end
  return string.rep("`", math.max(3, longest + 1))
end

--- Prompt for a language and insert an empty fenced block; cursor inside.
function M.insert()
  local buf = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1] - 1
  if in_block(buf, row) then
    return util.warn("already inside a code block")
  end
  vim.ui.input({ prompt = "Language: " }, function(lang)
    if lang == nil then
      return
    end
    lang = vim.trim(lang)
    local line = get_line(buf, row)
    local blank = line:match("^%s*$") ~= nil
    local prefix = blank and line or container_prefix(line)
    local block = { prefix .. "```" .. lang, prefix, prefix .. "```" }
    util.undo_break(buf)
    local at
    if blank then
      api.nvim_buf_set_lines(buf, row, row + 1, false, block)
      at = row + 1
    else
      api.nvim_buf_set_lines(buf, row + 1, row + 1, false, block)
      at = row + 2
    end
    api.nvim_win_set_cursor(0, { at + 1, #prefix })
    vim.cmd("startinsert!")
  end)
end

--- Prompt for a language and wrap rows srow..erow (0-based, inclusive) in a fence.
function M.wrap(buf, srow, erow)
  if in_block(buf, srow) then
    return util.warn("already inside a code block")
  end
  local lines = api.nvim_buf_get_lines(buf, srow, erow + 1, false)
  -- shared indentation of the non-blank lines
  local prefix
  for _, l in ipairs(lines) do
    if not l:match("^%s*$") then
      local ind = l:match("^%s*")
      if not prefix or #ind < #prefix then
        prefix = ind
      end
    end
  end
  prefix = prefix or ""
  local fence = M.fence_for(lines)
  local ns = api.nvim_create_namespace("mdtools_fence")
  local mark = api.nvim_buf_set_extmark(buf, ns, srow, 0, { end_row = erow, end_col = 0, right_gravity = false })
  vim.ui.input({ prompt = "Language: " }, function(lang)
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, mark, { details = true })
    pcall(api.nvim_buf_del_extmark, buf, ns, mark)
    if lang == nil or not m[1] then
      return
    end
    local s, e = m[1], m[3].end_row
    util.undo_break(buf)
    api.nvim_buf_set_lines(buf, e + 1, e + 1, false, { prefix .. fence })
    api.nvim_buf_set_lines(buf, s, s, false, { prefix .. fence .. vim.trim(lang) })
    if buf == api.nvim_get_current_buf() then
      api.nvim_win_set_cursor(0, { s + 1, #prefix })
    end
  end)
end

function M.wrap_visual()
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "<")[1] - 1
  local e = api.nvim_buf_get_mark(buf, ">")[1] - 1
  M.wrap(buf, s, e)
end

return M
