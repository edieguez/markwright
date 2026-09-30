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
  csv = function(args)
    require("markwright.tables").from_csv(0, args.line1 - 1, args.line2 - 1)
  end,
  align = function()
    require("markwright.tables").align()
  end,
  row = function()
    require("markwright.tables").add_row()
  end,
  delrow = function()
    require("markwright.tables").delete_row()
  end,
  col = function()
    require("markwright.tables").add_col()
  end,
  delcol = function()
    require("markwright.tables").delete_col()
  end,
}

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
  footnote = function()
    require("markwright.footnotes").insert()
  end,
  image = function()
    require("markwright.images").paste()
  end,
  toc = function()
    require("markwright.toc").insert()
  end,
  check = function()
    local d = require("markwright.diagnostics")
    d.check(0)
    local n = #vim.diagnostic.get(0, { namespace = d.ns })
    vim.notify(("markwright: %d link problem%s"):format(n, n == 1 and "" or "s"))
  end,
  table = function(args)
    local fn = table_sub[args.fargs[2] or ""]
    if not fn then
      vim.notify("markwright: :Markwright table {create|csv|align|row|delrow|col|delcol}", vim.log.levels.ERROR)
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
    if #words >= 2 and words[1] == "table" then
      return sorted_keys(table_sub, lead)
    end
    if #words > 1 then
      return {}
    end
    return sorted_keys(subcommands, lead)
  end,
})
