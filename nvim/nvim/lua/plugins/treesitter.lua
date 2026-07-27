-- Migrate nvim-treesitter (and textobjects) to the `main` branch rewrite.
--
-- AstroNvim's core spec targets the archived `master` branch (v0.10.0), which
-- is incompatible with Neovim 0.11+ : `iter_matches` now returns a list of
-- nodes per capture, and master's query.lua feeds that list straight into
-- `TSRange.from_nodes`, crashing on `make-range!` textobjects such as
-- `@parameter.outer` (e.g. `daa` in TypeScript).
--
-- The `main` branch is a full rewrite: no lazy-loading, and nothing is enabled
-- automatically, so we wire up installation, highlight, indentation, and the
-- textobject keymaps ourselves.

local ensure_installed = {
  "bash", "c", "comment", "css", "diff", "dockerfile", "gitcommit",
  "go", "gomod", "gosum", "gowork", "html", "javascript", "json",
  "lua", "luadoc", "markdown", "markdown_inline", "python", "query",
  "regex", "tsx", "typescript", "vim", "vimdoc", "yaml",
}

-- `select` module: capture group per key (mirrors AstroNvim's master defaults).
local select_keymaps = {
  ["ak"] = "@block.outer",
  ["ik"] = "@block.inner",
  ["ac"] = "@class.outer",
  ["ic"] = "@class.inner",
  ["a?"] = "@conditional.outer",
  ["i?"] = "@conditional.inner",
  ["af"] = "@function.outer",
  ["if"] = "@function.inner",
  ["ao"] = "@loop.outer",
  ["io"] = "@loop.inner",
  ["aa"] = "@parameter.outer",
  ["ia"] = "@parameter.inner",
}

-- `move` module: { key, query } per direction.
local move_keymaps = {
  goto_next_start = { { "]k", "@block.outer" }, { "]f", "@function.outer" }, { "]a", "@parameter.inner" } },
  goto_next_end = { { "]K", "@block.outer" }, { "]F", "@function.outer" }, { "]A", "@parameter.inner" } },
  goto_previous_start = { { "[k", "@block.outer" }, { "[f", "@function.outer" }, { "[a", "@parameter.inner" } },
  goto_previous_end = { { "[K", "@block.outer" }, { "[F", "@function.outer" }, { "[A", "@parameter.inner" } },
}

-- `swap` module: { key, query } per direction.
local swap_keymaps = {
  swap_next = { { ">K", "@block.outer" }, { ">F", "@function.outer" }, { ">A", "@parameter.inner" } },
  swap_previous = { { "<K", "@block.outer" }, { "<F", "@function.outer" }, { "<A", "@parameter.inner" } },
}

local function enable_treesitter(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not ok or not parser then return end
  pcall(vim.treesitter.start, buf)
  vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
end

---@type LazySpec
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false, -- main branch does not support lazy-loading
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()

      -- Async, no-op if parsers already present.
      require("nvim-treesitter").install(ensure_installed)

      vim.api.nvim_create_autocmd("FileType", {
        desc = "Enable treesitter highlight + indent",
        callback = function(args) enable_treesitter(args.buf) end,
      })

      -- config runs eagerly at startup, possibly after the first FileType has
      -- already fired, so enable any buffers that are already loaded.
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then enable_treesitter(buf) end
      end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    lazy = false,
    config = function()
      require("nvim-treesitter-textobjects").setup {
        select = { lookahead = true },
        move = { set_jumps = true },
      }

      local select = require "nvim-treesitter-textobjects.select"
      for lhs, query in pairs(select_keymaps) do
        vim.keymap.set({ "x", "o" }, lhs, function() select.select_textobject(query, "textobjects") end,
          { desc = "Select " .. query })
      end

      local move = require "nvim-treesitter-textobjects.move"
      for func, maps in pairs(move_keymaps) do
        for _, map in ipairs(maps) do
          local lhs, query = map[1], map[2]
          vim.keymap.set({ "n", "x", "o" }, lhs, function() move[func](query, "textobjects") end,
            { desc = func .. " " .. query })
        end
      end

      local swap = require "nvim-treesitter-textobjects.swap"
      for func, maps in pairs(swap_keymaps) do
        for _, map in ipairs(maps) do
          local lhs, query = map[1], map[2]
          vim.keymap.set("n", lhs, function() swap[func](query) end, { desc = func .. " " .. query })
        end
      end
    end,
  },
}
