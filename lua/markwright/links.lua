-- Links: create, convert bare URLs, remove, smart paste. Spec: SPEC.md section 7.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")
local title = require("markwright.title")

local M = {}

local ns = api.nvim_create_namespace("markwright_links")

local LINK_TYPES = {
  inline_link = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
  uri_autolink = true,
  email_autolink = true,
}
local IMAGE = { image = true }

local function opts()
  return config.options.links
end

local function get_line(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- URLs ------------------------------------------------------------------

---@param s string?
---@return boolean
function M.is_url(s)
  if type(s) ~= "string" then
    return false
  end
  s = trim(s):gsub("^<(.*)>$", "%1")
  if s:find("%s") then
    return false
  end
  return s:match("^%a[%w+.-]*://[^/%s]+") ~= nil
    or s:match("^www%.[^%s]+%.[^%s]+$") ~= nil
    or s:match("^mailto:[^%s@]+@[^%s]+$") ~= nil
end

--- Normalize a URL for use as a link destination.
function M.normalize(s)
  s = trim(s):gsub("^<(.*)>$", "%1")
  if s:match("^www%.") then
    s = "https://" .. s
  end
  return s
end

--- Short human label for a URL: its host without "www.".
function M.domain(url)
  local host = url:match("^%a[%w+.-]*://([^/?#:]+)")
  if host then
    return (host:gsub("^www%.", ""))
  end
  local mail = url:match("^mailto:(.+)$")
  return mail or url
end

--- Escape characters that would break the link text.
function M.escape_text(s)
  return (s:gsub("([%[%]])", "\\%1"))
end

local URL_PATTERNS = { "%a[%w+.-]*://[^%s<>\"'`]+", "www%.[^%s<>\"'`]+", "mailto:[^%s<>\"'`]+" }

--- Strip punctuation that usually ends a sentence rather than the URL.
local function trim_url_tail(url)
  while true do
    local last = url:sub(-1)
    if last:match("[.,;:!?*_~'\"]") then
      url = url:sub(1, -2)
    elseif last == ")" then
      local _, opens = url:gsub("%(", "")
      local _, closes = url:gsub("%)", "")
      if closes > opens then
        url = url:sub(1, -2)
      else
        break
      end
    else
      break
    end
  end
  return url
end

--- Bare URL covering 0-based `col` on `line`.
---@return integer? scol, integer? ecol_exclusive, string? url
function M.url_at(line, col)
  local taken = {}
  for _, pat in ipairs(URL_PATTERNS) do
    local init = 1
    while true do
      local s, e = line:find(pat, init)
      if not s then
        break
      end
      local url = trim_url_tail(line:sub(s, e))
      local sc, ec = s - 1, s - 1 + #url
      local overlap = false
      for _, t in ipairs(taken) do
        if sc < t[2] and ec > t[1] then
          overlap = true
        end
      end
      if not overlap and M.is_url(url) then
        table.insert(taken, { sc, ec })
        if col >= sc and col < ec then
          return sc, ec, url
        end
      end
      init = e + 1
    end
  end
end

--- Clipboard contents. Uses the + register; on macOS falls back to pbpaste
--- when Neovim has no clipboard provider.
function M.read_clipboard()
  if vim.fn.has("clipboard") == 1 then
    local ok, s = pcall(vim.fn.getreg, "+")
    if ok and s ~= "" then
      return s
    end
  end
  if vim.fn.executable("pbpaste") == 1 then
    local s = vim.fn.system({ "pbpaste" })
    if vim.v.shell_error == 0 then
      return s
    end
  end
  return ""
end

-- Tree lookups ----------------------------------------------------------

local function node_at(p, row, col, types)
  return p and ts.ancestor(ts.inline_node(p, row, col), types)
end

local function node_text(buf, node)
  local sr, sc, er, ec = node:range()
  return api.nvim_buf_get_text(buf, sr, sc, er, ec, {})
end

local function child_of_type(node, t)
  for child in node:iter_children() do
    if child:type() == t then
      return child
    end
  end
end

-- Edits -----------------------------------------------------------------

local function set_cursor(row, col)
  local line = get_line(0, row)
  api.nvim_win_set_cursor(0, { row + 1, math.max(0, math.min(col, #line - 1)) })
end

--- Remove a link node, keeping its visible text.
function M.unlink(buf, node)
  local sr, sc, er, ec = node:range()
  local lines
  if node:type() == "uri_autolink" or node:type() == "email_autolink" then
    local t = table.concat(node_text(buf, node), "\n")
    lines = vim.split((t:gsub("^<", ""):gsub(">$", "")), "\n")
  else
    local lt = child_of_type(node, "link_text")
    lines = lt and node_text(buf, lt) or { "" }
  end
  util.undo_break(buf)
  api.nvim_buf_set_text(buf, sr, sc, er, ec, lines)
  if buf == api.nvim_get_current_buf() then
    set_cursor(sr, sc)
  end
end

--- Insert `[label](url)` at (row, col) replacing [col, ecol), then refine the
--- label with the page title when it arrives.
function M.insert_titled(buf, row, col, ecol, url, o)
  local href = M.normalize(url)
  local label = M.escape_text(M.domain(href))
  if not (o and o.no_undo_break) then
    util.undo_break(buf)
  end
  api.nvim_buf_set_text(buf, row, col, row, ecol, { "[" .. label .. "](" .. href .. ")" })
  if buf == api.nvim_get_current_buf() then
    set_cursor(row, col)
  end
  if not opts().fetch_title or href:match("^mailto:") then
    return
  end
  local id = api.nvim_buf_set_extmark(buf, ns, row, col + 1, {
    end_row = row,
    end_col = col + 1 + #label,
    right_gravity = false,
    end_right_gravity = true,
  })
  title.fetch(href, function(t)
    if not api.nvim_buf_is_valid(buf) then
      return
    end
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
    pcall(api.nvim_buf_del_extmark, buf, ns, id)
    if not t or not m[1] then
      return
    end
    local r, c, d = m[1], m[2], m[3]
    if d.end_row ~= r then
      return
    end
    local current = api.nvim_buf_get_text(buf, r, c, r, d.end_col, {})[1]
    if current ~= label then
      return -- the user edited or undid it meanwhile
    end
    pcall(vim.cmd, "undojoin") -- keep link + title as one undo step
    api.nvim_buf_set_text(buf, r, c, r, d.end_col, { M.escape_text(t) })
  end)
end

--- Wrap a range with `[` and `](url)`. Rows/cols 0-based, `ecol` exclusive.
function M.wrap(buf, srow, scol, erow, ecol, url)
  util.undo_break(buf)
  api.nvim_buf_set_text(buf, erow, ecol, erow, ecol, { "](" .. M.normalize(url) .. ")" })
  api.nvim_buf_set_text(buf, srow, scol, srow, scol, { "[" })
  if buf == api.nvim_get_current_buf() then
    set_cursor(srow, scol)
  end
end

--- Track a range across an async prompt.
local function track(buf, srow, scol, erow, ecol)
  return api.nvim_buf_set_extmark(buf, ns, srow, scol, {
    end_row = erow,
    end_col = ecol,
    right_gravity = false,
    end_right_gravity = true,
  })
end

local function tracked(buf, id)
  local m = api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
  pcall(api.nvim_buf_del_extmark, buf, ns, id)
  if not m[1] then
    return nil
  end
  return m[1], m[2], m[3].end_row, m[3].end_col
end

local function input(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default }, cb)
end

-- Actions ---------------------------------------------------------------

local function in_code(p, row, col)
  if ts.code_context(p, row, col) then
    util.warn("links skipped inside code")
    return true
  end
  return false
end

--- Link over a range: unlink, convert a URL, or wrap with a URL from the
--- clipboard or a prompt. Rows/cols 0-based, `ecol` exclusive.
function M.link_range(buf, srow, scol, erow, ecol)
  local p = ts.parse(buf, srow, erow)
  if in_code(p, srow, scol) then
    return
  end
  if node_at(p, srow, scol, IMAGE) then
    util.warn("that's an image, not a link")
    return
  end
  local node = node_at(p, srow, scol, LINK_TYPES) or (ecol > 0 and node_at(p, erow, ecol - 1, LINK_TYPES))
  if node then
    return M.unlink(buf, node)
  end

  -- trim whitespace inside the range
  local first, last = get_line(buf, srow), get_line(buf, erow)
  while srow == erow and scol < ecol and first:sub(scol + 1, scol + 1):match("%s") do
    scol = scol + 1
  end
  while ecol > 0 and (srow ~= erow or ecol > scol) and last:sub(ecol, ecol):match("%s") do
    ecol = ecol - 1
  end
  if srow == erow and ecol <= scol then
    return
  end

  if srow == erow then
    local text = first:sub(scol + 1, ecol)
    if M.is_url(text) then
      return M.insert_titled(buf, srow, scol, ecol, text)
    end
  end

  if opts().use_clipboard then
    local clip = trim(M.read_clipboard() or "")
    if M.is_url(clip) then
      return M.wrap(buf, srow, scol, erow, ecol, clip)
    end
  end

  local id = track(buf, srow, scol, erow, ecol)
  input("URL: ", nil, function(url)
    local r1, c1, r2, c2 = tracked(buf, id)
    if not url or trim(url) == "" or not r1 then
      return
    end
    M.wrap(buf, r1, c1, r2, c2, trim(url))
  end)
end

--- Link key on whitespace / empty line: prompt for URL, then text.
function M.prompt_new()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local line = get_line(buf, row)
  if in_code(ts.parse(buf, row), row, col) then
    return
  end
  local at = (line == "") and 0 or col + 1
  local id = track(buf, row, at, row, at)
  input("URL: ", nil, function(url)
    if not url or trim(url) == "" then
      pcall(api.nvim_buf_del_extmark, buf, ns, id)
      return
    end
    url = trim(url)
    input("Text (empty = page title): ", nil, function(text)
      local r, c = tracked(buf, id)
      if not r or text == nil then
        return
      end
      local l = get_line(buf, r)
      local nextc = l:sub(c + 1, c + 1)
      local trail = (nextc ~= "" and not nextc:match("%s")) and " " or ""
      util.undo_break(buf)
      if trail ~= "" then
        api.nvim_buf_set_text(buf, r, c, r, c, { trail }) -- link goes before this space
      end
      if trim(text) == "" then
        M.insert_titled(buf, r, c, c, url, { no_undo_break = true })
      else
        local s = "[" .. M.escape_text(trim(text)) .. "](" .. M.normalize(url) .. ")"
        api.nvim_buf_set_text(buf, r, c, r, c, { s })
        set_cursor(r, c)
      end
    end)
  end)
end

--- Link key when the cursor is on an existing link or a bare URL.
function M.at_cursor()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local p = ts.parse(buf, row)
  if in_code(p, row, col) then
    return
  end
  if node_at(p, row, col, IMAGE) then
    util.warn("that's an image, not a link")
    return
  end
  local node = node_at(p, row, col, LINK_TYPES)
  if node then
    return M.unlink(buf, node)
  end
  local sc, ec, url = M.url_at(get_line(buf, row), col)
  if sc then
    M.insert_titled(buf, row, sc, ec, url)
  end
end

-- Operator / keymap entry points ------------------------------------------

function M.opfunc(mtype)
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "[")
  local e = api.nvim_buf_get_mark(buf, "]")
  local srow, scol, erow = s[1] - 1, s[2], e[1] - 1
  local last = get_line(buf, erow)
  local ecol
  if mtype == "line" then
    local first = get_line(buf, srow)
    scol = util.prefix_len(first)
    ecol = #last
  else
    ecol = math.min(#last, e[2] + math.max(util.char_len(last, e[2]), 1))
  end
  M.link_range(buf, srow, scol, erow, ecol)
end

local OPFUNC = "v:lua.require'markwright.links'.opfunc"

local function cmd(fn)
  return ("<Cmd>lua require('markwright.links').%s()<CR>"):format(fn)
end

--- Normal-mode link key.
function M.expr_normal()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local ch = line:sub(col + 1, col + 1)
  if ch == "" or ch:match("%s") then
    return cmd("prompt_new")
  end
  local p = ts.parse(buf, row - 1)
  if
    ts.code_context(p, row - 1, col)
    or node_at(p, row - 1, col, LINK_TYPES)
    or node_at(p, row - 1, col, IMAGE)
    or M.url_at(line, col)
  then
    return cmd("at_cursor")
  end
  vim.o.operatorfunc = OPFUNC
  return "g@iw"
end

--- Visual-mode link key.
function M.expr_visual()
  vim.o.operatorfunc = OPFUNC
  return "g@"
end

-- Smart paste -------------------------------------------------------------

M._paste = nil ---@type {url: string, after: boolean, reg: string}?

--- URL held in a register as a single charwise line, or nil.
local function register_url(reg)
  local ok, text = pcall(vim.fn.getreg, reg)
  if not ok or type(text) ~= "string" then
    return nil
  end
  if vim.fn.getregtype(reg) ~= "v" or text:find("\n") then
    return nil
  end
  text = trim(text)
  return M.is_url(text) and text or nil
end

--- Normal-mode p / P.
function M.expr_paste(after)
  local native = after and "p" or "P"
  -- clipboard holds an image and no text: paste the image (opt-in)
  local img = config.options.images
  if img and img.smart_paste then
    local r = vim.v.register
    local ok, text = pcall(vim.fn.getreg, r)
    if (r == "+" or r == "*") and ok and text == "" and require("markwright.images").backend() then
      return "<Cmd>lua require('markwright.images').paste()<CR>"
    end
  end
  if not opts().smart_paste_normal then
    return native
  end
  local reg = vim.v.register
  local url = register_url(reg)
  if not url then
    return native
  end
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local ch = line:sub(col + 1, col + 1)
  if after and (ch == "(" or ch == "<") then
    return native -- completing a link destination by hand
  end
  local p = ts.parse(buf, row - 1)
  if ts.code_context(p, row - 1, col) or node_at(p, row - 1, col, LINK_TYPES) then
    return native
  end
  M._paste = { url = url, after = after, reg = reg }
  return cmd("_paste_normal")
end

function M._paste_normal()
  local ps = M._paste
  M._paste = nil
  if not ps then
    return
  end
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local at = col
  if ps.after and line ~= "" then
    at = col + util.char_len(line, col)
  end
  M.insert_titled(buf, row - 1, at, at, ps.url)
end

--- Visual-mode p.
function M.expr_paste_visual()
  if not opts().smart_paste_visual or vim.fn.mode() ~= "v" then
    return "p"
  end
  local reg = vim.v.register
  local url = register_url(reg)
  if not url then
    return "p"
  end
  M._paste = { url = url, after = true, reg = reg }
  return "<Esc>" .. cmd("_paste_visual")
end

function M._paste_visual()
  local ps = M._paste
  M._paste = nil
  if not ps then
    return
  end
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "<")
  local e = api.nvim_buf_get_mark(buf, ">")
  local srow, scol, erow = s[1] - 1, s[2], e[1] - 1
  local last = get_line(buf, erow)
  local ecol = math.min(#last, e[2] + math.max(util.char_len(last, e[2]), 1))
  local p = ts.parse(buf, srow, erow)
  if ts.code_context(p, srow, scol) or node_at(p, srow, scol, LINK_TYPES) then
    vim.cmd(('normal! gv"%sp'):format(ps.reg)) -- plain paste
    return
  end
  -- keep edge whitespace outside the link
  local first = get_line(buf, srow)
  while srow == erow and scol < ecol and first:sub(scol + 1, scol + 1):match("%s") do
    scol = scol + 1
  end
  while ecol > 0 and (srow ~= erow or ecol > scol) and last:sub(ecol, ecol):match("%s") do
    ecol = ecol - 1
  end
  if srow == erow and ecol <= scol then
    return
  end
  M.wrap(buf, srow, scol, erow, ecol, ps.url)
end

return M
