-- GitLab MR review inside Neovim (akin to the VS Code GitLab Workflow extension).
--
-- <Leader>gm (or `glc` once loaded) searches open MRs and checks out the branch
-- locally, so the LSP keeps working on the real files. Review the diff via
-- diffview, comment inline with `c` (or `s` for a suggestion) in the reviewer,
-- manage discussion threads, and approve/merge.
--
-- Auth reuses the existing GITLAB_URL + GITLAB_TOKEN env vars (code.pan.run),
-- so no extra token config is needed. Requires Go (builds a small server on
-- install). Launch nvim from a terminal so the env vars are inherited.

---@type LazySpec
return {
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
    "dlyongemallo/diffview.nvim", -- maintained fork recommended by gitlab.nvim
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<Leader>gm", function() require("gitlab").choose_merge_request() end, desc = "󰊤 GitLab: choose MR" },
    { "<Leader>gM", function() require("gitlab").review() end, desc = "󰊤 GitLab: review current branch" },
  },
  config = function()
    -- Use a locally patched server binary. Upstream's server runs `git fetch` on
    -- init and treats a non-zero exit as fatal; on this case-insensitive filesystem
    -- the cloud-apps monorepo has case-conflicting remote refs that make `git fetch`
    -- exit non-zero (while still fetching what we need), which killed the server.
    -- The patched build makes that fetch best-effort. Rebuild via:
    --   ~/.local/share/nvim/gitlab.nvim-src  (patched clone)
    --   cd cmd && go build -buildvcs=false -o <binary> .
    local binary = vim.fn.stdpath("data") .. "/gitlab.nvim/bin/server-patched"
    local opts = {}
    if vim.uv.fs_stat(binary) then
      opts.server = { binary = binary }
    end
    require("gitlab").setup(opts)
  end,
}
