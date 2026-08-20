-- tpope-like mappings (see :h MiniSurround-vim-surround-config) so we never
-- touch built-in |s|. Normal: ysiw) add ), ds) delete, cs)] change.
-- Visual: select text, then S) to surround (replaces default visual |S|).
-- lazy=false: VeryLazy meant |sa| often was not set up yet, so |s| acted as substitute.

---@type LazySpec
return {
  {
    "echasnovski/mini.surround",
    version = false,
    lazy = false,
    opts = {
      mappings = {
        add = "ys",
        delete = "ds",
        find = "",
        find_left = "",
        highlight = "",
        replace = "cs",
        suffix_last = "",
        suffix_next = "",
      },
      search_method = "cover_or_next",
    },
    config = function(_, opts)
      require("mini.surround").setup(opts)
      pcall(vim.keymap.del, "x", "ys")
      vim.keymap.set("x", "S", "<Cmd>lua MiniSurround.add('visual')<CR>", { silent = true })
      vim.keymap.set("n", "yss", "ys_", { remap = true })
    end,
  },
}
