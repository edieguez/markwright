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
      require("markwright.frontmatter").on_save(buf)
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
  -- A buffer variable, not just a Lua table: `:bdelete` / `:bunload` (e.g.
  -- LazyVim's <leader>bd) drop the buffer's keymaps and b: variables but keep
  -- its number, so reopening the file must attach again.
  if M._attached[buf] and vim.b[buf].markwright_attached then
    return
  end
  vim.b[buf].markwright_attached = true
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

--- Make sure markwright's injection (queries/markdown/injections.scm: the
--- text of a footnote like `[^1]: [docs](url)` is parsed as inline Markdown)
--- is in effect. When the plugin is lazy-loaded on the first Markdown buffer,
--- that buffer's highlighter may have read the injection query before the
--- plugin was on 'runtimepath', and the query is cached per language.
local function refresh_injections()
  local q = vim.treesitter.query
  local ok, files = pcall(q.get_files, "markdown", "injections")
  if not ok then
    return
  end
  local ours, text = false, {}
  for _, f in ipairs(files) do
    ours = ours or f:find("markwright", 1, true) ~= nil
    local fd = io.open(f, "r")
    if fd then
      table.insert(text, fd:read("*a"))
      fd:close()
    end
  end
  local cur = q.get("markdown", "injections")
  local has = cur and vim.tbl_contains(cur.captures, "_label")
  if not ours or has then
    return
  end
  if not pcall(q.set, "markdown", "injections", table.concat(text, "\n")) then
    return
  end
  -- parsers that already exist read the old query when they were created
  local new = q.get("markdown", "injections")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(config.options.filetypes, vim.bo[buf].filetype) then
      local okp, p = pcall(vim.treesitter.get_parser, buf, "markdown", { error = false })
      if okp and p and p._injection_query ~= nil then
        p._injection_query = new
        pcall(p.invalidate, p, true)
      end
    end
  end
end

---@param opts? markwright.Config
function M.setup(opts)
  config.setup(opts)
  refresh_injections()
  local group = vim.api.nvim_create_augroup("markwright", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.options.filetypes,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(ev)
      M._attached[ev.buf] = nil
      if package.loaded["markwright.stats"] then
        package.loaded["markwright.stats"]._clear(ev.buf)
      end
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
