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

-- Footnote definitions whose text is a single word or link ------------------
--
-- The markdown grammar has no footnotes: `[^1]: [docs](https://x.io)` (no
-- space in the text) is a valid *link reference definition* to it, label `^1`
-- and destination `[docs](https://x.io)`, so the text is never parsed as
-- inline Markdown and the link in it doesn't exist for gx, the link key or the
-- text objects. For such lines the text is parsed on its own, and its nodes
-- are wrapped so their ranges are buffer positions.

local Proxy = {}
Proxy.__index = Proxy

local function wrap(node, row, off)
  return node and setmetatable({ _n = node, _row = row, _off = off }, Proxy) or nil
end

function Proxy:type()
  return self._n:type()
end
function Proxy:named()
  return self._n:named()
end
function Proxy:id()
  return self._n:id()
end
function Proxy:range()
  local sr, sc, er, ec = self._n:range()
  return self._row + sr, sc + self._off, self._row + er, ec + self._off
end
function Proxy:start()
  local r, c = self:range()
  return r, c
end
function Proxy:end_()
  local _, _, r, c = self:range()
  return r, c
end
function Proxy:parent()
  return wrap(self._n:parent(), self._row, self._off)
end
function Proxy:iter_children()
  local it = self._n:iter_children()
  return function()
    local c, field = it()
    if c then
      return wrap(c, self._row, self._off), field
    end
  end
end
function Proxy:child_count()
  return self._n:child_count()
end
function Proxy:child(i)
  return wrap(self._n:child(i), self._row, self._off)
end
function Proxy:named_child_count()
  return self._n:named_child_count()
end
function Proxy:named_child(i)
  return wrap(self._n:named_child(i), self._row, self._off)
end
function Proxy:equal(other)
  return getmetatable(other) == Proxy and self._n:equal(other._n)
end

M.FOOTNOTE_DEF = "^(%s*%[%^[^%]%s]+%]:%s*)"

--- Inline node at (row, col) inside the text of a footnote definition that
--- the grammar read as a reference definition, or nil.
local function footnote_text_node(p, row, col)
  local buf = p:source()
  if type(buf) ~= "number" then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local prefix = line:match(M.FOOTNOTE_DEF)
  if not prefix or col < #prefix then
    return nil
  end
  local block = M.block_node(p, row, #prefix)
  if not M.ancestor(block, { link_reference_definition = true }) then
    return nil -- parsed as a paragraph: the normal inline tree has it
  end
  local text = line:sub(#prefix + 1)
  local ok, sp = pcall(vim.treesitter.get_string_parser, text, "markdown_inline")
  if not ok or not sp then
    return nil
  end
  local tree = sp:parse()[1]
  local node = tree and tree:root():named_descendant_for_range(0, col - #prefix, 0, col - #prefix)
  return wrap(node, row, #prefix)
end

--- Root of the separately parsed text of a footnote definition on `row`
--- (see above), or nil when the line is parsed normally.
function M.footnote_text_root(p, row)
  local buf = p:source()
  if type(buf) ~= "number" then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local prefix = line:match(M.FOOTNOTE_DEF)
  if not prefix or #prefix == #line then
    return nil
  end
  if not M.ancestor(M.block_node(p, row, #prefix), { link_reference_definition = true }) then
    return nil
  end
  local inl = p:children()["markdown_inline"]
  if inl and inl:named_node_for_range({ row, #prefix, row, #prefix }, { ignore_injections = true }) then
    return nil -- injected by queries/markdown/injections.scm: already an inline tree
  end
  local ok, sp = pcall(vim.treesitter.get_string_parser, line:sub(#prefix + 1), "markdown_inline")
  local tree = ok and sp and sp:parse()[1]
  return tree and wrap(tree:root(), row, #prefix) or nil
end

--- Roots of every inline tree in rows `srow`..`erow` (all rows when nil),
--- including the footnote texts the grammar doesn't parse inline.
function M.inline_roots(p, srow, erow)
  local roots = {}
  local inl = p:children()["markdown_inline"]
  if inl then
    for _, tree in ipairs(inl:trees()) do
      local sr, _, er = tree:root():range()
      if not srow or (er >= srow and sr <= erow) then
        table.insert(roots, tree:root())
      end
    end
  end
  local buf = p:source()
  if type(buf) == "number" then
    local first = srow or 0
    local lines = vim.api.nvim_buf_get_lines(buf, first, erow and erow + 1 or -1, false)
    for i, l in ipairs(lines) do
      if l:match(M.FOOTNOTE_DEF) then
        local root = M.footnote_text_root(p, first + i - 1)
        if root then
          table.insert(roots, root)
        end
      end
    end
  end
  return roots
end

--- Text of a node, from the buffer (works for wrapped nodes too).
function M.node_text(node, buf)
  local sr, sc, er, ec = node:range()
  return table.concat(vim.api.nvim_buf_get_text(buf, sr, sc, er, ec, {}), "\n")
end

--- Smallest named node of the markdown_inline tree at a position.
function M.inline_node(p, row, col)
  local inl = p:children()["markdown_inline"]
  local node = inl and inl:named_node_for_range({ row, col, row, col }, { ignore_injections = true })
  if node and node:type() == "inline" and not node:parent() then
    -- root of an inline tree: only useful if it really contains the position
    local sr, sc, er, ec = node:range()
    if (row < sr or (row == sr and col < sc)) or (row > er or (row == er and col > ec)) then
      node = nil
    end
  end
  return node or footnote_text_node(p, row, col)
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
