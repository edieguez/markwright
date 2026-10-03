-- Paste images from the clipboard. Spec: SPEC.md section 13.1.
-- macOS backend: pngpaste (if installed) or osascript (built in).
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local util = require("markwright.util")

local M = {}

M.IMAGE_EXT = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  svg = true,
  bmp = true,
  tiff = true,
  heic = true,
  avif = true,
}

local function opts()
  return config.options.images
end

-- macOS backend -------------------------------------------------------------

local SAVE_SCRIPT = {
  "on run argv",
  "  set outPath to item 1 of argv",
  "  try",
  "    set img to the clipboard as «class PNGf»",
  "  on error",
  '    return "noimage"',
  "  end try",
  "  set f to open for access (POSIX file outPath) with write permission",
  "  try",
  "    set eof f to 0",
  "    write img to f",
  "  end try",
  "  close access f",
  '  return "ok"',
  "end run",
}

local FURL_SCRIPT = {
  "try",
  "  return POSIX path of (the clipboard as «class furl»)",
  "on error",
  '  return ""',
  "end try",
}

--- `osascript -e line -e line ... args` as an argv list.
function M.osascript_cmd(lines, args)
  local cmd = { "osascript" }
  for _, l in ipairs(lines) do
    table.insert(cmd, "-e")
    table.insert(cmd, l)
  end
  vim.list_extend(cmd, args or {})
  return cmd
end

local function run(cmd, cb)
  local ok = pcall(vim.system, cmd, { text = true }, function(res)
    vim.schedule(function()
      cb(res.code == 0, vim.trim(res.stdout or ""), res.stderr)
    end)
  end)
  if not ok then
    cb(false, "", "could not run " .. cmd[1])
  end
end

---@class markwright.ImageBackend
---@field info fun(cb: fun(info: string))                      clipboard type summary
---@field save_image fun(path: string, cb: fun(ok: boolean, err?: string))
---@field file_path fun(cb: fun(path: string?))                 file copied in Finder

M.macos = {
  info = function(cb)
    run({ "osascript", "-e", "clipboard info" }, function(_, out)
      cb(out)
    end)
  end,
  save_image = function(path, cb)
    if vim.fn.executable("pngpaste") == 1 then
      run({ "pngpaste", path }, function(ok, _, err)
        cb(ok, (not ok) and vim.trim(err or "pngpaste failed") or nil)
      end)
      return
    end
    run(M.osascript_cmd(SAVE_SCRIPT, { path }), function(ok, out, err)
      if ok and out == "ok" then
        cb(true)
      else
        cb(false, out == "noimage" and "the clipboard has no image" or vim.trim(err or "osascript failed"))
      end
    end)
  end,
  file_path = function(cb)
    run(M.osascript_cmd(FURL_SCRIPT), function(ok, out)
      cb((ok and out ~= "") and out or nil)
    end)
  end,
}

--- Backend for this platform (overridable in tests), or nil if unsupported.
function M.backend()
  if vim.fn.has("mac") == 1 then
    return M.macos
  end
end

--- Text on the clipboard (for copied paths and URLs).
function M.clipboard_text()
  return require("markwright.links").read_clipboard()
end

-- Paths ---------------------------------------------------------------------------

local function buf_dir(buf)
  local name = api.nvim_buf_get_name(buf)
  if name == "" then
    return vim.fs.normalize(vim.fn.getcwd())
  end
  return vim.fs.normalize(vim.fn.fnamemodify(name, ":p:h"))
end

--- Absolute folder where images for `buf` are saved.
function M.target_dir(buf)
  local d = opts().dir
  if type(d) == "function" then
    d = d(buf)
  end
  d = d or "assets"
  if d:sub(1, 1) == "~" then
    d = vim.fn.expand(d)
  elseif d:sub(1, 1) ~= "/" then
    d = buf_dir(buf) .. "/" .. d
  end
  return vim.fs.normalize(d)
end

--- Relative path from folder `from` to file `to` (both absolute).
function M.relpath(from, to)
  local a = vim.split(vim.fs.normalize(from), "/", { trimempty = true })
  local b = vim.split(vim.fs.normalize(to), "/", { trimempty = true })
  local i = 1
  while i <= #a and i <= #b and a[i] == b[i] do
    i = i + 1
  end
  local parts = {}
  for _ = i, #a do
    table.insert(parts, "..")
  end
  for k = i, #b do
    table.insert(parts, b[k])
  end
  return table.concat(parts, "/")
end

--- Encode characters that would break a link destination.
function M.encode_path(p)
  return (p:gsub("[ ()<>]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

--- Turn a typed name into a safe file name (no extension).
function M.sanitize(name)
  name = vim.trim(name):gsub("%.%w+$", "")
  name = name:gsub('[/\\:*?"<>|]', ""):gsub("%s+", "-")
  return name
end

--- Alt text from a file name: "my-diagram" → "my diagram".
local function alt_from(name)
  return (name:gsub("[-_]+", " "))
end

--- First free path: name.ext, name-1.ext, name-2.ext ...
function M.free_path(dir, name, ext)
  local path = ("%s/%s.%s"):format(dir, name, ext)
  local n = 1
  while vim.uv.fs_stat(path) do
    path = ("%s/%s-%d.%s"):format(dir, name, n, ext)
    n = n + 1
  end
  return path
end

local function ext_of(path)
  return (path:match("%.([%w]+)$") or ""):lower()
end

-- Clipboard → source ---------------------------------------------------------------

---@class markwright.ImageSource
---@field kind "data"|"file"|"url"
---@field path? string   file to copy (kind = "file")
---@field url? string    remote image (kind = "url")

--- Work out what the clipboard holds. `cb(source|nil, err?)`.
function M.detect(backend, cb)
  backend.info(function(info)
    if info:find("furl", 1, true) then
      -- a file copied in Finder (also carries its icon as an image: check first)
      return backend.file_path(function(path)
        if path and M.IMAGE_EXT[ext_of(path)] then
          return cb({ kind = "file", path = path })
        end
        cb(nil, path and ("not an image file: " .. vim.fn.fnamemodify(path, ":t")) or "the clipboard has no image")
      end)
    end
    for _, t in ipairs({ "PNGf", "TIFF", "JPEG", "GIFf", "public.png", "public.jpeg" }) do
      if info:find(t, 1, true) then
        return cb({ kind = "data" })
      end
    end
    -- a copied path or URL
    local text = vim.trim(M.clipboard_text() or "")
    if not text:find("\n") and M.IMAGE_EXT[ext_of(text:gsub("[?#].*$", ""))] then
      if text:match("^https?://") then
        return cb({ kind = "url", url = text })
      end
      local p = text:gsub("^file://", "")
      p = vim.fn.expand(p)
      if vim.uv.fs_stat(p) then
        return cb({ kind = "file", path = vim.fs.normalize(p) })
      end
    end
    cb(nil, "the clipboard has no image")
  end)
end

-- Paste ----------------------------------------------------------------------------

--- Insert `text` at the paste position: replacing the selection, or after the
--- cursor character (like `p`), or at the start of an empty line.
local function insert(buf, target, text)
  util.undo_break(buf)
  if target.insert then
    -- insert mode (`;;p`): exactly at the cursor, then keep typing after it
    local row, col = target.row, target.col
    api.nvim_buf_set_text(buf, row, col, row, col, { text })
    target.col = col + #text
    return
  end
  if target.range then
    local r = target.range
    api.nvim_buf_set_text(buf, r[1], r[2], r[3], r[4], { text })
    api.nvim_win_set_cursor(0, { r[1] + 1, r[2] })
    return
  end
  local row, col = target.row, target.col
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local at = (line == "") and 0 or math.min(#line, col + util.char_len(line, col))
  api.nvim_buf_set_text(buf, row, at, row, at, { text })
  api.nvim_win_set_cursor(0, { row + 1, at })
end

local function link_for(buf, path, alt)
  local rel = M.relpath(buf_dir(buf), path)
  local escaped = alt:gsub("([%[%]])", "\\%1")
  return ("![%s](%s)"):format(escaped, M.encode_path(rel))
end

local function ask(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default }, cb)
end

--- Paste the clipboard image. `target` is {row, col}, {range = {sr,sc,er,ec}, alt = text},
--- or {row, col, insert = true} to paste at an insert-mode cursor and keep typing.
function M.paste(target)
  local buf = api.nvim_get_current_buf()
  if target and target.insert then
    return M._paste(buf, target, function()
      M.resume_insert(buf, target)
      -- a floating prompt (snacks.input, dressing…) may stop insert mode
      -- while it closes, after this callback: check again once it's gone
      if not target.prompted then
        return
      end
      vim.schedule(function()
        local cur = api.nvim_win_get_cursor(0)
        local left = cur[1] == target.row + 1 and cur[2] == math.max(target.col - 1, 0)
        if api.nvim_get_mode().mode == "n" and left and vim.fn.getchar(1) == 0 then
          M.resume_insert(buf, target)
        end
      end)
    end)
  end
  return M._paste(buf, target, function() end)
end

--- Back to insert mode at `target` (prompts may have left it).
function M.resume_insert(buf, target)
  if api.nvim_get_current_buf() ~= buf then
    return
  end
  local line = api.nvim_buf_get_lines(buf, target.row, target.row + 1, false)[1] or ""
  local col = math.min(target.col, #line)
  if api.nvim_get_mode().mode:sub(1, 1) == "i" then
    api.nvim_win_set_cursor(0, { target.row + 1, col })
    return
  end
  if col >= #line then
    api.nvim_win_set_cursor(0, { target.row + 1, col })
    vim.cmd("startinsert!")
  else
    api.nvim_win_set_cursor(0, { target.row + 1, col })
    vim.cmd("startinsert")
  end
end

function M._paste(buf, target, after)
  local backend = M.backend()
  if not backend then
    util.warn("image paste is only supported on macOS for now")
    return after()
  end
  if not target then
    local row, col = unpack(api.nvim_win_get_cursor(0))
    target = { row = row - 1, col = col }
  end
  local crow = target.range and target.range[1] or target.row
  if ts.code_context(ts.parse(buf, crow), crow, 0) then
    util.warn("image paste skipped inside code")
    return after()
  end

  M.detect(backend, function(src, err)
    if not src then
      util.warn(err or "the clipboard has no image")
      return after()
    end
    if src.kind == "url" then
      insert(buf, target, ("![%s](%s)"):format(target.alt or "", src.url))
      return after()
    end

    local o = opts()
    local ext = src.kind == "data" and "png" or ext_of(src.path)
    local default = target.alt and M.sanitize(target.alt)
    if not default or default == "" then
      default = src.kind == "file" and M.sanitize(vim.fn.fnamemodify(src.path, ":t:r")) or os.date(o.name)
    end

    local function finish(name, alt)
      local dir = M.target_dir(buf)
      vim.fn.mkdir(dir, "p")
      local path = M.free_path(dir, name, ext)
      local function done(ok, e)
        if not ok then
          util.warn("could not save image: " .. tostring(e))
          return after()
        end
        insert(buf, target, link_for(buf, path, alt))
        util.notify("saved " .. vim.fn.fnamemodify(path, ":~:."))
        after()
      end
      if src.kind == "data" then
        backend.save_image(path, done)
      else
        local ok, e = vim.uv.fs_copyfile(src.path, path)
        done(ok, e)
      end
    end

    local function with_name(name)
      local typed = name ~= default
      name = M.sanitize(name)
      if name == "" then
        name = M.sanitize(default)
      end
      if target.alt then
        return finish(name, target.alt)
      end
      if o.alt == "prompt" then
        target.prompted = true
        return ask("Alt text: ", typed and alt_from(name) or "", function(alt)
          if alt == nil then
            return after()
          end
          finish(name, vim.trim(alt))
        end)
      end
      local alt = ""
      if o.alt == "name" and (typed or src.kind == "file") then
        alt = alt_from(name)
      end
      finish(name, alt)
    end

    if o.prompt_name then
      target.prompted = true
      ask("Image name: ", default, function(name)
        if name == nil then
          return after()
        end
        with_name(name)
      end)
    else
      with_name(default)
    end
  end)
end

--- Visual mode: the selection becomes the alt text and is replaced by the image.
function M.paste_visual()
  local buf = api.nvim_get_current_buf()
  local s = api.nvim_buf_get_mark(buf, "<")
  local e = api.nvim_buf_get_mark(buf, ">")
  local last = api.nvim_buf_get_lines(buf, e[1] - 1, e[1], false)[1] or ""
  local ecol = math.min(#last, e[2] + math.max(util.char_len(last, e[2]), 1))
  local text = table.concat(api.nvim_buf_get_text(buf, s[1] - 1, s[2], e[1] - 1, ecol, {}), " ")
  M.paste({ range = { s[1] - 1, s[2], e[1] - 1, ecol }, alt = vim.trim(text) })
end

-- Rename ---------------------------------------------------------------------------

--- Strip `<...>` from a link destination.
local function bare_dest(dest)
  return (dest:gsub("^<(.*)>$", "%1"))
end

--- The image under the cursor: its destination text and node, or nil.
local function image_at(buf, row, col)
  local p = ts.parse(buf, row)
  local node = p and ts.ancestor(ts.inline_node(p, row, col), { image = true })
  if not node then
    return nil
  end
  for c in node:iter_children() do
    if c:type() == "link_destination" then
      return vim.treesitter.get_node_text(c, buf)
    end
  end
end

--- Every link/image destination (and `[ref]: dest` definition) in `buf` that
--- points at `abs`, as { row, scol, ecol } (0-based, ecol exclusive).
local function references(buf, abs)
  local follow = require("markwright.follow")
  local found = {}
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local function check(row, s, dest)
    local d = bare_dest(dest)
    if d == "" or d:match("^%a[%w+.-]*:") then
      return
    end
    if follow.resolve_path(buf, d:gsub("#.*$", "")) == abs then
      table.insert(found, { row, s - 1, s - 1 + #dest })
    end
  end
  for i, line in ipairs(lines) do
    local row = i - 1
    for s, dest in line:gmatch("%]%(()(<[^>]*>)") do
      check(row, s, dest)
    end
    for s, dest in line:gmatch("%]%(()([^%s)<][^%s)]*)") do
      check(row, s, dest)
    end
    local s, dest = line:match("^%s?%s?%s?%[[^%]]+%]:%s*()(%S+)")
    if s then
      check(row, s, dest)
    end
  end
  -- skip code spans and blocks
  return vim.tbl_filter(function(r)
    return not ts.code_context(ts.parse(buf, r[1]), r[1], r[2])
  end, found)
end

--- Rename the image file under the cursor on disk and update every reference
--- to it in the buffer. The new name keeps the old extension if none is typed.
function M.rename()
  local buf = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  row = row - 1
  local dest = image_at(buf, row, col)
  if not dest then
    return util.warn("no image under the cursor")
  end
  local path = bare_dest(dest):gsub("#.*$", "")
  if path:match("^%a[%w+.-]*:") then
    return util.warn("not a local file: " .. path)
  end
  local abs = require("markwright.follow").resolve_path(buf, path)
  if not vim.uv.fs_stat(abs) then
    return util.warn("file not found: " .. abs)
  end
  local dir, old = abs:match("^(.*)/([^/]+)$")
  ask("Rename image: ", old, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    input = vim.trim(input)
    if input:find("[/\\]") then
      return util.warn("type a file name, not a path")
    end
    local ext = input:match("%.(%w+)$") or old:match("%.(%w+)$")
    local stem = M.sanitize(input)
    if stem == "" then
      return
    end
    local new = ext and (stem .. "." .. ext) or stem
    if new == old then
      return
    end
    local target = dir .. "/" .. new
    -- (a case-only change on a case-insensitive disk "exists" as the same file)
    if vim.uv.fs_stat(target) and target:lower() ~= abs:lower() then
      return util.warn(new .. " already exists")
    end
    local ok, err = vim.uv.fs_rename(abs, target)
    if not ok then
      return util.warn("rename failed: " .. tostring(err))
    end
    local refs = references(buf, abs)
    util.undo_break(buf)
    for k = #refs, 1, -1 do
      local r = refs[k]
      local written = bare_dest(api.nvim_buf_get_text(buf, r[1], r[2], r[1], r[3], {})[1])
      local prefix = written:match("^(.*/)") or ""
      local anchor = written:match("(#.*)$") or ""
      api.nvim_buf_set_text(buf, r[1], r[2], r[1], r[3], { prefix .. M.encode_path(new) .. anchor })
    end
    vim.notify(
      ("markwright: renamed to %s (%d reference%s updated in this buffer)"):format(new, #refs, #refs == 1 and "" or "s")
    )
  end)
end

return M
