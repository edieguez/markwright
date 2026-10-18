-- Local usage counts (on by default; `usage = { enabled = false }` turns them off).
--
-- Every markwright key, `;;` insert key and :Markwright subcommand adds one
-- to its count in a JSON file on this machine (stdpath("data")/markwright/
-- usage.json). Only the key or command, its description, the count and the
-- date it was last used are stored: no file names, no text. Nothing is ever
-- sent anywhere. :Markwright usage shows the counts, most used first, and
-- the features never used.
--
-- Counts are kept in memory and added to the file (read, add, write) a few
-- seconds after a change and when Neovim exits, so several Neovim
-- instances can share the file.
local api = vim.api
local config = require("markwright.config")

local M = {}

M._pending = {} ---@type table<string, {count: integer, desc: string?, last: string}>
M._known = {} ---@type table<string, string> feature id -> description
M._timer = false
M.FLUSH_MS = 10000
M._default_file = nil -- tests point this at a temporary file

function M.enabled()
  local u = config.options.usage
  return u ~= nil and u.enabled == true
end

function M.path()
  local f = config.options.usage and config.options.usage.file
  if type(f) == "string" and f ~= "" then
    return vim.fs.normalize(vim.fn.expand(f))
  end
  return M._default_file or vim.fs.joinpath(vim.fn.stdpath("data"), "markwright", "usage.json")
end

local function today()
  return os.date("%Y-%m-%d")
end

--- Feature id of a key: the mode(s) and the key, with the configured prefix
--- written as <P> so counts survive a prefix change ("n <P>tj").
function M.key_id(mode, lhs)
  local modes = type(mode) == "table" and table.concat(mode) or mode
  local P = config.options.keymaps.prefix
  if P ~= "" and lhs:sub(1, #P) == P then
    lhs = "<P>" .. lhs:sub(#P + 1)
  end
  return modes .. " " .. lhs
end

--- An id as the user sees it: <P> and <T> replaced by the prefix and trigger.
function M.display(id)
  local P = config.options.keymaps.prefix
  local T = config.options.insert.trigger or ""
  return (id:gsub("<P>", function()
    return P
  end):gsub("<T>", function()
    return T
  end))
end

--- A feature that exists in this setup (listed under "Never used" until used).
function M.register(id, desc)
  if M.enabled() then
    M._known[id] = desc or M._known[id] or ""
  end
end

local function schedule_flush()
  if M._timer then
    return
  end
  M._timer = true
  vim.defer_fn(function()
    M._timer = false
    M.flush()
  end, M.FLUSH_MS)
end

--- Count one use of `id`.
function M.record(id, desc)
  if not M.enabled() then
    return
  end
  local p = M._pending[id] or { count = 0 }
  p.count = p.count + 1
  p.desc = desc or p.desc or M._known[id]
  p.last = today()
  M._pending[id] = p
  schedule_flush()
end

--- Wrap a mapping's rhs so pressing the key counts. Returns rhs, opts
--- (unchanged when counting is off). `o.contextual`: the key keeps its usual
--- meaning outside markwright's contexts (<CR>, <Tab>, o, p...), so it counts
--- only when markwright acted: not when the rhs returned the key itself or
--- ran the previous mapping (util.fallback).
---@param mode string|string[]
---@param lhs string
---@param desc string
---@param rhs string|function
---@param opts? table
---@param o? {contextual: boolean?}
function M.wrap(mode, lhs, desc, rhs, opts, o)
  if not M.enabled() then
    return rhs, opts
  end
  local id = M.key_id(mode, lhs)
  M._known[id] = desc
  opts = opts or {}
  if type(rhs) == "string" then
    if opts.expr then
      return rhs, opts
    end
    local keys = rhs
    opts = vim.tbl_extend("force", opts, { expr = true, replace_keycodes = true })
    return function()
      M.record(id, desc)
      return keys
    end, opts
  end
  local fn = rhs
  if not (o and o.contextual) then
    return function(...)
      M.record(id, desc)
      return fn(...)
    end, opts
  end
  local util = require("markwright.util")
  return function(...)
    util._fell_back = false
    local out = fn(...)
    if not util._fell_back and out ~= lhs then
      M.record(id, desc)
    end
    return out
  end,
    opts
end

-- Storage ---------------------------------------------------------------------

local function empty()
  return { version = 1, since = today(), features = {} }
end

--- The file's contents (without what's still in memory).
function M.load()
  local fd = io.open(M.path(), "r")
  if not fd then
    return empty()
  end
  local text = fd:read("*a")
  fd:close()
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or type(data.features) ~= "table" then
    return empty()
  end
  data.since = data.since or today()
  return data
end

local function merge(data, pending)
  for id, p in pairs(pending) do
    local f = data.features[id] or { count = 0 }
    f.count = (tonumber(f.count) or 0) + p.count
    f.desc = p.desc or f.desc
    if not f.last or p.last > f.last then
      f.last = p.last
    end
    data.features[id] = f
  end
  return data
end

--- Counts in the file plus those not written yet.
function M.data()
  return merge(M.load(), M._pending)
end

local function write(data)
  local path = M.path()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if next(data.features) == nil then
    data.features = vim.empty_dict()
  end
  local tmp = path .. ".tmp"
  local fd = io.open(tmp, "w")
  if not fd then
    return false
  end
  fd:write(vim.json.encode(data))
  fd:close()
  return os.rename(tmp, path) ~= nil
end

--- Add the counts in memory to the file.
function M.flush()
  if next(M._pending) == nil then
    return true
  end
  local pending = M._pending
  M._pending = {}
  if not write(merge(M.load(), pending)) then
    -- keep them for the next try
    M._pending = merge({ features = M._pending }, pending).features
    return false
  end
  return true
end

--- Start over: the old file is kept as usage.json.bak.
function M.reset()
  M._pending = {}
  local path = M.path()
  if vim.uv.fs_stat(path) then
    os.rename(path, path .. ".bak")
  end
  require("markwright.util").notify("usage counts reset (previous counts in " .. path .. ".bak)")
end

-- Report ----------------------------------------------------------------------

local function md_cell(s)
  return (tostring(s):gsub("|", "\\|"))
end

local function table_lines(header, rows, right)
  local width = {}
  for i, h in ipairs(header) do
    width[i] = math.max(3, vim.fn.strdisplaywidth(h))
  end
  for _, r in ipairs(rows) do
    for i, c in ipairs(r) do
      width[i] = math.max(width[i], vim.fn.strdisplaywidth(c))
    end
  end
  local function line(cells)
    local out = {}
    for i, c in ipairs(cells) do
      local pad = string.rep(" ", width[i] - vim.fn.strdisplaywidth(c))
      table.insert(out, right[i] and (pad .. c) or (c .. pad))
    end
    return "| " .. table.concat(out, " | ") .. " |"
  end
  local delim = {}
  for i, w in ipairs(width) do
    delim[i] = right[i] and (string.rep("-", w - 1) .. ":") or string.rep("-", w)
  end
  local lines = { line(header), "| " .. table.concat(delim, " | ") .. " |" }
  for _, r in ipairs(rows) do
    table.insert(lines, line(r))
  end
  return lines
end

--- Report lines: used features (most used first), then the ones never used.
---@param commands? string[] :Markwright command ids that exist
function M.report_lines(commands)
  local data = M.data()
  local known = vim.deepcopy(M._known)
  for _, c in ipairs(commands or {}) do
    known[c] = known[c] or ""
  end
  local used = {}
  local total = 0
  for id, f in pairs(data.features) do
    table.insert(
      used,
      { id = id, count = tonumber(f.count) or 0, desc = f.desc or known[id] or "", last = f.last or "" }
    )
    total = total + (tonumber(f.count) or 0)
  end
  table.sort(used, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.id < b.id
  end)
  local never = {}
  for id, desc in pairs(known) do
    if not data.features[id] then
      table.insert(never, { id = id, desc = desc })
    end
  end
  table.sort(never, function(a, b)
    return a.id < b.id
  end)

  local lines = {
    "# markwright usage",
    "",
    ("Counted since %s: %d use%s of %d feature%s. Stored in `%s`."):format(
      data.since,
      total,
      total == 1 and "" or "s",
      #used,
      #used == 1 and "" or "s",
      vim.fn.fnamemodify(M.path(), ":~")
    ),
    "",
    "Keys are listed with their modes (n normal, x visual, o operator-pending, i insert).",
    "",
    "## Used",
    "",
  }
  if #used == 0 then
    table.insert(lines, "Nothing yet.")
  else
    local rows = {}
    for _, u in ipairs(used) do
      table.insert(rows, { tostring(u.count), md_cell(M.display(u.id)), md_cell(u.desc), u.last })
    end
    vim.list_extend(lines, table_lines({ "Uses", "Key / command", "Feature", "Last used" }, rows, { true }))
  end
  vim.list_extend(lines, { "", "## Never used", "" })
  if #never == 0 then
    table.insert(lines, "Every feature has been used at least once.")
  else
    local rows = {}
    for _, n in ipairs(never) do
      table.insert(rows, { md_cell(M.display(n.id)), md_cell(n.desc) })
    end
    vim.list_extend(lines, table_lines({ "Key / command", "Feature" }, rows, {}))
  end
  return lines
end

--- Show the report in a scratch Markdown buffer.
---@param commands? string[]
function M.show(commands)
  if not M.enabled() then
    return require("markwright.util").notify("usage counting is off (usage.enabled = false in your setup)")
  end
  M.flush()
  local lines = M.report_lines(commands)
  local name = "markwright://usage"
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = api.nvim_create_buf(true, true)
    api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = "wipe"
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    api.nvim_set_current_win(win)
  else
    vim.cmd("tab sbuffer " .. buf)
  end
  vim.bo[buf].filetype = "markdown"
end

--- Write the counts when Neovim exits.
function M.setup(group)
  if not M.enabled() then
    return
  end
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.flush()
    end,
  })
end

return M
