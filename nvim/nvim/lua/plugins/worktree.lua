-- Git worktree keymaps, wired into AstroNvim's leader (git group).
-- The implementation lives in `lua/worktree.lua`.

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    mappings = {
      n = {
        ["<Leader>gw"] = { desc = "󰙅 Worktrees" },
        ["<Leader>gws"] = { function() require("worktree").switch() end, desc = "Switch worktree" },
        ["<Leader>gwt"] = { function() require("worktree").switch(true) end, desc = "Open worktree in new tab" },
        ["<Leader>gwc"] = { function() require("worktree").create() end, desc = "Create worktree" },
        ["<Leader>gwd"] = { function() require("worktree").remove() end, desc = "Delete worktree" },
      },
    },
  },
}
