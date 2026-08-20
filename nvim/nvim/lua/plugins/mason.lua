-- Community packs (lua, typescript, go, json, yaml) auto-install their
-- own LSPs, formatters, and linters via Mason. Only list extras here.
--
-- Note: AstroNvim clears mason-lspconfig's `ensure_installed` whenever
-- mason-tool-installer is present, so servers belong in this list too.

---@type LazySpec
return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = function(_, opts)
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed or {}, {
        "prettierd",
        "stylua",
        "goimports",
        "tsc", -- TypeScript 7 (npm `typescript`), replaces vtsls for TS/JS
      })
      -- Drop the other TypeScript servers so Mason doesn't keep second and
      -- third copies installed and updated: the astrocommunity typescript pack
      -- asks for vtsls, and `tsgo` is the deprecated preview build of the same
      -- native server that shipped as `tsc` in TypeScript 7.
      opts.ensure_installed =
        vim.tbl_filter(function(pkg) return pkg ~= "vtsls" and pkg ~= "tsgo" end, opts.ensure_installed)
    end,
  },
}
