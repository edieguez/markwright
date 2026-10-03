-- Insert-mode formatting: type a trigger (default ";;"), then a key.
-- Spec: SPEC.md section 13.2.
--
-- Character triggers are detected without a timeout: only the trigger's LAST
-- character is mapped (a single-key mapping never waits), and the earlier
-- characters must have just been typed in sequence (tracked by InsertCharPre).
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")

local M = {}

local ns = api.nvim_create_namespace("markwright_insert")

M.KEYS = {
  { key = "i", fmt = "italic", label = "italic" },
  { key = "b", fmt = "bold", label = "bold" },
  { key = "s", fmt = "strike", label = "strike" },
  { key = "c", fmt = "code", label = "code" },
  { key = "h", fmt = "highlight", label = "highlight" },
  { key = "k", fmt = "link", label = "link" },
  { key = "n", action = "footnote", label = "footnote" },
  { key = "p", action = "image", label = "image" },
}

local function trigger()
  return config.options.insert.trigger or ""
end

--- Is the trigger a key notation like "<C-g>" (vs. a character sequence)?
function M.is_key_trigger(t)
  return t:match("^<.+>$") ~= nil
end

-- Typed-character tracking ------------------------------------------------------

---@type table<integer, {row: integer, col: integer, typed: string}>
local state = {}

local function reset(buf)
  state[buf] = { row = -1, col = -1, typed = "" }
end

function M._on_char_pre(buf)
  local s = state[buf] or { row = -1, col = -1, typed = "" }
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local ch = vim.v.char
  if row ~= s.row or col ~= s.col then
    s.typed = ""
  end
  s.typed = (s.typed .. ch):sub(-16)
  s.row, s.col = row, col + #ch
  state[buf] = s
end

-- Pair bookkeeping (jump-out targets) ----------------------------------------------

---@type table<integer, table<integer, string>> buf -> extmark id -> kind
local kinds = {}

local function mark(buf, row, col, kind)
  local id = api.nvim_buf_set_extmark(buf, ns, row, col, { right_gravity = true })
  kinds[buf] = kinds[buf] or {}
  kinds[buf][id] = kind
  return id
end

--- Extmark of `kind` exactly at (row, col), if any.
local function mark_at(buf, row, col, kind)
  for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, { row, col }, { row, col }, {})) do
    if kinds[buf] and kinds[buf][m[1]] == kind then
      return m[1]
    end
  end
end

local function unmark(buf, id)
  pcall(api.nvim_buf_del_extmark, buf, ns, id)
  if kinds[buf] then
    kinds[buf][id] = nil
  end
end

function M._clear(buf)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  kinds[buf] = nil
  reset(buf)
end

-- Actions ---------------------------------------------------------------------------

local function cursor()
  local r, c = unpack(api.nvim_win_get_cursor(0))
  return r - 1, c
end

local function line_at(buf, row)
  return api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function put(buf, row, col, text)
  api.nvim_buf_set_text(buf, row, col, row, col, { text })
end

local function marker(fmt)
  return config.options.format[fmt].marker
end

--- Jump past the closing marker if the cursor sits right before it; otherwise
--- insert an empty pair with the cursor between.
function M.pair(buf, fmt)
  local row, col = cursor()
  local m = marker(fmt)
  local after = line_at(buf, row):sub(col + 1)
  local id = mark_at(buf, row, col, fmt)
  local ch = m:sub(1, 1)
  local heuristic = not id and after:sub(1, #m) == m and after:sub(#m + 1, #m + 1) ~= ch
  if id or heuristic then
    if id then
      unmark(buf, id)
    end
    api.nvim_win_set_cursor(0, { row + 1, col + #m })
    return
  end
  put(buf, row, col, m .. m)
  api.nvim_win_set_cursor(0, { row + 1, col + #m })
  mark(buf, row, col + #m, fmt)
end

--- Links in stages: `[|](url)` or `[|]()`; then jump into the parens (or past
--- them when the URL came from the clipboard); then past `)`.
function M.link(buf)
  local row, col = cursor()
  local after = line_at(buf, row):sub(col + 1)

  local text_id = mark_at(buf, row, col, "link_text")
  local url_id = mark_at(buf, row, col, "link_url")
  if text_id then
    unmark(buf, text_id)
    for _, m in ipairs(api.nvim_buf_get_extmarks(buf, ns, { row, col }, { row, -1 }, {})) do
      if kinds[buf] and kinds[buf][m[1]] == "link_url" then
        api.nvim_win_set_cursor(0, { row + 1, m[3] })
        return
      end
    end
    local close = after:find(")", 1, true)
    api.nvim_win_set_cursor(0, { row + 1, col + (close or 0) })
    return
  end
  if url_id then
    unmark(buf, url_id)
    api.nvim_win_set_cursor(0, { row + 1, col + 1 })
    return
  end
  -- no bookkeeping (e.g. typed by hand): infer from the text after the cursor
  if after:sub(1, 2) == "](" then
    local close = after:find(")", 3, true)
    if close then
      local empty = close == 3
      api.nvim_win_set_cursor(0, { row + 1, col + (empty and 2 or close) })
      return
    end
  elseif after:sub(1, 1) == ")" then
    api.nvim_win_set_cursor(0, { row + 1, col + 1 })
    return
  end

  local links = require("markwright.links")
  local url = ""
  if config.options.links.use_clipboard then
    local clip = vim.trim(links.read_clipboard() or "")
    if links.is_url(clip) then
      url = links.normalize(clip)
    end
  end
  put(buf, row, col, "[](" .. url .. ")")
  api.nvim_win_set_cursor(0, { row + 1, col + 1 })
  mark(buf, row, col + 1, "link_text")
  if url == "" then
    mark(buf, row, col + 3, "link_url")
  end
end

-- The menu ------------------------------------------------------------------------------

local function hint(only)
  local parts = {}
  for _, k in ipairs(M.KEYS) do
    if not only or only[k.key] then
      table.insert(parts, k.key .. " " .. k.label)
    end
  end
  return table.concat(parts, " · ") .. "  (Esc cancels)"
end

local function clear_hint()
  api.nvim_echo({ { "" } }, false, {})
end

--- Put back what the trigger replaced, then replay `key` as if typed.
local function fall_through(buf, key, restore)
  local row, col = cursor()
  if restore and restore ~= "" then
    put(buf, row, col, restore)
    api.nvim_win_set_cursor(0, { row + 1, col + #restore })
  end
  reset(buf)
  if key and key ~= "" then
    api.nvim_feedkeys(key, "mi", false)
  end
end

--- Run the key-trigger's previous meaning (e.g. native <C-g>u).
local function key_fallback(key)
  local t = trigger()
  local seq = api.nvim_replace_termcodes(t, true, false, true) .. key
  local m = vim.fn.maparg(t .. vim.fn.keytrans(key), "i", false, true)
  if m and not vim.tbl_isempty(m) and m.buffer == 0 then
    if m.callback then
      local out = m.callback()
      if m.expr == 1 and type(out) == "string" then
        api.nvim_feedkeys(api.nvim_replace_termcodes(out, true, false, true), m.noremap == 1 and "ni" or "mi", false)
      end
      return
    end
    local rhs = api.nvim_replace_termcodes(m.rhs or "", true, false, true)
    api.nvim_feedkeys(rhs, m.noremap == 1 and "ni" or "mi", false)
    return
  end
  api.nvim_feedkeys(seq, "ni", false)
end

--- Wait (no timeout) for the command key and run it.
---@param restore string text to put back if the key isn't a command
---@param ctx? "span" inside inline code: only jumping out of it is offered
function M.menu(restore, ctx)
  local buf = api.nvim_get_current_buf()
  local only = ctx == "span" and { c = true } or nil
  vim.cmd("redraw")
  api.nvim_echo({ { "markwright: ", "Title" }, { hint(only) } }, false, {})
  local ok, key = pcall(vim.fn.getcharstr)
  clear_hint()
  if not ok then
    key = "\27"
  end

  local entry
  for _, k in ipairs(M.KEYS) do
    if k.key == key and (not only or only[k.key]) then
      entry = k
    end
  end
  if entry then
    reset(buf)
    if entry.action == "footnote" then
      require("markwright.footnotes").insert_inline()
    elseif entry.action == "image" then
      local row, col = cursor()
      require("markwright.images").paste({ row = row, col = col, insert = true })
    elseif entry.fmt == "link" then
      M.link(buf)
    else
      M.pair(buf, entry.fmt)
    end
    return
  end
  if restore == nil then
    return key_fallback(key)
  end
  fall_through(buf, key, restore)
end

-- Triggers ------------------------------------------------------------------------------

--- Code context that blocks the trigger: nil (ok), "block" (off) or "span".
local function context(buf, row, col)
  local ctx = ts.code_context(ts.parse(buf, row), row, math.max(0, col - 1))
  return ctx
end

--- expr mapping on the trigger's last character.
function M.expr_last_char()
  local t = trigger()
  local last = vim.fn.strcharpart(t, vim.fn.strchars(t) - 1)
  local prefix = t:sub(1, #t - #last)
  local buf = api.nvim_get_current_buf()
  local row, col = cursor()
  local s = state[buf]
  local line = line_at(buf, row)
  local typed_ok = s and s.row == row + 1 and s.col == col and s.typed:sub(-#prefix) == prefix
  if not typed_ok or line:sub(col - #prefix + 1, col) ~= prefix then
    return last
  end
  local ctx = context(buf, row, col)
  if ctx == "block" then
    return last
  end
  if ctx == "span" and line:sub(col + 1, col + 1) ~= "`" then
    return last -- typing inside inline code, e.g. `for(;;)`
  end
  local bs = string.rep("<BS>", vim.fn.strchars(prefix))
  return ("%s<Cmd>lua require('markwright.insert').menu(%q, %s)<CR>"):format(bs, t, ctx == "span" and '"span"' or "nil")
end

--- Mapping for key triggers like <C-g>.
function M.expr_key()
  local buf = api.nvim_get_current_buf()
  local row, col = cursor()
  local ctx = context(buf, row, col)
  if ctx == "block" or (ctx == "span" and line_at(buf, row):sub(col + 1, col + 1) ~= "`") then
    return "<Cmd>lua require('markwright.insert').passthrough()<CR>"
  end
  return ("<Cmd>lua require('markwright.insert').menu(nil, %s)<CR>"):format(ctx == "span" and '"span"' or "nil")
end

--- Key trigger in code: behave exactly like the key did before.
function M.passthrough()
  local ok, key = pcall(vim.fn.getcharstr)
  if ok then
    key_fallback(key)
  end
end

function M.attach(buf)
  local t = trigger()
  if t == "" then
    return
  end
  local group = api.nvim_create_augroup("markwright_insert_" .. buf, { clear = true })
  reset(buf)
  api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    buffer = buf,
    callback = function()
      M._on_char_pre(buf)
    end,
  })
  api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
    group = group,
    buffer = buf,
    callback = function()
      M._clear(buf)
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      state[buf], kinds[buf] = nil, nil
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })
  local opts = { buffer = buf, expr = true, silent = true, desc = "markwright: insert-mode formatting" }
  if M.is_key_trigger(t) then
    vim.keymap.set("i", t, M.expr_key, opts)
  else
    local last = vim.fn.strcharpart(t, vim.fn.strchars(t) - 1)
    vim.keymap.set("i", last, M.expr_last_char, opts)
  end
end

return M
