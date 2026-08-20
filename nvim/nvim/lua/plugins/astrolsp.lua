-- AstroLSP configuration for cloud-apps monorepo

-- Every LSP list -- definitions, references, implementations, symbols -- opens
-- in the snacks picker (the same fuzzy-find UI as <Leader>ff) instead of the
-- quickfix window, so the list previews as you move and closes on selection.
local picker_opts = {
  auto_confirm = true, -- single result: jump straight there, don't show the list
  unique_lines = true, -- monorepo servers routinely return the same location twice
  jump = { tagstack = true, reuse_win = true },
}

-- Build an AstroLSP mapping that opens `source` in the snacks picker, falling
-- back to the stock `vim.lsp.buf` handler if snacks isn't loaded.
---@param source string snacks picker source, e.g. "lsp_references"
---@param fallback function
---@param spec table extra AstroLSP mapping fields (desc, cond, ...)
local function pick(source, fallback, spec)
  return vim.tbl_extend("error", {
    function()
      local ok, snacks = pcall(require, "snacks")
      if ok and snacks.picker then
        snacks.picker[source](picker_opts)
      else
        fallback()
      end
    end,
  }, spec)
end

-- Show an arbitrary list of quickfix-style locations in the same picker.
local function show_locations(items, title)
  if #items == 0 then return vim.notify("No results", vim.log.levels.INFO) end

  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.fn.setqflist({}, " ", { title = title, items = items })
    return vim.cmd.copen()
  end

  snacks.picker.pick(vim.tbl_extend("force", picker_opts, {
    title = title,
    format = "file",
    items = vim.tbl_map(function(item)
      return {
        file = item.filename,
        pos = { item.lnum, math.max(0, (item.col or 1) - 1) },
        text = item.filename .. " " .. (item.text or ""),
        line = item.text,
      }
    end, items),
  }))
end

-- Go to source definition: skips generated `.d.ts` files and lands on the real
-- implementation. vtsls exposed this as an executeCommand; tsc advertises it
-- as the custom request below (see its `customSourceDefinitionProvider`
-- experimental server capability). Falls back to a plain definition jump.
local function goto_source_definition()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "tsc" })[1]
  if not client then return vim.lsp.buf.definition() end

  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request("custom/textDocument/sourceDefinition", params, function(err, result)
    if err or not result or vim.tbl_isempty(result) then return vim.lsp.buf.definition() end
    show_locations(vim.lsp.util.locations_to_items(result, client.offset_encoding), "Source Definitions")
  end, 0)
end

-- Inlay hints. TypeScript 7's server reads a single `js/ts` config section, so
-- TS and JS no longer get separate settings the way they did under vtsls.
local inlay_hints = {
  enumMemberValues = { enabled = true },
  functionLikeReturnTypes = { enabled = true },
  parameterNames = { enabled = "all", suppressWhenArgumentMatchesName = true },
  parameterTypes = { enabled = true },
  propertyDeclarationTypes = { enabled = true },
  variableTypes = { enabled = true },
}

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    -- `gr*`/`gO` are Neovim's built-in LSP mappings and `gd`/`gD`/`gy` are
    -- AstroNvim's; both are overridden here so every entry point lands in the
    -- picker rather than the quickfix window.
    mappings = {
      n = {
        gd = pick("lsp_definitions", vim.lsp.buf.definition, {
          desc = "Go to definition",
          cond = "textDocument/definition",
        }),
        gD = pick("lsp_declarations", vim.lsp.buf.declaration, {
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        }),
        gI = pick("lsp_implementations", vim.lsp.buf.implementation, {
          desc = "Implementation of current symbol",
          cond = "textDocument/implementation",
        }),
        gri = pick("lsp_implementations", vim.lsp.buf.implementation, {
          desc = "Implementation of current symbol",
          cond = "textDocument/implementation",
        }),
        gy = pick("lsp_type_definitions", vim.lsp.buf.type_definition, {
          desc = "Definition of current type",
          cond = "textDocument/typeDefinition",
        }),
        grt = pick("lsp_type_definitions", vim.lsp.buf.type_definition, {
          desc = "Definition of current type",
          cond = "textDocument/typeDefinition",
        }),
        gr = pick("lsp_references", vim.lsp.buf.references, {
          desc = "References of current symbol",
          cond = "textDocument/references",
        }),
        grr = pick("lsp_references", vim.lsp.buf.references, {
          desc = "References of current symbol",
          cond = "textDocument/references",
        }),
        ["<Leader>lR"] = pick("lsp_references", vim.lsp.buf.references, {
          desc = "Search references",
          cond = "textDocument/references",
        }),
        gO = pick("lsp_symbols", vim.lsp.buf.document_symbol, {
          desc = "Search document symbols",
          cond = "textDocument/documentSymbol",
        }),
        ["<Leader>lG"] = pick("lsp_workspace_symbols", vim.lsp.buf.workspace_symbol, {
          desc = "Search workspace symbols",
          cond = "workspace/symbol",
        }),
        ["<Leader>lci"] = pick("lsp_incoming_calls", vim.lsp.buf.incoming_calls, {
          desc = "Incoming calls",
          cond = "textDocument/prepareCallHierarchy",
        }),
        ["<Leader>lco"] = pick("lsp_outgoing_calls", vim.lsp.buf.outgoing_calls, {
          desc = "Outgoing calls",
          cond = "textDocument/prepareCallHierarchy",
        }),
        gs = {
          goto_source_definition,
          desc = "Go to source definition",
          cond = function(client) return client.name == "tsc" end,
        },
      },
    },
    features = {
      codelens = true,
      inlay_hints = false,
      semantic_tokens = true,
    },
    formatting = {
      format_on_save = {
        enabled = true,
      },
      timeout_ms = 3000, -- longer timeout for large monorepo
    },
    handlers = {
      ts_ls = false, -- tsc is the only TypeScript server; avoid double TS servers
      tsgo = false, -- renamed to tsc in TypeScript 7; lspconfig keeps it as a deprecated alias
      vtsls = false, -- superseded by tsc (astrocommunity's typescript pack still pulls it in)
    },
    config = {
      -- tsc (the TypeScript 7 native server, formerly tsgo) serves the whole
      -- monorepo from a single process and resolves the right tsconfig.json per
      -- package by itself, so it needs no memory tuning the way vtsls'
      -- node-based tsserver did.
      tsc = {
        settings = {
          ["js/ts"] = {
            inlayHints = inlay_hints,
            -- nvim-lspconfig enables both by default; they hang "N references"
            -- and "N implementations" codelenses above every signature. `gr`
            -- and `gI` already cover it.
            referencesCodeLens = { enabled = false },
            implementationsCodeLens = { enabled = false },
          },
        },
      },
      eslint = {
        settings = {
          workingDirectories = { mode = "auto" }, -- auto-detect working dir per file
        },
      },
      gopls = {
        settings = {
          gopls = {
            -- Keep gopls out of directories that hold copies of the repo.
            -- Claude Code checks out git worktrees under `.claude/worktrees`,
            -- which are full clones of the monorepo: without this filter gopls
            -- indexes the tree ~5x over (33k Go files instead of 6.6k, 700k
            -- files total), taking 30s to load and pegging every core.
            directoryFilters = {
              "-**/node_modules",
              "-**/.claude",
              "-**/.git",
              "-**/dist",
              "-**/.nx",
            },
            analyses = {
              unusedparams = true,
              shadow = true,
            },
            staticcheck = true,
          },
        },
      },
    },
  },
}
