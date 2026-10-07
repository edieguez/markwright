if vim.g.loaded_markwright then
  return
end
vim.g.loaded_markwright = true

local function feed_expr(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "nx", false)
end

--- Run `fn` with util.count1() = `n` (a number argument, default 1).
local function with_count(n, fn)
  local util = require("markwright.util")
  local prev = util._count
  util._count = math.max(1, tonumber(n) or 1)
  local ok, err = pcall(fn)
  util._count = prev
  if not ok then
    error(err, 0)
  end
end

--- 1-based model indices (header = 1) of buffer lines `line1`..`line2` in
--- the table at line1, or nil.
local function table_rows(args)
  if args.range == 0 then
    return nil
  end
  local sr = require("markwright.tables").find(0, args.line1 - 1)
  if not sr then
    return nil
  end
  vim.api.nvim_win_set_cursor(0, { args.line1, 0 })
  return { args.line1 - sr, args.line2 - sr }
end

local table_sub = {
  create = function()
    require("markwright.tables").create()
  end,
  tocsv = function()
    require("markwright.tables").to_csv()
  end,
  csv = function(args)
    require("markwright.tables").from_csv_prompt(0, args.line1 - 1, args.line2 - 1)
  end,
  fromcsv = function(args)
    if args.range > 0 then
      require("markwright.tables").from_csv_prompt(0, args.line1 - 1, args.line2 - 1)
    else
      require("markwright.tables").from_csv_paragraph()
    end
  end,
  align = function()
    require("markwright.tables").align()
  end,
  row = function(args)
    require("markwright.tables").add_row(false, math.max(1, tonumber(args.fargs[3]) or 1))
  end,
  rowabove = function(args)
    require("markwright.tables").add_row(true, math.max(1, tonumber(args.fargs[3]) or 1))
  end,
  delrow = function(args)
    require("markwright.tables").delete_row(table_rows(args), math.max(1, tonumber(args.fargs[3]) or 1))
  end,
  col = function(args)
    require("markwright.tables").add_col(false, math.max(1, tonumber(args.fargs[3]) or 1))
  end,
  colleft = function(args)
    require("markwright.tables").add_col(true, math.max(1, tonumber(args.fargs[3]) or 1))
  end,
  move = function(args)
    local tables = require("markwright.tables")
    local dir = args.fargs[3]
    local how = ({ up = { "row", -1 }, down = { "row", 1 }, left = { "col", -1 }, right = { "col", 1 } })[dir or ""]
    if not how then
      return vim.notify("markwright: :Markwright table move {up|down|left|right} [count]", vim.log.levels.ERROR)
    end
    with_count(args.fargs[4], function()
      if how[1] == "row" then
        tables.move_row(how[2], table_rows(args))
      else
        tables.move_col(how[2])
      end
    end)
  end,
  sort = function(args)
    require("markwright.tables").sort(args.fargs[3] == "desc", table_rows(args))
  end,
  transpose = function()
    require("markwright.tables").transpose()
  end,
  yank = function()
    require("markwright.tables").yank_csv()
  end,
  delcol = function(args)
    require("markwright.tables").delete_col(nil, math.max(1, tonumber(args.fargs[3]) or 1))
  end,
}

local list_sub = {
  up = function(args)
    with_count(args.fargs[3], function()
      require("markwright.listtools").move(-1)
    end)
  end,
  down = function(args)
    with_count(args.fargs[3], function()
      require("markwright.listtools").move(1)
    end)
  end,
  sort = function(args)
    local mode = args.fargs[3]
    require("markwright.listtools").sort((mode == "desc" or mode == "done") and mode or "asc")
  end,
}
for _, style in ipairs({ "bullet", "number", "checkbox" }) do
  list_sub[style] = function(args)
    local lt = require("markwright.listtools")
    if args.range > 0 then
      lt.convert_lines(style, args.line1 - 1, args.line2 - 1)
    else
      lt.convert(style, args.fargs[3] == "all")
    end
  end
end

local subcommands = {
  health = function()
    vim.cmd("checkhealth markwright")
  end,
  link = function()
    feed_expr(require("markwright.links").expr_normal())
  end,
  follow = function()
    require("markwright.follow").follow()
  end,
  fence = function(args)
    if args.range > 0 then
      require("markwright.fence").wrap(0, args.line1 - 1, args.line2 - 1)
    else
      require("markwright.fence").insert()
    end
  end,
  callout = function(args)
    local sub = args.fargs[2]
    local callouts = require("markwright.callouts")
    if sub == "remove" then
      return callouts.unwrap()
    end
    if args.range > 0 then
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_mark(buf, "<", args.line1, 0, {})
      vim.api.nvim_buf_set_mark(buf, ">", args.line2, 0, {})
      return callouts.wrap_visual(sub)
    end
    callouts.toggle(sub)
  end,
  outline = function()
    require("markwright.nav").outline()
  end,
  footnote = function()
    require("markwright.footnotes").insert()
  end,
  image = function(args)
    if args.fargs[2] == "rename" then
      return require("markwright.images").rename()
    end
    require("markwright.images").paste()
  end,
  toc = function()
    require("markwright.toc").insert()
  end,
  heading = function(args)
    local delta = ({ add = 1, remove = -1 })[args.fargs[2] or ""]
    if not delta then
      return vim.notify("markwright: :[range]Markwright heading {add|remove} [count]", vim.log.levels.ERROR)
    end
    local n = math.max(1, tonumber(args.fargs[3]) or 1)
    local buf = vim.api.nvim_get_current_buf()
    require("markwright.headings").change(buf, args.line1 - 1, args.line2 - 1, delta * n)
  end,
  checkbox = function(args)
    local lists = require("markwright.lists")
    if args.range > 0 then
      lists.toggle_range(args.line1 - 1, args.line2 - 1)
    else
      lists.toggle_checkbox()
    end
  end,
  stats = function(args)
    local range = args.range > 0 and { args.line1 - 1, args.line2 - 1 } or nil
    require("markwright.stats").show(range)
  end,
  check = function(args)
    if args.fargs[2] == "urls" then
      return require("markwright.urlcheck").run(0)
    end
    local d = require("markwright.diagnostics")
    d.check(0)
    local n = #vim.diagnostic.get(0, { namespace = d.ns })
    vim.notify(("markwright: %d link problem%s"):format(n, n == 1 and "" or "s"))
  end,
  list = function(args)
    local fn = list_sub[args.fargs[2] or ""]
    if not fn then
      vim.notify(
        "markwright: :Markwright list {up|down|sort [desc|done]|bullet|number|checkbox [all]}",
        vim.log.levels.ERROR
      )
      return
    end
    fn(args)
  end,
  table = function(args)
    local fn = table_sub[args.fargs[2] or ""]
    if not fn then
      vim.notify(
        "markwright: :Markwright table {create|fromcsv|tocsv|yank|align|sort|transpose|move|row|rowabove|delrow|col|colleft|delcol}",
        vim.log.levels.ERROR
      )
      return
    end
    fn(args)
  end,
}
for _, fmt in ipairs({ "italic", "bold", "strike", "code", "highlight" }) do
  subcommands[fmt] = function()
    require("markwright.format").toggle(fmt)
  end
end

local function sorted_keys(t, lead)
  local names = vim.tbl_filter(function(name)
    return name:find(lead, 1, true) == 1
  end, vim.tbl_keys(t))
  table.sort(names)
  return names
end

vim.api.nvim_create_user_command("Markwright", function(args)
  local fn = subcommands[args.fargs[1] or ""]
  if not fn then
    vim.notify("markwright: unknown subcommand '" .. (args.fargs[1] or "") .. "'", vim.log.levels.ERROR)
    return
  end
  fn(args)
end, {
  nargs = "+",
  range = true,
  desc = "markwright.nvim",
  complete = function(lead, line)
    local words = vim.split((line:gsub("^%S*%s*", "")), "%s+")
    if #words == 2 and words[1] == "list" then
      return sorted_keys(list_sub, lead)
    end
    if #words == 3 and words[1] == "list" and words[2] == "sort" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "desc", "done" })
    end
    if #words == 3 and words[1] == "list" and vim.tbl_contains({ "bullet", "number", "checkbox" }, words[2]) then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "all" })
    end
    if #words == 3 and words[1] == "table" and words[2] == "move" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "down", "left", "right", "up" })
    end
    if #words == 2 and words[1] == "heading" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "add", "remove" })
    end
    if #words == 3 and words[1] == "table" and words[2] == "sort" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "desc" })
    end
    if #words == 2 and words[1] == "table" then
      return sorted_keys(table_sub, lead)
    end
    if #words == 2 and words[1] == "image" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "rename" })
    end
    if #words == 2 and words[1] == "check" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "urls" })
    end
    if #words == 2 and words[1] == "callout" then
      local names = { "remove" }
      for _, t in ipairs(require("markwright.config").options.callouts.types) do
        table.insert(names, t:lower())
      end
      return vim.tbl_filter(function(n)
        return n:find(lead:lower(), 1, true) == 1
      end, names)
    end
    if #words > 1 then
      return {}
    end
    return sorted_keys(subcommands, lead)
  end,
})
