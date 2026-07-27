-- AstroLSP configuration for cloud-apps monorepo

-- Jump the current window to a quickfix-style location item.
local function jump_to(item)
  vim.cmd.edit(vim.fn.fnameescape(item.filename))
  pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, math.max(0, (item.col or 1) - 1) })
  vim.cmd "normal! zz"
end

-- Go to definition that dedupes results (LSP servers in a monorepo often
-- return the same location twice) and, when several distinct definitions
-- exist, presents a selection dialog instead of opening a new buffer/quickfix.
local function goto_definition()
  vim.lsp.buf.definition {
    on_list = function(options)
      local seen, items = {}, {}
      for _, item in ipairs(options.items or {}) do
        local key = string.format("%s:%d:%d", item.filename or "", item.lnum or 0, item.col or 0)
        if not seen[key] then
          seen[key] = true
          items[#items + 1] = item
        end
      end

      if #items == 0 then
        vim.notify("No definition found", vim.log.levels.INFO)
      elseif #items == 1 then
        jump_to(items[1])
      else
        vim.ui.select(items, {
          prompt = options.title or "Definitions",
          format_item = function(item)
            return string.format("%s:%d  %s", vim.fn.fnamemodify(item.filename, ":~:."), item.lnum, vim.trim(item.text or ""))
          end,
        }, function(choice)
          if choice then jump_to(choice) end
        end)
      end
    end,
  }
end

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    mappings = {
      n = {
        gd = {
          goto_definition,
          desc = "Go to definition",
          cond = "textDocument/definition",
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
      ts_ls = false, -- use vtsls only; avoid double TS servers
    },
    config = {
      vtsls = {
        settings = {
          typescript = {
            tsserver = {
              maxTsServerMemory = 8192, -- prevent OOM crashes in large monorepo
            },
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
