-- AstroLSP configuration for cloud-apps monorepo

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
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
