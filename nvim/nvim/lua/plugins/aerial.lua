-- Override AstroNvim's pinned aerial version.
--
-- AstroNvim v5's lazy_snapshot pins aerial to `^2.2`, but aerial 2.x uses the
-- old treesitter `iter_matches` semantics and the deprecated `node:start()`.
-- On Neovim 0.12 `iter_matches` returns a LIST of nodes per capture, so aerial
-- 2.x passes a table into `range_from_nodes` and crashes with:
--   "attempt to call method 'start' (a nil value)"
-- This was fixed in aerial 4.0.0 (which also drops nvim <0.12 support).
--
-- Unpin so lazy can install a 0.12-compatible release (>= 4.0).
return {
  {
    "stevearc/aerial.nvim",
    version = false, -- ignore AstroNvim's `^2.2` snapshot pin
    pin = false, -- allow `:Lazy update` to move it forward
  },
}
