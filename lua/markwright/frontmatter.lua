-- Front matter: insert a YAML block from a template, jump to it, refresh an
-- `updated:` field on save. Spec: SPEC.md section 14.19.
local api = vim.api
local config = require("markwright.config")
local util = require("markwright.util")

local M = {}

local function opts()
  return config.options.frontmatter
end

--- Rows (0-based) of the front matter block: `---` … `---` (or `...`) YAML,
--- or `+++` … `+++` TOML, starting on the first line. nil when there is none.
function M.find(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, math.min(api.nvim_buf_line_count(buf), 500), false)
  local open = lines[1] and lines[1]:match("^(%-%-%-)%s*$") or (lines[1] and lines[1]:match("^(%+%+%+)%s*$"))
  if not open then
    return nil
  end
  for i = 2, #lines do
    local l = lines[i]
    if
      (open == "---" and (l:match("^%-%-%-%s*$") or l:match("^%.%.%.%s*$")))
      or (open == "+++" and l:match("^%+%+%+%s*$"))
    then
      return 0, i - 1
    end
  end
  return nil
end

--- A YAML scalar for `s`: plain when safe, double-quoted otherwise.
function M.yaml_string(s)
  if
    s == ""
    or s:match("^[%s%-?:,%[%]{}#&*!|>'\"%%@`]")
    or s:match("[:#]%s")
    or s:match("[:%s]$")
    or s:match("^%s")
  then
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  end
  return s
end

local function title_for(buf)
  local h = require("markwright.doc").headings(buf)[1]
  if h and h.text ~= "" then
    return h.text
  end
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t:r")
  if name == "" then
    return ""
  end
  name = name:gsub("[-_]+", " ")
  return (name:gsub("^%l", string.upper))
end

--- Template lines with the placeholders filled in.
function M.render(buf)
  local tpl = opts().template
  if type(tpl) == "function" then
    tpl = tpl(buf)
  end
  local values = {
    title = M.yaml_string(title_for(buf)),
    date = os.date(opts().date_format),
    filename = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t:r"),
  }
  local out = {}
  for _, l in ipairs(tpl) do
    table.insert(out, (l:gsub("{(%w+)}", function(k)
      return values[k] or ("{" .. k .. "}")
    end)))
  end
  return out
end

--- <P>F: insert front matter at the top of the file, or jump into the one
--- that's there.
function M.insert()
  local buf = api.nvim_get_current_buf()
  local sr, er = M.find(buf)
  if sr then
    vim.cmd("normal! m'")
    local row = math.min(sr + 1, er)
    api.nvim_win_set_cursor(0, { row + 1, #(api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "") })
    return
  end
  local lines = M.render(buf)
  local first = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  local n = api.nvim_buf_line_count(buf)
  util.undo_break(buf)
  if n == 1 and first == "" then
    api.nvim_buf_set_lines(buf, 0, 1, false, vim.list_extend(lines, { "" }))
  else
    api.nvim_buf_set_lines(buf, 0, 0, false, vim.list_extend(lines, first ~= "" and { "" } or {}))
  end
  vim.cmd("normal! m'")
  -- cursor on the title, ready to edit
  local tl
  for i, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match("^title:") then
      tl = i
      break
    end
    if i > 50 then
      break
    end
  end
  tl = tl or 2
  api.nvim_win_set_cursor(0, { tl, math.max(0, #api.nvim_buf_get_lines(buf, tl - 1, tl, false)[1] - 1) })
end

--- BufWritePre: refresh the date of an existing `updated:` (or `lastmod:`,
--- `modified:`…) field. Never adds one. Returns true if it changed something.
function M.on_save(buf)
  if not opts().update_on_save then
    return false
  end
  local sr, er = M.find(buf)
  if not sr then
    return false
  end
  local fields = {}
  for _, f in ipairs(opts().update_fields) do
    fields[f] = true
  end
  local date = os.date(opts().date_format)
  for row = sr + 1, er - 1 do
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    local key, value = line:match("^([%w_%-]+):%s*(.-)%s*$")
    if key and fields[key] then
      local q = value:match("^([\"'])") or ""
      local new = ("%s: %s%s%s"):format(key, q, date, q)
      if new ~= line then
        pcall(vim.cmd, "undojoin")
        api.nvim_buf_set_lines(buf, row, row + 1, false, { new })
        return true
      end
      return false
    end
  end
  return false
end

return M
