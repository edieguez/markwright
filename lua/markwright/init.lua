local config = require("markwright.config")

local M = {}

M._attached = {} ---@type table<integer, true>

local function attach_autocmds(buf)
  local group = vim.api.nvim_create_augroup("markwright_buf_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      require("markwright.tables").on_insert_leave()
      require("markwright.lists").on_change()
    end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    buffer = buf,
    callback = function()
      -- not after undo/redo: that would re-apply what the user just undid
      local ut = vim.fn.undotree()
      require("markwright.lists").on_change({ undo = ut.seq_cur ~= ut.seq_last })
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    buffer = buf,
    callback = function()
      require("markwright.toc").on_save(buf)
      require("markwright.lists").update_progress(buf, { join = true })
    end,
  })
  local d = config.options.diagnostics
  if d.enabled then
    if d.on_save then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        buffer = buf,
        callback = function()
          require("markwright.diagnostics").check(buf)
        end,
      })
    end
    vim.schedule(function()
      require("markwright.diagnostics").check(buf)
    end)
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      M._attached[buf] = nil
      if package.loaded["markwright.stats"] then
        package.loaded["markwright.stats"]._clear(buf)
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

function M.attach(buf)
  if M._attached[buf] then
    return
  end
  M._attached[buf] = true
  require("markwright.keymaps").attach(buf)
  attach_autocmds(buf)
  require("markwright.lists").attach(buf)
end

--- Word count and reading time for `buf` (default: current), or for the
--- visual selection when one is active: { words, chars, reading_minutes }.
function M.stats(buf)
  return require("markwright.stats").get(buf)
end

---@param opts? markwright.Config
function M.setup(opts)
  config.setup(opts)
  local group = vim.api.nvim_create_augroup("markwright", { clear = true })
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
