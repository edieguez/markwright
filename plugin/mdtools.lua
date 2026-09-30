if vim.g.loaded_mdtools then
  return
end
vim.g.loaded_mdtools = true

-- Subcommands; later modules register theirs here.
local subcommands = {
  health = function()
    vim.cmd("checkhealth mdtools")
  end,
}
for _, fmt in ipairs({ "italic", "bold", "strike", "code", "highlight" }) do
  subcommands[fmt] = function()
    require("mdtools.format").toggle(fmt)
  end
end

vim.api.nvim_create_user_command("Mdtools", function(args)
  local fn = subcommands[args.fargs[1] or ""]
  if not fn then
    vim.notify("mdtools: unknown subcommand '" .. (args.fargs[1] or "") .. "'", vim.log.levels.ERROR)
    return
  end
  fn(args)
end, {
  nargs = 1,
  desc = "mdtools.nvim",
  complete = function(lead)
    local names = vim.tbl_filter(function(name)
      return name:find(lead, 1, true) == 1
    end, vim.tbl_keys(subcommands))
    table.sort(names)
    return names
  end,
})
