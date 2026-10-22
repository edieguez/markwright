-- Local usage counts (on by default; `usage = { enabled = false }` turns them off).
--
-- Each use of a markwright feature adds one to that feature's count in a
-- JSON file on this machine (stdpath("data")/markwright/usage.json). A
-- feature is what the user does (add a table row), not a key: <P>tj, <P>tk
-- and :Markwright table row are all "Add row". Stored per feature: the
-- total, the count per day for the last 90 days, how it was reached (key,
-- visual, insert, command) and the date of the last use. No file names, no
-- text. Nothing is ever sent anywhere. :Markwright usage (usage_ui.lua)
-- shows the report.
--
-- Counts are kept in memory and added to the file (read, add, write) a few
-- seconds after a use and when Neovim exits, so several Neovim instances
-- can share the file.
local api = vim.api
local config = require("markwright.config")

local M = {}

M._pending = {} ---@type table<string, table>
M._registered = {} ---@type table<string, true> features with a key in this setup
M._key_ids = {} ---@type table<string, string> 4.5.0 key id ("n <P>tj") -> feature
M._timer = false
M._noticed = false
M._default_file = nil -- tests point this at a temporary file
M.FLUSH_MS = 10000
M.KEEP_DAYS = 90
M.RECENT_DAYS = 30
M.clock = os.time -- tests replace it

-- Features ----------------------------------------------------------------

--- Report areas, in this order when nothing is used yet. "Automatic" holds
--- what markwright does on keys that keep their usual meaning elsewhere.
M.AREAS = {
  "Formatting",
  "Links",
  "Lists",
  "Tables",
  "Headings",
  "Navigation",
  "Text objects",
  "Blocks",
  "Images",
  "Document",
  "Automatic",
}

---@class markwright.UsageFeature
---@field name string
---@field area string
---@field doc string README heading the report's <CR> opens
---@field cmd? boolean reachable with a :Markwright command

---@type table<string, markwright.UsageFeature>
M.FEATURES = {}
local function feature(id, area, name, doc)
  M.FEATURES[id] = { name = name, area = area, doc = doc }
end

for _, f in ipairs({
  { "bold", "Bold" },
  { "italic", "Italic" },
  { "strike", "Strikethrough" },
  { "code", "Inline code" },
  { "highlight", "Highlight" },
}) do
  feature("format." .. f[1], "Formatting", f[2], "Inline formatting in detail")
end

feature("link.toggle", "Links", "Create / remove link", "What `<leader>mk` does")
feature("link.refs", "Links", "Inline ↔ reference links", "Inline ↔ reference links")
feature("link.follow", "Links", "Follow link", "Following links with gx")
feature("link.check", "Links", "Link diagnostics", "Link diagnostics")
feature("link.check_urls", "Links", "Check external links", "Checking external links")

feature("list.checkbox", "Lists", "Toggle checkbox", "Checkboxes")
feature("list.move", "Lists", "Move item", "List tools")
feature("list.sort", "Lists", "Sort list", "List tools")
feature("list.convert", "Lists", "Convert list type", "List tools")

feature("table.create", "Tables", "Create table", "Creating")
feature("table.from_csv", "Tables", "CSV → table", "Creating")
feature("table.to_csv", "Tables", "Table → CSV", "Back to CSV")
feature("table.yank", "Tables", "Copy as CSV", "Back to CSV")
feature("table.add_row", "Tables", "Add row", "Editing")
feature("table.add_col", "Tables", "Add column", "Editing")
feature("table.delete_row", "Tables", "Delete row", "Editing")
feature("table.delete_col", "Tables", "Delete column", "Editing")
feature("table.move_row", "Tables", "Move row", "Moving, sorting and transposing")
feature("table.move_col", "Tables", "Move column", "Moving, sorting and transposing")
feature("table.sort", "Tables", "Sort table", "Moving, sorting and transposing")
feature("table.transpose", "Tables", "Transpose table", "Moving, sorting and transposing")
feature("table.align", "Tables", "Align table", "Alignment")

feature("heading.change", "Headings", "Heading level", "Headings")
feature("section.move", "Headings", "Move section", "Sections")
feature("section.change", "Headings", "Section level", "Sections")

feature("nav.heading", "Navigation", "Next / previous heading", "Heading navigation")
feature("nav.sibling", "Navigation", "Same-level heading", "Heading navigation")
feature("nav.parent", "Navigation", "Parent heading", "Heading navigation")
feature("nav.outline", "Navigation", "Outline", "Outline")

-- named apart from the features they share a word with ("Link", "Inline
-- code"), since the report can list every area together
for _, o in ipairs({
  { "link", "Link object" },
  { "url", "URL object" },
  { "code", "Code span object" },
  { "fence", "Code block object" },
  { "section", "Section object" },
  { "cell", "Cell object" },
  { "item", "List item object" },
  { "emphasis", "Emphasis object" },
}) do
  feature("textobject." .. o[1], "Text objects", o[2], "Text objects")
end

feature("fence", "Blocks", "Code fence", "Code fences")
feature("callout.toggle", "Blocks", "Callout", "Callouts")
feature("callout.remove", "Blocks", "Remove callout", "Callouts")
feature("footnote.insert", "Blocks", "Insert footnote", "Footnotes")
feature("footnote.renumber", "Blocks", "Renumber footnotes", "Renumbering")

feature("image.paste", "Images", "Paste image", "Pasting images")
feature("image.rename", "Images", "Rename image file", "Pasting images")

feature("toc", "Document", "Table of contents", "Table of contents")
feature("frontmatter", "Document", "Front matter", "Front matter")
feature("stats", "Document", "Word count", "Word count and reading time")
feature("health", "Document", "Health check", "Health check")

feature("list.continue", "Automatic", "Continue list", "Continuing lists")
feature("list.indent", "Automatic", "Indent list item", "Lists and checkboxes")
feature("quote.continue", "Automatic", "Continue quote", "Typing inside callouts and quotes")
feature("table.next_cell", "Automatic", "Next table cell", "`<Tab>` and completion")
feature("link.smart_paste", "Automatic", "Paste URL as link", "Smart paste")

--- Keys after the prefix -> feature.
M.KEY_FEATURES = {
  b = "format.bold",
  i = "format.italic",
  s = "format.strike",
  c = "format.code",
  h = "format.highlight",
  k = "link.toggle",
  r = "link.refs",
  f = "fence",
  n = "footnote.insert",
  tt = "table.create",
  tc = "table.from_csv",
  tC = "table.to_csv",
  ty = "table.yank",
  th = "table.add_col",
  tl = "table.add_col",
  tj = "table.add_row",
  tk = "table.add_row",
  tH = "table.move_col",
  tL = "table.move_col",
  tJ = "table.move_row",
  tK = "table.move_row",
  ts = "table.sort",
  tS = "table.sort",
  tf = "table.transpose",
  ta = "table.align",
  tdr = "table.delete_row",
  tdc = "table.delete_col",
  lJ = "list.move",
  lK = "list.move",
  ls = "list.sort",
  lS = "list.sort",
  ld = "list.sort",
  lb = "list.convert",
  lB = "list.convert",
  ln = "list.convert",
  lN = "list.convert",
  lc = "list.convert",
  lC = "list.convert",
  ["="] = "heading.change",
  ["-"] = "heading.change",
  ["#j"] = "section.move",
  ["#k"] = "section.move",
  ["#="] = "section.change",
  ["#-"] = "section.change",
  p = "image.paste",
  P = "image.rename",
  a = "callout.toggle",
  A = "callout.remove",
  F = "frontmatter",
  O = "toc",
  o = "nav.outline",
}

--- `;;` keys whose feature isn't format.<fmt> (insert.lua).
M.INSERT_KEYS = { link = "link.toggle", footnote = "footnote.insert", image = "image.paste" }

-- :Markwright subcommands: a feature, or { [second word] = feature,
-- [""] = feature without one }
local function all(id)
  return { [""] = id }
end
local function with_default(t, default)
  t[""] = default
  return t
end

local COMMANDS = {
  bold = all("format.bold"),
  italic = all("format.italic"),
  strike = all("format.strike"),
  code = all("format.code"),
  highlight = all("format.highlight"),
  link = all("link.toggle"),
  links = all("link.refs"),
  follow = all("link.follow"),
  check = with_default({ urls = "link.check_urls" }, "link.check"),
  checkbox = all("list.checkbox"),
  list = with_default({
    up = "list.move",
    down = "list.move",
    sort = "list.sort",
    bullet = "list.convert",
    number = "list.convert",
    checkbox = "list.convert",
  }),
  table = with_default({
    create = "table.create",
    csv = "table.from_csv",
    fromcsv = "table.from_csv",
    tocsv = "table.to_csv",
    yank = "table.yank",
    row = "table.add_row",
    rowabove = "table.add_row",
    col = "table.add_col",
    colleft = "table.add_col",
    delrow = "table.delete_row",
    delcol = "table.delete_col",
    sort = "table.sort",
    transpose = "table.transpose",
    align = "table.align",
  }),
  heading = all("heading.change"),
  section = with_default({
    up = "section.move",
    down = "section.move",
    add = "section.change",
    remove = "section.change",
  }),
  outline = all("nav.outline"),
  fence = all("fence"),
  callout = with_default({ remove = "callout.remove" }, "callout.toggle"),
  footnote = with_default({ renumber = "footnote.renumber" }, "footnote.insert"),
  image = with_default({ rename = "image.rename" }, "image.paste"),
  toc = all("toc"),
  frontmatter = all("frontmatter"),
  stats = all("stats"),
  health = all("health"),
}
for _, t in pairs(COMMANDS) do
  for _, id in pairs(t) do
    M.FEATURES[id].cmd = true
  end
end
M.FEATURES["table.move_row"].cmd, M.FEATURES["table.move_col"].cmd = true, true -- table move

--- Feature of a :Markwright command (its arguments), or nil (:Markwright usage).
---@param fargs string[]
function M.command_feature(fargs)
  if fargs[1] == "table" and fargs[2] == "move" then
    return (fargs[3] == "left" or fargs[3] == "right") and "table.move_col" or "table.move_row"
  end
  local t = COMMANDS[fargs[1] or ""]
  return t and (t[fargs[2] or ""] or t[""]) or nil
end

-- Counting ------------------------------------------------------------------

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

function M.today()
  return os.date("%Y-%m-%d", M.clock())
end

local function parse(date)
  local y, m, d = tostring(date):match("^(%d+)-(%d+)-(%d+)$")
  return y and os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) or nil
end

--- Whole days between `date` ("%Y-%m-%d") and today.
function M.days_ago(date)
  local t = parse(date)
  if not t then
    return math.huge
  end
  return math.floor((parse(M.today()) - t) / 86400 + 0.5)
end

--- A feature with a key in this setup (it's listed as never used until it is).
function M.register(id)
  if M.enabled() and id then
    M._registered[id] = true
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

M.NOTICE = "counting which features are used, in a local file only (nothing is sent anywhere). "
  .. ":Markwright usage shows the counts; usage = { enabled = false } in setup() turns this off."

--- Say once, before anything was ever written, that counting is on.
local function notice()
  if M._noticed then
    return
  end
  M._noticed = true
  if not vim.uv.fs_stat(M.path()) then
    vim.schedule(function()
      require("markwright.util").notify(M.NOTICE)
    end)
  end
end

--- Count one use of feature `id`, reached through `via` ("key", "visual",
--- "insert" or "command").
---@param id string?
---@param via? string
function M.record(id, via)
  if not id or not M.enabled() then
    return
  end
  via = via or "key"
  local p = M._pending[id] or { count = 0, via = {}, days = {} }
  local d = M.today()
  p.count = p.count + 1
  p.via[via] = (p.via[via] or 0) + 1
  p.days[d] = (p.days[d] or 0) + 1
  p.last = d
  M._pending[id] = p
  notice()
  schedule_flush()
end

--- 4.5.0 key id: modes and key, the prefix written <P>.
local function key_id(mode, lhs)
  local modes = type(mode) == "table" and table.concat(mode) or mode
  local P = config.options.keymaps.prefix
  if P ~= "" and lhs:sub(1, #P) == P then
    lhs = "<P>" .. lhs:sub(#P + 1)
  end
  return modes .. " " .. lhs
end

--- Wrap a mapping's rhs so using the key counts. Returns rhs, opts
--- (unchanged when counting is off).
--- `u.feature`: the feature id, or function(keys the rhs returned) -> id;
--- default: from the key after the prefix (KEY_FEATURES). `u.features`: the
--- ids a function can return. `u.contextual`: the key keeps its usual
--- meaning outside markwright's contexts (<CR>, <Tab>, o, p...), so it
--- counts only when markwright acted: not when the rhs returned the key
--- itself or ran the previous mapping (util.fallback).
---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
---@param u? {feature: string|fun(out: any): string, features: string[]?, contextual: boolean?}
function M.wrap(mode, lhs, rhs, opts, u)
  if not M.enabled() then
    return rhs, opts
  end
  u = u or {}
  local id = u.feature
  if id == nil then
    local P = config.options.keymaps.prefix
    if P ~= "" and lhs:sub(1, #P) == P then
      id = M.KEY_FEATURES[lhs:sub(#P + 1)]
    end
    id = id or ("unknown:" .. lhs) -- not in FEATURES: the usage spec fails on it
  end
  local ids = u.features or (type(id) == "string" and { id } or {})
  for _, f in ipairs(ids) do
    M._registered[f] = true
  end
  -- for counts from 4.5.0 (per key): a function's last id is its default
  M._key_ids[key_id(mode, lhs)] = type(id) == "string" and id or ids[#ids]
  local via = mode == "x" and "visual" or "key"
  local function feature_of(out)
    if type(id) == "function" then
      return id(out)
    end
    return id
  end
  opts = opts or {}
  if type(rhs) == "string" then
    if opts.expr then
      return rhs, opts
    end
    local keys = rhs
    opts = vim.tbl_extend("force", opts, { expr = true, replace_keycodes = true })
    return function()
      M.record(feature_of(keys), via)
      return keys
    end, opts
  end
  local fn = rhs
  if not u.contextual then
    return function(...)
      local out = fn(...)
      M.record(feature_of(out), via)
      return out
    end, opts
  end
  local util = require("markwright.util")
  return function(...)
    util._fell_back = false
    local out = fn(...)
    if not util._fell_back and out ~= lhs then
      M.record(feature_of(out), via)
    end
    return out
  end,
    opts
end

-- Storage -------------------------------------------------------------------

local function empty()
  return { version = 2, since = M.today(), features = {} }
end

local function add_into(f, p)
  f.count = (tonumber(f.count) or 0) + (tonumber(p.count) or 0)
  f.via = f.via or {}
  for k, n in pairs(p.via or {}) do
    f.via[k] = (tonumber(f.via[k]) or 0) + n
  end
  f.days = f.days or {}
  for k, n in pairs(p.days or {}) do
    f.days[k] = (tonumber(f.days[k]) or 0) + n
  end
  if p.last and (not f.last or p.last > f.last) then
    f.last = p.last
  end
  return f
end

local LEGACY_INSERT = {
  b = "format.bold",
  i = "format.italic",
  s = "format.strike",
  c = "format.code",
  h = "format.highlight",
  k = "link.toggle",
  n = "footnote.insert",
  p = "image.paste",
}

--- Feature and via of a 4.5.0 id ("n <P>tj", "i <T>b", ":Markwright table row").
local function legacy(id)
  if id:sub(1, 1) == ":" then
    return M.command_feature(vim.split(id:gsub("^:Markwright%s+", ""), "%s+")), "command"
  end
  local letter = id:match("^i <T>(.)$")
  if letter then
    return LEGACY_INSERT[letter], "insert"
  end
  local mode, lhs = id:match("^(%S+) (.+)$")
  if not mode then
    return nil
  end
  local f = M._key_ids[id] or (lhs:sub(1, 3) == "<P>" and M.KEY_FEATURES[lhs:sub(4)])
  return f or nil, mode == "x" and "visual" or "key"
end

local function migrate(data)
  local out = { version = 2, since = data.since, features = {}, legacy = {} }
  for id, f in pairs(data.features) do
    local fid, via = legacy(id)
    if fid and M.FEATURES[fid] then
      local n = tonumber(f.count) or 0
      out.features[fid] = add_into(out.features[fid] or { count = 0 }, {
        count = n,
        via = { [via] = n },
        last = f.last,
      })
    else
      out.legacy[id] = f -- kept, not shown
    end
  end
  return out
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
    -- unreadable: keep it aside, or the next write would replace it with nothing
    os.rename(M.path(), M.path() .. ".bad")
    return empty()
  end
  data.since = data.since or M.today()
  if data.version ~= 2 then
    data = migrate(data)
  end
  return data
end

local function merge(data, pending)
  for id, p in pairs(pending) do
    data.features[id] = add_into(data.features[id] or { count = 0 }, p)
  end
  return data
end

--- Counts in the file plus those not written yet.
function M.data()
  return merge(M.load(), vim.deepcopy(M._pending))
end

local function dict(t)
  return (t == nil or next(t) == nil) and vim.empty_dict() or t
end

local function write(data)
  local path = M.path()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  for _, f in pairs(data.features) do
    for d in pairs(f.days or {}) do
      if M.days_ago(d) >= M.KEEP_DAYS then
        f.days[d] = nil
      end
    end
    f.via, f.days = dict(f.via), dict(f.days)
  end
  data.features = dict(data.features)
  if data.legacy then
    data.legacy = dict(data.legacy)
  end
  -- one temporary file per process: two Neovims writing at once never mix
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local fd = io.open(tmp, "w")
  if not fd then
    return false
  end
  local ok = fd:write(vim.json.encode(data))
  ok = fd:close() and ok
  if not ok then
    os.remove(tmp)
    return false
  end
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
    M._pending = merge({ features = M._pending }, pending).features -- next time
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

---@class markwright.UsageRow
---@field id string
---@field name string
---@field area string
---@field doc string
---@field recent integer uses in the last 30 days
---@field total integer
---@field last string? date of the last use
---@field via table<string, integer>

--- One row per feature, used or not (features reachable in this setup), and
--- the data they come from.
---@return markwright.UsageRow[] rows, table data
function M.rows()
  local data = M.data()
  local rows = {}
  for id, f in pairs(M.FEATURES) do
    local e = data.features[id]
    if e or f.cmd or M._registered[id] then
      local recent = 0
      for d, n in pairs(e and e.days or {}) do
        if M.days_ago(d) < M.RECENT_DAYS then
          recent = recent + n
        end
      end
      table.insert(rows, {
        id = id,
        name = f.name,
        area = f.area,
        doc = f.doc,
        recent = recent,
        total = e and tonumber(e.count) or 0,
        last = e and e.last or nil,
        via = e and e.via or {},
      })
    end
  end
  table.sort(rows, function(a, b)
    return a.id < b.id
  end)
  return rows, data
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
