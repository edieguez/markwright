local config = require("mdtools.config")

local M = {}

M._attached = {} ---@type table<integer, true>

local function attach_autocmds(buf)
  local group = vim.api.nvim_create_augroup("mdtools_buf_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      require("mdtools.tables").on_insert_leave()
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    buffer = buf,
    callback = function()
      require("mdtools.toc").on_save(buf)
    end,
  })
  local d = config.options.diagnostics
  if d.enabled then
    if d.on_save then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        buffer = buf,
        callback = function()
          require("mdtools.diagnostics").check(buf)
        end,
      })
    end
    vim.schedule(function()
      require("mdtools.diagnostics").check(buf)
    end)
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      M._attached[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

function M.attach(buf)
  if M._attached[buf] then
    return
  end
  M._attached[buf] = true
  require("mdtools.keymaps").attach(buf)
  attach_autocmds(buf)
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
