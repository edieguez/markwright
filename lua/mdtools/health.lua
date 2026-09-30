local M = {}

function M.check()
  local h = vim.health
  h.start("mdtools.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim >= 0.10 is required")
  end

  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    local ok = pcall(vim.treesitter.language.add, lang)
    if ok then
      h.ok("Treesitter parser '" .. lang .. "' found")
    else
      h.error("Treesitter parser '" .. lang .. "' missing", { ":TSInstall " .. lang })
    end
  end

  if vim.fn.executable("curl") == 1 then
    h.ok("curl found (page-title fetching)")
  else
    h.warn("curl not found: link titles will fall back to the domain name")
  end

  if vim.fn.has("clipboard") == 1 then
    h.ok("clipboard provider available")
  else
    h.warn("no clipboard provider: link creation from the clipboard won't work", { ":h clipboard" })
  end

  if vim.ui.open then
    h.ok("vim.ui.open available (gx)")
  else
    h.warn("vim.ui.open missing")
  end
end

return M
