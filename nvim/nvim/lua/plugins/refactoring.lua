-- "Extract to variable", the refactor VSCode puts on its lightbulb: select an
-- expression in visual mode, press <Leader>lv, and it becomes a new variable
-- declared just above, with the selection replaced by its name.
--
-- Two implementations sit behind that one key. Servers that ship the refactor
-- as a code action (gopls, rust-analyzer) do the extraction themselves and get
-- scope right. `tsc`, the TypeScript 7 server, advertises only quickfix and
-- source.* kinds -- no `refactor.*` at all -- so TypeScript buffers fall
-- through to refactoring.nvim, which works off the treesitter tree instead.

-- Keep the actions that produce a variable/constant; drop the sibling
-- function/type/interface extractions the same `refactor.extract` request
-- returns.
---@param action lsp.CodeAction|lsp.Command
local function extracts_a_variable(action)
  local kind = action.kind or ""
  if vim.startswith(kind, "refactor.extract.variable") or vim.startswith(kind, "refactor.extract.constant") then
    return true
  end
  -- servers that never split `refactor.extract` into sub-kinds only tell the
  -- variants apart by title
  local title = action.title:lower()
  return kind == "refactor.extract" and (title:find "variable" ~= nil or title:find "constant" ~= nil)
end

-- Whether a server attached to the current buffer advertises the refactor.
-- Only an explicit kind counts: none-ls attaches to most buffers declaring no
-- kinds at all, and taking that as a maybe would route every TypeScript
-- extraction to a server that has none.
local function lsp_extracts_variables()
  for _, client in ipairs(vim.lsp.get_clients { bufnr = 0, method = "textDocument/codeAction" }) do
    local provider = client.server_capabilities.codeActionProvider
    for _, kind in ipairs(type(provider) == "table" and provider.codeActionKinds or {}) do
      if kind == "refactor" or vim.startswith(kind, "refactor.extract") then return true end
    end
  end
  return false
end

-- Extracts the visual selection. The LSP path names the variable itself
-- (`newConst`, `x`, ...) and applies straight away when the server offers a
-- single variant, so rename with <Leader>lr afterwards; refactoring.nvim asks
-- for the name up front. Its entry points are operators: they set
-- `operatorfunc` and hand back the `g@` that runs it over the selection.
local function extract_to_variable()
  if lsp_extracts_variables() then
    vim.lsp.buf.code_action {
      context = { only = { "refactor.extract" }, diagnostics = {} },
      filter = extracts_a_variable,
      apply = true,
    }
  else
    vim.api.nvim_feedkeys(require("refactoring").extract_var(), "n", false)
  end
end

---@type LazySpec
return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = { "lewis6991/async.nvim" },
  keys = {
    { "<Leader>lv", extract_to_variable, mode = "x", desc = "Extract to variable" },
  },
  opts = {},
}
