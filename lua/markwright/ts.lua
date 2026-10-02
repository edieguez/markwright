-- Treesitter helpers for the markdown / markdown_inline parsers.
local M = {}

---@return vim.treesitter.LanguageTree?
function M.parser(buf)
  local ok, p = pcall(vim.treesitter.get_parser, buf, "markdown", { error = false })
  if ok and p then
    return p
  end
end

--- Parse (incrementally) the rows around a range, including injections.
---@return vim.treesitter.LanguageTree?
function M.parse(buf, srow, erow)
  local p = M.parser(buf)
  if not p then
    return nil
  end
  p:parse({ srow, (erow or srow) + 1 })
  return p
end

--- Smallest named node of the block-level (markdown) tree at a position.
function M.block_node(p, row, col)
  return p:named_node_for_range({ row, col, row, col }, { ignore_injections = true })
end

--- Smallest named node of the markdown_inline tree at a position.
function M.inline_node(p, row, col)
  local inl = p:children()["markdown_inline"]
  if not inl then
    return nil
  end
  local node = inl:named_node_for_range({ row, col, row, col }, { ignore_injections = true })
  if node and node:type() == "inline" and not node:parent() then
    -- root of an inline tree: only useful if it really contains the position
    local sr, sc, er, ec = node:range()
    if (row < sr or (row == sr and col < sc)) or (row > er or (row == er and col > ec)) then
      return nil
    end
  end
  return node
end

---@param node TSNode?
---@param types table<string, true>
---@return TSNode?
--- Is `node` a GitHub callout marker (`> [!WARNING]`)? Tree-sitter parses the
--- marker as a shortcut link, but it isn't one: link keys, text objects and
--- `gx` must leave it alone. `src` is the buffer (or a parser: its source).
function M.is_callout_marker(node, src)
  if not node or node:type() ~= "shortcut_link" then
    return false
  end
  local buf = type(src) == "number" and src or src:source()
  if type(buf) ~= "number" then
    return false
  end
  local sr, sc = node:range()
  local line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
  return line:sub(1, sc):match("^%s*>[%s>]*$") ~= nil and line:sub(sc + 1):match("^%[!%a+%]") ~= nil
end

function M.ancestor(node, types)
  while node do
    if types[node:type()] then
      return node
    end
    node = node:parent()
  end
end

local BLOCK_CODE = { fenced_code_block = true, indented_code_block = true, html_block = true }
local SPAN_CODE = { code_span = true }

--- Is the position inside code? Returns "block", "span" or nil.
function M.code_context(p, row, col)
  if not p then
    return nil
  end
  if M.ancestor(M.block_node(p, row, col), BLOCK_CODE) then
    return "block"
  end
  if M.ancestor(M.inline_node(p, row, col), SPAN_CODE) then
    return "span"
  end
end

return M
