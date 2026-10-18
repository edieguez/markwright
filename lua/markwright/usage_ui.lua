-- :Markwright usage — the usage report in a floating window.
--
-- One row per feature, grouped by area (a toggles a flat list), sorted by
-- uses in the last 30 days (s cycles 30 days / all time / name). Features
-- never used are listed after each area's used ones (u shows them as rows);
-- the "Automatic" area holds what markwright did on keys that keep their
-- usual meaning elsewhere (<CR>, <Tab>, o, p). <CR> opens the feature's
-- README section. The buffer isn't Markdown, so markwright doesn't attach to
-- it and moving around in it doesn't count.
local api = vim.api
local usage = require("markwright.usage")

local M = {}

local ns = api.nvim_create_namespace("markwright_usage")

M.SORTS = { "recent", "total", "name" }
local SORT_LABEL = { recent = "30 days", total = "all time", name = "name" }

M.state = { sort = "recent", grouped = true, unused_rows = false }
M._win, M._buf = nil, nil

local BAR = 10
local EIGHTHS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" }

local function set_hl()
  local links = {
    MarkwrightUsageTitle = "Title",
    MarkwrightUsageArea = "Title",
    MarkwrightUsageBar = "Special",
    MarkwrightUsageNumber = "Number",
    MarkwrightUsageDim = "Comment",
    MarkwrightUsageHeader = "Comment",
  }
  for name, link in pairs(links) do
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

function M.bar(value, max)
  if max <= 0 or value <= 0 then
    return ""
  end
  local eighths = math.max(1, math.floor(value / max * BAR * 8 + 0.5))
  return string.rep("█", math.floor(eighths / 8)) .. (eighths % 8 > 0 and EIGHTHS[eighths % 8] or "")
end

local function num(n)
  local s = tostring(n)
  while true do
    local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    s = r
    if k == 0 then
      return s
    end
  end
end

function M.relative(date)
  if not date then
    return "—"
  end
  local d = usage.days_ago(date)
  if d <= 0 then
    return "today"
  elseif d == 1 then
    return "yesterday"
  elseif d < 30 then
    return d .. " days ago"
  end
  return date
end

local VIA = { { "key", "key" }, { "visual", "visual" }, { "insert", ";;" }, { "command", "cmd" } }

function M.via_text(via)
  local parts = {}
  for _, v in ipairs(VIA) do
    local n = tonumber(via[v[1]]) or 0
    if n > 0 then
      table.insert(parts, { v[2], n })
    end
  end
  table.sort(parts, function(a, b)
    return a[2] > b[2]
  end)
  if #parts == 1 then
    return parts[1][1]
  end
  local out = {}
  for _, p in ipairs(parts) do
    table.insert(out, p[1] .. " " .. num(p[2]))
  end
  return table.concat(out, " · ")
end

local function metric(r, sort)
  return sort == "total" and r.total or r.recent
end

local function compare(sort)
  return function(a, b)
    if sort ~= "name" then
      local ma, mb = metric(a, sort), metric(b, sort)
      if ma ~= mb then
        return ma > mb
      end
      if a.total ~= b.total then
        return a.total > b.total
      end
    end
    return a.name < b.name
  end
end

--- Report lines, highlights ({ line, col_start, col_end, group }) and the
--- feature row of each line.
---@param rows markwright.UsageRow[]
---@param data table
---@param st {sort: string, grouped: boolean, unused_rows: boolean}
---@param width integer
function M.render(rows, data, st, width)
  local lines, hls, at = {}, {}, {}
  local function add(text, group, row)
    text = text:gsub("%s+$", "")
    table.insert(lines, text)
    if group then
      table.insert(hls, { #lines - 1, 0, #text, group })
    end
    at[#lines] = row
  end

  -- automatic features (markwright acting on <CR>, <Tab>...) are counted
  -- apart: they'd dwarf what's chosen on purpose
  local recent_all, total_all, used_recent, auto_total = 0, 0, 0, 0
  for _, r in ipairs(rows) do
    if r.area == "Automatic" then
      auto_total = auto_total + r.total
    else
      recent_all, total_all = recent_all + r.recent, total_all + r.total
      used_recent = used_recent + (r.recent > 0 and 1 or 0)
    end
  end
  add(
    (" Since %s · last 30 days: %s use%s of %d feature%s · all time: %s · automatic: %s"):format(
      data.since,
      num(recent_all),
      recent_all == 1 and "" or "s",
      used_recent,
      used_recent == 1 and "" or "s",
      num(total_all),
      num(auto_total)
    ),
    "MarkwrightUsageHeader"
  )
  add(" Stored only on this machine: " .. vim.fn.fnamemodify(usage.path(), ":~"), "MarkwrightUsageHeader")
  add("")

  -- columns
  local name_w = 24
  for _, r in ipairs(rows) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(r.name) + 4) -- indent + gap
  end
  local function pad(s, w, right)
    local gap = string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s)))
    return right and (gap .. s) or (s .. gap)
  end
  local function cols(name, bar, recent, total, last, via)
    return " "
      .. pad(name, name_w)
      .. pad(bar, BAR + 1)
      .. pad(recent, 8, true)
      .. pad(total, 8, true)
      .. "  "
      .. pad(last, 12)
      .. via
  end
  add(cols("", "", "30 days", "total", "last used", "how"), "MarkwrightUsageHeader")

  -- bars: deliberate features against each other, automatic ones apart
  local max = { deliberate = 0, auto = 0 }
  local function kind(r)
    return r.area == "Automatic" and "auto" or "deliberate"
  end
  for _, r in ipairs(rows) do
    max[kind(r)] = math.max(max[kind(r)], st.sort == "recent" and r.recent or r.total)
  end
  local function feature_line(r)
    local b = M.bar(st.sort == "recent" and r.recent or r.total, max[kind(r)])
    local how = r.area == "Automatic" and "" or M.via_text(r.via)
    add(cols("  " .. r.name, b, num(r.recent), num(r.total), M.relative(r.last), how), nil, r)
    if b ~= "" then
      local start = #(" " .. pad("  " .. r.name, name_w))
      table.insert(hls, { #lines - 1, start, start + #b, "MarkwrightUsageBar" })
    end
  end
  local function unused_lines(list, indent, label)
    table.sort(list, compare("name"))
    if st.unused_rows then
      for _, r in ipairs(list) do
        add(cols(indent .. r.name, "", "", "", "never", ""), "MarkwrightUsageDim", r)
      end
      return
    end
    local names = vim.tbl_map(function(r)
      return r.name
    end, list)
    local lead = indent .. (label or "never used") .. ": "
    local cur = " " .. lead
    for i, n in ipairs(names) do
      local piece = n .. (i < #names and ", " or "")
      if vim.fn.strdisplaywidth(cur .. piece) > width - 1 and cur ~= " " .. lead then
        add(cur:gsub("%s+$", ""), "MarkwrightUsageDim")
        cur = " " .. string.rep(" ", vim.fn.strdisplaywidth(lead))
      end
      cur = cur .. piece
    end
    add(cur, "MarkwrightUsageDim")
  end

  local by_area = {}
  for _, r in ipairs(rows) do
    by_area[r.area] = by_area[r.area] or { used = {}, unused = {}, recent = 0, total = 0 }
    local a = by_area[r.area]
    table.insert(r.total > 0 and a.used or a.unused, r)
    a.recent, a.total = a.recent + r.recent, a.total + r.total
  end
  local order = {}
  for name in pairs(by_area) do
    if name ~= "Automatic" then
      table.insert(order, name)
    end
  end
  local rank = {}
  for i, a in ipairs(usage.AREAS) do
    rank[a] = i
  end
  table.sort(order, function(x, y)
    if st.sort ~= "name" then
      local mx, my = metric(by_area[x], st.sort), metric(by_area[y], st.sort)
      if mx ~= my then
        return mx > my
      end
    end
    return (rank[x] or 99) < (rank[y] or 99)
  end)

  local function area_header(name, a, note)
    add("")
    if a.total == 0 then
      add(" " .. name, "MarkwrightUsageDim")
      return
    end
    local text = cols(name, "", num(a.recent), num(a.total), "", note or "")
    add(text, nil)
    table.insert(hls, { #lines - 1, 0, #name + 1, "MarkwrightUsageArea" })
  end

  if st.grouped then
    for _, name in ipairs(order) do
      local a = by_area[name]
      area_header(name, a)
      table.sort(a.used, compare(st.sort))
      for _, r in ipairs(a.used) do
        feature_line(r)
      end
      if #a.unused > 0 then
        unused_lines(a.unused, "  ")
      end
    end
  else
    local used = {}
    for _, name in ipairs(order) do
      vim.list_extend(used, by_area[name].used)
    end
    table.sort(used, compare(st.sort))
    add("")
    if #used == 0 then
      add("   Nothing counted yet.", "MarkwrightUsageDim")
    end
    for _, r in ipairs(used) do
      feature_line(r)
    end
    local any = false
    for _, name in ipairs(order) do
      if #by_area[name].unused > 0 then
        if not any then
          add("")
          add(" Never used", "MarkwrightUsageArea")
          any = true
        end
        unused_lines(by_area[name].unused, "  ", name)
      end
    end
  end

  local auto = by_area.Automatic
  if auto then
    area_header("Automatic", auto, "markwright acting on <CR>, <Tab>, o, O, p")
    table.sort(auto.used, compare(st.sort))
    for _, r in ipairs(auto.used) do
      feature_line(r)
    end
    if #auto.unused > 0 then
      unused_lines(auto.unused, "  ")
    end
  end
  return lines, hls, at
end

local function footer()
  return {
    { " s ", "Special" },
    { "sort: " .. SORT_LABEL[M.state.sort] .. "  ", "Normal" },
    { "a ", "Special" },
    { (M.state.grouped and "flat list" or "by area") .. "  ", "Normal" },
    { "u ", "Special" },
    { (M.state.unused_rows and "fold unused" or "unused as rows") .. "  ", "Normal" },
    { "<CR> ", "Special" },
    { "docs  ", "Normal" },
    { "r ", "Special" },
    { "refresh  ", "Normal" },
    { "q ", "Special" },
    { "close ", "Normal" },
  }
end

local function size()
  local width = math.min(vim.o.columns - 4, 110)
  return math.max(40, width)
end

function M.refresh()
  local buf, win = M._buf, M._win
  if not (buf and api.nvim_buf_is_valid(buf)) then
    return
  end
  usage.flush()
  local rows, data = usage.rows()
  local width = (win and api.nvim_win_is_valid(win)) and api.nvim_win_get_width(win) or size()
  local lines, hls, at = M.render(rows, data, M.state, width)
  M._at = at
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(api.nvim_buf_set_extmark, buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
  if win and api.nvim_win_is_valid(win) then
    local height = math.min(#lines, vim.o.lines - 6)
    api.nvim_win_set_config(win, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2) - 1,
      col = math.floor((vim.o.columns - width) / 2),
      footer = footer(),
      footer_pos = "center",
    })
  end
end

function M.close()
  if M._win and api.nvim_win_is_valid(M._win) then
    api.nvim_win_close(M._win, true)
  end
  M._win = nil
end

local function plugin_root()
  return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
end

--- Open the README (read-only) at the feature's section.
function M.open_docs(row)
  if not row or not row.doc then
    return
  end
  local readme = plugin_root() .. "/README.md"
  if vim.fn.filereadable(readme) == 0 then
    return require("markwright.util").warn("README.md not found")
  end
  M.close()
  vim.cmd("sview " .. vim.fn.fnameescape(readme))
  local target = row.doc
  for i, l in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    local h = l:match("^#+%s+(.-)%s*$")
    if h == target then
      api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd("normal! zt")
      return
    end
  end
end

function M.show()
  if not usage.enabled() then
    return require("markwright.util").notify("usage counting is off (usage.enabled = false in your setup)")
  end
  set_hl()
  if M._win and api.nvim_win_is_valid(M._win) then
    api.nvim_set_current_win(M._win)
    return M.refresh()
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markwright-usage"
  M._buf = buf
  local width = size()
  M._win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 10,
    row = 2,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " markwright usage ",
    title_pos = "center",
  })
  vim.wo[M._win].cursorline = true
  vim.wo[M._win].wrap = false
  local function key(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  key("q", M.close)
  key("<Esc>", M.close)
  key("r", M.refresh)
  key("s", function()
    local i = 1
    for k, v in ipairs(M.SORTS) do
      if v == M.state.sort then
        i = k
      end
    end
    M.state.sort = M.SORTS[i % #M.SORTS + 1]
    M.refresh()
  end)
  key("a", function()
    M.state.grouped = not M.state.grouped
    M.refresh()
  end)
  key("u", function()
    M.state.unused_rows = not M.state.unused_rows
    M.refresh()
  end)
  key("<CR>", function()
    M.open_docs(M._at and M._at[api.nvim_win_get_cursor(0)[1]])
  end)
  api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })
  M.refresh()
  -- start on the first feature
  for l = 1, api.nvim_buf_line_count(buf) do
    if M._at[l] then
      api.nvim_win_set_cursor(M._win, { l, 0 })
      break
    end
  end
end

return M
