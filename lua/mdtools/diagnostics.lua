-- Broken link diagnostics. Spec: SPEC.md section 10.
local api = vim.api
local config = require("mdtools.config")
local ts = require("mdtools.ts")
local doc = require("mdtools.doc")
local links = require("mdtools.links")

local M = {}

M.ns = api.nvim_create_namespace("mdtools")

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function slug_set(headings)
  local set = {}
  for _, h in ipairs(headings) do
    set[h.slug] = true
  end
  return set
end

--- Compute diagnostics for a buffer (does not publish them).
---@return vim.Diagnostic[]
function M.collect(buf)
  local o = config.options.diagnostics
  local items = {}
  local function add(row, col, ecol, msg)
    table.insert(items, {
      lnum = row,
      col = col,
      end_col = ecol,
      severity = o.severity,
      source = "mdtools",
      message = msg,
    })
  end

  local p = ts.parser(buf)
  if not p then
    return items
  end
  p:parse(true)
  local code = doc.code_rows(buf)
  local slugs = slug_set(doc.headings(buf))
  local defs = doc.definitions(buf, code)
  local named = api.nvim_buf_get_name(buf) ~= ""
  local other_files = {}
  local follow = require("mdtools.follow")

  local function check_dest(dest, row, col, ecol)
    dest = vim.trim(dest):gsub("^<(.*)>$", "%1")
    if dest == "" then
      return
    end
    if dest:sub(1, 1) == "#" then
      local anchor = vim.fn.tolower(url_decode(dest:sub(2)))
      if anchor ~= "" and not slugs[anchor] then
        add(row, col, ecol, "no heading for #" .. anchor)
      end
      return
    end
    if links.is_url(dest) or (dest:match("^%a[%w+.-]+:") and not dest:match("^%a:[/\\]")) then
      return -- external: not checked
    end
    local path, anchor = dest:match("^([^#]*)#(.*)$")
    path = path or dest
    if path:sub(1, 1) ~= "/" and path:sub(1, 1) ~= "~" and not named then
      return -- unsaved buffer: nothing to resolve against
    end
    local full = follow.resolve_path(buf, path)
    if vim.fn.filereadable(full) == 0 and vim.fn.isdirectory(full) == 0 then
      if not full:match("%.[%w]+$") and vim.fn.filereadable(full .. ".md") == 1 then
        full = full .. ".md"
      else
        add(row, col, ecol, "file not found: " .. path)
        return
      end
    end
    if anchor and anchor ~= "" and full:match("%.md$") then
      local set = other_files[full]
      if not set then
        local ok, lines = pcall(vim.fn.readfile, full)
        set = slug_set(ok and doc.headings_from_string(table.concat(lines, "\n")) or {})
        other_files[full] = set
      end
      local a = vim.fn.tolower(url_decode(anchor))
      if not set[a] then
        add(row, col, ecol, ("no heading #%s in %s"):format(a, path))
      end
    end
  end

  local function label_of(node, t)
    for c in node:iter_children() do
      if c:type() == t then
        return c
      end
    end
  end

  local inl = p:children()["markdown_inline"]
  if inl then
    for _, tree in ipairs(inl:trees()) do
      local function walk(n)
        local t = n:type()
        if t == "inline_link" or t == "image" then
          local d = label_of(n, "link_destination")
          if d then
            local r, c, _, ec = d:range()
            check_dest(vim.treesitter.get_node_text(d, buf), r, c, ec)
          end
        elseif t == "full_reference_link" or t == "collapsed_reference_link" then
          local l = label_of(n, t == "full_reference_link" and "link_label" or "link_text")
          if l then
            local text = vim.treesitter.get_node_text(l, buf):gsub("^%[", ""):gsub("%]$", "")
            if not text:match("^%^") and not defs[doc.normalize_label(text)] then
              local r, c, _, ec = n:range()
              add(r, c, ec, "undefined reference [" .. text .. "]")
            end
          end
        end
        for ch in n:iter_children() do
          walk(ch)
        end
      end
      walk(tree:root())
    end
  end

  for _, d in pairs(defs) do
    check_dest(d.dest, d.row, d.col, d.col + #d.dest)
  end

  local refs, fdefs = doc.footnotes(buf, code)
  local referenced = {}
  for _, r in ipairs(refs) do
    referenced[r.id] = true
    if not fdefs[r.id] then
      add(r.row, r.col, r.ecol, "no definition for [^" .. r.id .. "]")
    end
  end
  for id, d in pairs(fdefs) do
    if not referenced[id] then
      add(d.row, d.col, d.col + #id + 3, "footnote [^" .. id .. "] is never referenced")
    end
  end

  table.sort(items, function(a, b)
    return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
  end)
  return items
end

--- Compute and publish diagnostics. They stay until the next check.
function M.check(buf)
  buf = buf or api.nvim_get_current_buf()
  if not config.options.diagnostics.enabled or not api.nvim_buf_is_valid(buf) then
    return
  end
  vim.diagnostic.set(M.ns, buf, M.collect(buf))
end

return M
