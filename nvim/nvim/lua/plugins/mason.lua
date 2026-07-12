-- Community packs (lua, typescript, go, json, yaml) auto-install their
-- own LSPs, formatters, and linters via Mason. Only list extras here.

---@type LazySpec
return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = {
      ensure_installed = {
        "prettierd",
        "stylua",
        "goimports",
      },
    },
  },
}
