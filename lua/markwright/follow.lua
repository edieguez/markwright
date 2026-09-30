-- gx: follow links, anchors, files, images and footnotes. Spec: SPEC.md section 8.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")
local doc = require("markwright.doc")
local links = require("markwright.links")

local M = {}

M.IMAGE_EXT = { png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true, bmp = true, avif = true }
-- binary documents also go to the system opener
M.OPEN_EXT = { pdf = true, mp4 = true, mov = true, mp3 = true, zip = true }

--- Opener, overridable in tests.
function M.open(target)
  local ok, res, err = pcall(vim.ui.open, target)
  if not ok then
    util.warn("could not open " .. target .. ": " .. tostring(res))
  elseif err then
    util.warn("could not open " .. target .. ": " .. tostring(err))
  end
end

local function jump(row, col)
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(0, { row + 1, col or 0 })
end

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

--- Jump to the heading whose slug matches `anchor` in `buf`.
function M.jump_anchor(buf, anchor)
  anchor = vim.fn.tolower(url_decode(anchor))
  for _, h in ipairs(doc.headings(buf)) do
    if h.slug == anchor then
      jump(h.row, 0)
      return true
    end
  end
  util.warn("no heading for #" .. anchor)
  return false
end

local function buf_dir(buf)
  local name = api.nvim_buf_get_name(buf)
  if name == "" then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(name, ":p:h")
end

--- Resolve a local link target to an absolute path.
function M.resolve_path(buf, path)
  path = url_decode(path)
  if path:sub(1, 1) == "~" then
    path = vim.fn.expand(path)
  elseif path:sub(1, 1) ~= "/" then
    path = buf_dir(buf) .. "/" .. path
  end
  return vim.fs.normalize(path)
end

local function ensure_dir_on_write(buf, path)
  api.nvim_create_autocmd("BufWritePre", {
    buffer = buf,
    once = true,
    callback = function()
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    end,
  })
end

--- Open a link destination.
function M.open_target(buf, dest)
  dest = vim.trim(dest):gsub("^<(.*)>$", "%1")
  if dest == "" then
    return
  end
  if dest:sub(1, 1) == "#" then
    return M.jump_anchor(buf, dest:sub(2))
  end
  if links.is_url(dest) then
    return M.open(links.normalize(dest))
  end
  if dest:match("^%a[%w+.-]+:") and not dest:match("^%a:[/\\]") then
    return M.open(dest) -- other schemes: file:, obsidian:, zotero: ...
  end

  local path, anchor = dest:match("^([^#]*)#(.*)$")
  path = path or dest
  if path == "" then
    return M.jump_anchor(buf, anchor or "")
  end
  local full = M.resolve_path(buf, path)
  local ext = (full:match("%.([%w]+)$") or ""):lower()
  if ext == "" and vim.fn.filereadable(full) == 0 and vim.fn.filereadable(full .. ".md") == 1 then
    full, ext = full .. ".md", "md"
  end
  local exists = vim.fn.filereadable(full) == 1
  if M.IMAGE_EXT[ext] or M.OPEN_EXT[ext] then
    if exists then
      return M.open(full)
    end
    return util.warn("file not found: " .. path)
  end
  if vim.fn.isdirectory(full) == 1 then
    vim.cmd("normal! m'")
    return vim.cmd.edit(vim.fn.fnameescape(full))
  end
  if not exists and not (ext == "md" and config.options.follow.create_missing_md) then
    return util.warn("file not found: " .. path)
  end
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(full))
  local nbuf = api.nvim_get_current_buf()
  if not exists then
    ensure_dir_on_write(nbuf, full)
    util.notify("new file: " .. vim.fn.fnamemodify(full, ":~:."))
  elseif anchor and anchor ~= "" then
    vim.bo[nbuf].filetype = vim.bo[nbuf].filetype ~= "" and vim.bo[nbuf].filetype or "markdown"
    M.jump_anchor(nbuf, anchor)
  end
end

-- What is under the cursor ------------------------------------------------

local function footnote_at(line, col)
  local init = 1
  while true do
    local s, e, id = line:find("%[%^([^%]%s]+)%]", init)
    if not s then
      return nil
    end
    if col >= s - 1 and col < e then
      local is_def = line:sub(1, s - 1):match("^%s*$") and line:sub(e + 1, e + 1) == ":"
      return id, is_def
    end
    init = e + 1
  end
end

local function child_text(buf, node, t)
  for c in node:iter_children() do
    if c:type() == t then
      return vim.treesitter.get_node_text(c, buf)
    end
  end
end

--- Destination of the link under the cursor, or nil.
function M.target_at(buf, row, col)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local p = ts.parse(buf, row)
  if p then
    local node = ts.ancestor(ts.inline_node(p, row, col), {
      inline_link = true,
      image = true,
      uri_autolink = true,
      email_autolink = true,
      full_reference_link = true,
      collapsed_reference_link = true,
      shortcut_link = true,
    })
    if node then
      local t = node:type()
      if t == "inline_link" or t == "image" then
        return child_text(buf, node, "link_destination") or ""
      elseif t == "uri_autolink" then
        return (vim.treesitter.get_node_text(node, buf):gsub("^<(.*)>$", "%1"))
      elseif t == "email_autolink" then
        return "mailto:" .. vim.treesitter.get_node_text(node, buf):gsub("^<(.*)>$", "%1")
      else
        local label = t == "full_reference_link" and child_text(buf, node, "link_label")
          or child_text(buf, node, "link_text")
        label = (label or ""):gsub("^%[", ""):gsub("%]$", "")
        local def = doc.definitions(buf)[doc.normalize_label(label)]
        if def then
          return def.dest
        end
        if t ~= "shortcut_link" then
          util.warn("no definition for [" .. label .. "]")
          return false
        end
      end
    end
  end
  -- a definition line: [ref]: dest
  local raw = line:match("^%s?%s?%s?%[[^%]^][^%]]*%]:%s*(%S+)")
  if raw then
    return raw
  end
  local _, _, url = links.url_at(line, col)
  return url
end

--- gx
function M.follow()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local line = api.nvim_get_current_line()

  local id, is_def = footnote_at(line, col)
  if id and not ts.code_context(ts.parse(buf, row), row, col) then
    local refs, defs = doc.footnotes(buf)
    if is_def then
      for _, r in ipairs(refs) do
        if r.id == id then
          return jump(r.row, r.col)
        end
      end
      return util.warn("footnote [^" .. id .. "] is never referenced")
    end
    local d = defs[id]
    if d then
      return jump(d.row, d.col)
    end
    return util.warn("no definition for [^" .. id .. "]")
  end

  local dest = M.target_at(buf, row, col)
  if dest == false then
    return
  end
  if dest then
    return M.open_target(buf, dest)
  end
  -- not a link: behave like the default gx
  local cfile = vim.fn.expand("<cfile>")
  if cfile ~= "" then
    M.open(cfile)
  end
end

return M
