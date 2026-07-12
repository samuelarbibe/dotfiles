---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    features = {
      large_buf = { size = 1024 * 500, lines = 20000 }, -- higher threshold before disabling features
      autopairs = true,
      cmp = true,
      diagnostics = { virtual_text = true, virtual_lines = false },
      highlighturl = true,
      notifications = true,
    },
    diagnostics = {
      virtual_text = true,
      underline = true,
      severity_sort = true,
    },
    mappings = {
      v = {
        ["<Leader>r"] = {
          function()
            -- yank selection into register
            vim.cmd('noautocmd normal! "vy')
            local text = vim.fn.getreg("v")
            -- escape for \V (very nomagic): only backslash and separator need escaping
            local escaped = vim.fn.escape(text, [[\/]])
            -- populate command line with substitution
            local left = vim.api.nvim_replace_termcodes("<Left>", true, false, true)
            vim.api.nvim_feedkeys(":%s/\\V" .. escaped .. "//gI" .. left .. left .. left, "n", false)
          end,
          desc = "Search & replace selection",
        },
      },
    },
    options = {
      opt = {
        relativenumber = true,
        number = true,
        spell = false,
        signcolumn = "yes",
        wrap = false,
        scrolloff = 15,
      },
    },
  },
}
