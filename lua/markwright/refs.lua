-- Inline ↔ reference links: [text](url) ↔ [text][label] + [label]: url.
-- Spec: SPEC.md section 14.17.
local api = vim.api
local doc = require("markwright.doc")
local slug = require("markwright.slug")
local ts = require("markwright.ts")
local util = require("markwright.util")

local M = {}

local KINDS = {
  inline_link = "inline",
  full_reference_link = "ref",
  collapsed_reference_link = "ref",
  shortcut_link = "ref",
  image = true, -- inline or reference, by its children
}

local function text_of(buf, node)
  local sr, sc, er, ec = node:range()
  return table.concat(api.nvim_buf_get_text(buf, sr, sc, er, ec, {}), "\n")
end

local function child(node, t)
  for c in node:iter_children() do
    if c:type() == t then
      return c
    end
  end
end

-- Definitions ----------------------------------------------------------------

---@class markwright.RefDef
---@field row integer
---@field label string as written
---@field dest string as written (may be <…>)
---@field title? string as written, with its quotes

--- Reference definitions (footnotes excluded), by normalized label.
---@return table<string, markwright.RefDef>
function M.definitions(buf)
  local code = doc.code_rows(buf)
  local defs = {}
  for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = i - 1
    if not code[row] then
      local label, rest = line:match("^ ? ? ?%[([^%]^][^%]]*)%]:%s*(.*)$")
      if label and rest ~= "" then
        local dest, title
        if rest:sub(1, 1) == "<" then
          dest, title = rest:match("^(<[^>]*>)%s*(.*)$")
        else
          dest, title = rest:match("^(%S+)%s*(.*)$")
        end
        if dest then
          local key = doc.normalize_label(label)
          if not defs[key] then
            defs[key] = { row = row, label = label, dest = dest, title = title ~= "" and title or nil }
          end
        end
      end
    end
  end
  return defs
end

-- Links ----------------------------------------------------------------------

---@class markwright.RefLink
---@field kind "inline"|"ref"
---@field image boolean
---@field sr integer
---@field sc integer
---@field er integer
---@field ec integer
---@field text string link text / alt text, as written
---@field dest? string inline: destination as written
---@field title? string inline: title as written
---@field label? string ref: the label (the text for collapsed / shortcut links)

--- Inline and reference links (and images) in rows `srow`..`erow`. Shortcut
--- and collapsed links only count when their label has a definition.
---@return markwright.RefLink[]
function M.collect(buf, srow, erow, defs)
  defs = defs or M.definitions(buf)
  local p = ts.parse(buf, srow, erow)
  local out = {}
  if not p then
    return out
  end
  p:parse({ srow, erow + 1 })
  local function walk(node)
    local t = node:type()
    if KINDS[t] then
      local sr, sc, er, ec = node:range()
      if er >= srow and sr <= erow and not ts.is_callout_marker(node, p) then
        local image = t == "image"
        local text_node = child(node, image and "image_description" or "link_text")
        local item = {
          image = image,
          sr = sr,
          sc = sc,
          er = er,
          ec = ec,
          text = text_node and text_of(buf, text_node) or "",
        }
        local dest, label = child(node, "link_destination"), child(node, "link_label")
        if t == "inline_link" or (image and dest) then
          item.kind = "inline"
          item.dest = text_of(buf, dest)
          local title = child(node, "link_title")
          item.title = title and text_of(buf, title) or nil
        elseif label then
          item.kind = "ref"
          item.label = text_of(buf, label):sub(2, -2)
        elseif t ~= "image" then
          item.kind = "ref"
          item.label = item.text
        end
        if item.kind == "inline" or (item.kind == "ref" and defs[doc.normalize_label(item.label)]) then
          table.insert(out, item)
        end
      end
      return
    end
    for c in node:iter_children() do
      walk(c)
    end
  end
  for _, root in ipairs(ts.inline_roots(p, srow, erow)) do
    walk(root)
  end
  table.sort(out, function(a, b)
    return a.sr < b.sr or (a.sr == b.sr and a.sc < b.sc)
  end)
  return out
end

-- Converting -------------------------------------------------------------------

local function bare(dest)
  return (dest:gsub("^<(.*)>$", "%1"))
end

--- Row after which new definitions go: after the last reference definition
--- when only definitions follow it, else nil (append at the end).
local function insert_row(buf, defs)
  local last
  for _, d in pairs(defs) do
    last = math.max(last or -1, d.row)
  end
  if not last then
    return nil
  end
  for _, l in ipairs(api.nvim_buf_get_lines(buf, last + 1, -1, false)) do
    if not (l:match("^%s*$") or l:match("^ ? ? ?%[[^%]]+%]:")) then
      return nil
    end
  end
  return last
end

--- Convert inline links (and images) to reference links. Labels come from
--- the link text; a URL that already has a definition reuses its label.
---@return integer converted
function M.to_reference(buf, links)
  local defs = M.definitions(buf)
  local by_url, taken = {}, {}
  for key, d in pairs(defs) do
    taken[key] = d
    by_url[bare(d.dest) .. "\0" .. (d.title or "")] = d.label
  end
  local new_defs = {}
  local function label_for(l)
    local k = bare(l.dest) .. "\0" .. (l.title or "")
    if by_url[k] then
      return by_url[k]
    end
    local base = slug.slug((l.text:gsub("%s+", " ")))
    if base == "" then
      base = l.image and "image" or "link"
    end
    local label, n = base, 1
    while taken[doc.normalize_label(label)] do
      n = n + 1
      label = base .. "-" .. n
    end
    taken[doc.normalize_label(label)] = true
    by_url[k] = label
    table.insert(new_defs, ("[%s]: %s%s"):format(label, l.dest, l.title and (" " .. l.title) or ""))
    return label
  end
  local todo = {}
  for _, l in ipairs(links) do
    if l.kind == "inline" then
      table.insert(todo, { l = l, label = label_for(l) })
    end
  end
  if #todo == 0 then
    return 0
  end
  util.undo_break(buf)
  for k = #todo, 1, -1 do
    local l = todo[k].l
    local s = ("%s[%s][%s]"):format(l.image and "!" or "", l.text, todo[k].label)
    api.nvim_buf_set_text(buf, l.sr, l.sc, l.er, l.ec, vim.split(s, "\n"))
  end
  if #new_defs > 0 then
    local at = insert_row(buf, defs)
    if at then
      api.nvim_buf_set_lines(buf, at + 1, at + 1, false, new_defs)
    else
      local n = api.nvim_buf_line_count(buf)
      local last = api.nvim_buf_get_lines(buf, n - 1, n, false)[1]
      if last == "" and n == 1 then
        api.nvim_buf_set_lines(buf, 0, 1, false, new_defs)
      else
        if last ~= "" then
          table.insert(new_defs, 1, "")
        end
        api.nvim_buf_set_lines(buf, n, n, false, new_defs)
      end
    end
  end
  return #todo
end

--- Convert reference links (and images) to inline ones. Definitions that no
--- reference uses any more are removed.
---@return integer converted
function M.to_inline(buf, links)
  local defs = M.definitions(buf)
  local todo, labels = {}, {}
  for _, l in ipairs(links) do
    if l.kind == "ref" then
      local d = defs[doc.normalize_label(l.label)]
      if d then
        table.insert(todo, { l = l, d = d })
        labels[doc.normalize_label(l.label)] = true
      end
    end
  end
  if #todo == 0 then
    return 0
  end
  util.undo_break(buf)
  for k = #todo, 1, -1 do
    local l, d = todo[k].l, todo[k].d
    local s = ("%s[%s](%s%s)"):format(l.image and "!" or "", l.text, d.dest, d.title and (" " .. d.title) or "")
    api.nvim_buf_set_text(buf, l.sr, l.sc, l.er, l.ec, vim.split(s, "\n"))
  end
  -- drop the definitions nothing refers to any more
  local still = {}
  local n = api.nvim_buf_line_count(buf)
  for _, l in ipairs(M.collect(buf, 0, n - 1)) do
    if l.kind == "ref" then
      still[doc.normalize_label(l.label)] = true
    end
  end
  local rows = {}
  for key, d in pairs(M.definitions(buf)) do
    if labels[key] and not still[key] then
      table.insert(rows, d.row)
    end
  end
  table.sort(rows, function(a, b)
    return a > b
  end)
  for _, r in ipairs(rows) do
    api.nvim_buf_set_lines(buf, r, r + 1, false, {})
  end
  -- no blank lines left dangling at the end of the file
  n = api.nvim_buf_line_count(buf)
  while #rows > 0 and n > 1 and api.nvim_buf_get_lines(buf, n - 1, n, false)[1] == "" do
    api.nvim_buf_set_lines(buf, n - 1, n, false, {})
    n = n - 1
  end
  return #todo
end

-- Entry points -------------------------------------------------------------------

local function report(n, what)
  if n == 0 then
    util.notify("no " .. what .. " to convert")
  end
end

--- <P>r: toggle the link under the cursor between inline and reference.
function M.toggle()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  for _, l in ipairs(M.collect(buf, row, row)) do
    local inside = (row > l.sr or (row == l.sr and col >= l.sc)) and (row < l.er or (row == l.er and col < l.ec))
    if inside then
      if l.kind == "inline" then
        M.to_reference(buf, { l })
      else
        M.to_inline(buf, { l })
      end
      pcall(api.nvim_win_set_cursor, 0, { l.sr + 1, l.sc })
      return
    end
  end
  util.warn("not on an inline or reference link")
end

--- Rows `srow`..`erow` (visual <P>r, a :range): inline links become references;
--- when there are none, references become inline.
function M.convert_range(buf, srow, erow, to)
  local links = M.collect(buf, srow, erow)
  if not to then
    to = "inline"
    for _, l in ipairs(links) do
      if l.kind == "inline" then
        to = "reference"
        break
      end
    end
  end
  if to == "reference" then
    report(M.to_reference(buf, links), "inline links")
  else
    report(M.to_inline(buf, links), "reference links")
  end
end

return M
