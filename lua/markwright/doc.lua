-- Document-level queries shared by follow, toc, footnotes and diagnostics.
local api = vim.api
local ts = require("markwright.ts")
local slug = require("markwright.slug")

local M = {}

local CODE_BLOCKS = { fenced_code_block = true, indented_code_block = true, html_block = true }

local function root_of(buf)
  local p = ts.parser(buf)
  if not p then
    return nil
  end
  local trees = p:parse()
  return trees and trees[1] and trees[1]:root()
end

local function clean_heading(text)
  text = text:gsub("%s+#+%s*$", ""):gsub("^#+%s*$", "") -- closing hashes
  -- only line breaks (setext headings): GitHub keeps doubled spaces (`a--b`)
  return vim.trim((text:gsub("%s*\n%s*", " ")))
end

local function collect_headings(root, source)
  local out = {}
  local function walk(n)
    local t = n:type()
    if CODE_BLOCKS[t] then
      return
    end
    if t == "atx_heading" or t == "setext_heading" then
      local level, text
      for c in n:iter_children() do
        local ct = c:type()
        local lv = ct:match("^atx_h(%d)_marker$")
        if lv then
          level = tonumber(lv)
        elseif ct == "setext_h1_underline" then
          level = 1
        elseif ct == "setext_h2_underline" then
          level = 2
        elseif ct == "inline" then
          text = vim.treesitter.get_node_text(c, source)
        elseif ct == "paragraph" then
          for g in c:iter_children() do
            if g:type() == "inline" then
              text = vim.treesitter.get_node_text(g, source)
            end
          end
        end
      end
      local row = n:range()
      table.insert(out, { row = row, level = level or 1, text = clean_heading(text or "") })
      return
    end
    for c in n:iter_children() do
      walk(c)
    end
  end
  walk(root)
  local slugs = {}
  for i, h in ipairs(out) do
    slugs[i] = slug.slug(h.text)
  end
  for i, s in ipairs(slug.unique(slugs)) do
    out[i].slug = s
  end
  return out
end

---@class markwright.Heading
---@field row integer 0-based
---@field level integer
---@field text string
---@field slug string

--- Headings of a buffer (code blocks excluded), with unique slugs.
---@return markwright.Heading[]
function M.headings(buf)
  local root = root_of(buf)
  return root and collect_headings(root, buf) or {}
end

--- Headings of a markdown string (e.g. another file on disk).
function M.headings_from_string(str)
  local ok, p = pcall(vim.treesitter.get_string_parser, str, "markdown")
  if not ok or not p then
    return {}
  end
  local trees = p:parse()
  return collect_headings(trees[1]:root(), str)
end

--- Set of 0-based rows that are inside code blocks (and HTML blocks, unless
--- `opts.html == false`).
function M.code_rows(buf, opts)
  local skip_html = not (opts and opts.html == false)
  local rows = {}
  local root = root_of(buf)
  if not root then
    return rows
  end
  local function walk(n)
    local t = n:type()
    if CODE_BLOCKS[t] and (skip_html or t ~= "html_block") then
      local sr, _, er, ec = n:range()
      if ec == 0 then
        er = er - 1
      end
      for r = sr, er do
        rows[r] = true
      end
      return
    end
    for c in n:iter_children() do
      walk(c)
    end
  end
  walk(root)
  return rows
end

function M.normalize_label(s)
  return vim.fn.tolower((s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")))
end

--- Remove code spans from a line (so scans don't see their content).
function M.strip_code_spans(line)
  return (
    line:gsub("(`+)(.-)%1", function(ticks, inner)
      return ticks .. string.rep(" ", #inner) .. ticks -- keep column positions
    end)
  )
end

--- Link reference definitions `[label]: dest "title"` (footnotes excluded),
--- by normalized label. `dest` is bare, `raw` as written (may be `<…>`),
--- `col` where `raw` starts (0-based), `title` as written with its quotes.
---@return table<string, {row: integer, col: integer, dest: string, raw: string, label: string, title: string?}>
function M.definitions(buf, code)
  code = code or M.code_rows(buf)
  local defs = {}
  for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = i - 1
    if not code[row] then
      local label, at, rest = line:match("^ ? ? ?%[([^%]^][^%]]*)%]:%s*()(.*)$")
      if label and rest ~= "" then
        local raw, title
        if rest:sub(1, 1) == "<" then
          raw, title = rest:match("^(<[^>]*>)%s*(.*)$")
        else
          raw, title = rest:match("^(%S+)%s*(.*)$")
        end
        local key = raw and M.normalize_label(label)
        if key and not defs[key] then
          defs[key] = {
            row = row,
            col = at - 1,
            dest = (raw:gsub("^<(.*)>$", "%1")),
            raw = raw,
            label = label,
            title = title ~= "" and title or nil,
          }
        end
      end
    end
  end
  return defs
end

---@class markwright.FootnoteRef
---@field id string
---@field row integer
---@field col integer 0-based start of "[^"
---@field ecol integer exclusive

--- Footnote references and definitions.
---@return markwright.FootnoteRef[] refs, table<string, {row: integer, col: integer}> defs
function M.footnotes(buf, code)
  code = code or M.code_rows(buf)
  local refs, defs = {}, {}
  for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = i - 1
    if not code[row] then
      local scan = M.strip_code_spans(line)
      local def_prefix = scan:match(ts.FOOTNOTE_DEF)
      local def_indent = def_prefix and def_prefix:match("^[%s>]*")
      local def_id = def_prefix and def_prefix:match("%[%^([^%]%s]+)%]")
      if def_id and not defs[def_id] then
        defs[def_id] = { row = row, col = #def_indent }
      end
      local init = 1
      while true do
        local s, e, id = scan:find("%[%^([^%]%s]+)%]", init)
        if not s then
          break
        end
        local is_def = def_id and s == #def_indent + 1
        if not is_def then
          table.insert(refs, { id = id, row = row, col = s - 1, ecol = e })
        end
        init = e + 1
      end
    end
  end
  return refs, defs
end

return M
