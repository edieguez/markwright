local config = require("mdtools.config")

local M = {}

M._attached = {} ---@type table<integer, true>

function M.attach(buf)
  if M._attached[buf] then
    return
  end
  M._attached[buf] = true
  require("mdtools.keymaps").attach(buf)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M._attached[buf] = nil
    end,
  })
end

---@param opts? mdtools.Config
function M.setup(opts)
  config.setup(opts)
  local group = vim.api.nvim_create_augroup("mdtools", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.options.filetypes,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  -- lazy-loaded on ft=markdown: the FileType event for the first buffer already fired
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(config.options.filetypes, vim.bo[buf].filetype) then
      M.attach(buf)
    end
  end
end

return M
