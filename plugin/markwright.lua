if vim.g.loaded_markwright then
  return
end
vim.g.loaded_markwright = true

local function feed_expr(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "nx", false)
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
  align = function()
    require("markwright.tables").align()
  end,
  row = function()
    require("markwright.tables").add_row()
  end,
  rowabove = function()
    require("markwright.tables").add_row(true)
  end,
  delrow = function()
    require("markwright.tables").delete_row()
  end,
  col = function()
    require("markwright.tables").add_col()
  end,
  colleft = function()
    require("markwright.tables").add_col(true)
  end,
  sort = function(args)
    require("markwright.tables").sort(args.fargs[3] == "desc")
  end,
  transpose = function()
    require("markwright.tables").transpose()
  end,
  yank = function()
    require("markwright.tables").yank_csv()
  end,
  delcol = function()
    require("markwright.tables").delete_col()
  end,
}

local list_sub = {
  up = function()
    require("markwright.listtools").move(-1)
  end,
  down = function()
    require("markwright.listtools").move(1)
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
        "markwright: :Markwright table {create|csv|tocsv|yank|align|sort|transpose|row|rowabove|delrow|col|colleft|delcol}",
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
    if #words == 3 and words[1] == "table" and words[2] == "sort" then
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, { "desc" })
    end
    if #words >= 2 and words[1] == "table" then
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
