-- Keep AstroNvim aligned with astrolsp v4 and mason-lspconfig v2.
--
-- AstroNvim v5.3.x still calls `astrolsp.mason-lspconfig`, which was removed in
-- astrolsp v4. Newer AstroNvim main uses mason-org/mason-lspconfig.nvim instead.
-- Without these pins, a stale lazy checkout can leave Neovim broken after pull.

---@type LazySpec
return {
  {
    "AstroNvim/AstroNvim",
    version = false,
    commit = "7fc1bf55037f98b3270eed761cb5b0794b30e7d2",
  },
  {
    "AstroNvim/astrolsp",
    version = false,
    commit = "ebc1676127b3bfbd46e3e26589b104853cac3730",
  },
  {
    "mason-org/mason-lspconfig.nvim",
    version = false,
    commit = "7adc933dabcc7c86ae6b07aff7ee68eac398491f",
  },
}
