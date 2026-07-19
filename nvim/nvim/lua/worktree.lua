-- Lightweight git worktree management.
-- Uses `vim.system` + `vim.ui.select`/`vim.ui.input`, so it works with whatever
-- picker AstroNvim has configured (snacks.picker here) without needing telescope.

local M = {}

--- Run a git command synchronously.
---@param args string[] git arguments (without the leading "git")
---@param cwd? string working directory (defaults to the current file's dir / cwd)
---@return string|nil stdout (trimmed) on success, nil on failure
---@return string|nil err stderr (trimmed) on failure
local function git(args, cwd)
  cwd = cwd or M.cwd()
  local cmd = { "git" }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then return nil, vim.trim(res.stderr or "git command failed") end
  return vim.trim(res.stdout or ""), nil
end

--- Best-effort working directory: current buffer's dir, else Neovim's cwd.
---@return string
function M.cwd()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname ~= "" and vim.fn.filereadable(bufname) == 1 then
    return vim.fn.fnamemodify(bufname, ":p:h")
  end
  return vim.fn.getcwd()
end

--- Absolute path of the current worktree's top level.
---@return string|nil
local function toplevel() return (git { "rev-parse", "--show-toplevel" }) end

--- Parse `git worktree list --porcelain` into structured entries.
---@return table[] worktrees list of { path, head?, branch?, bare?, detached? }
function M.list()
  local out, err = git { "worktree", "list", "--porcelain" }
  if not out then
    vim.notify("Not a git repository (" .. (err or "unknown error") .. ")", vim.log.levels.WARN)
    return {}
  end
  local worktrees, cur = {}, nil
  for _, line in ipairs(vim.split(out, "\n")) do
    if line:match "^worktree " then
      cur = { path = line:sub(#"worktree " + 1) }
      table.insert(worktrees, cur)
    elseif cur and line:match "^HEAD " then
      cur.head = line:sub(#"HEAD " + 1):sub(1, 8)
    elseif cur and line:match "^branch " then
      cur.branch = (line:sub(#"branch " + 1):gsub("^refs/heads/", ""))
    elseif cur and line:match "^bare" then
      cur.bare = true
    elseif cur and line:match "^detached" then
      cur.detached = true
    end
  end
  return worktrees
end

--- A short human label for a worktree entry.
---@param wt table
---@return string
local function label(wt)
  if wt.bare then return "(bare)" end
  if wt.branch then return wt.branch end
  if wt.detached then return "(detached " .. (wt.head or "?") .. ")" end
  return wt.head or "?"
end

--- Change to a worktree and, when possible, reopen the equivalent file.
---@param wt table worktree entry (needs `.path`)
---@param rel? string path of the current file relative to the old worktree root
---@param in_tab? boolean open in a new tab (tab-local cd) instead of switching globally
function M.goto_worktree(wt, rel, in_tab)
  if in_tab then
    vim.cmd.tabnew()
    vim.cmd.tcd(vim.fn.fnameescape(wt.path))
  else
    vim.cmd.cd(vim.fn.fnameescape(wt.path))
  end

  local opened = false
  if rel and rel ~= "" then
    local target = wt.path .. "/" .. rel
    if vim.fn.filereadable(target) == 1 then
      vim.cmd.edit(vim.fn.fnameescape(target))
      opened = true
    end
  end
  if in_tab and not opened then vim.cmd.enew() end

  vim.notify("Worktree: " .. label(wt) .. "  →  " .. wt.path, vim.log.levels.INFO)
end

--- Pick a worktree, then switch to it (or open it in a new tab).
---@param in_tab? boolean
function M.switch(in_tab)
  local worktrees = M.list()
  if #worktrees == 0 then return end

  local root = toplevel()
  local file = vim.api.nvim_buf_get_name(0)
  local rel
  if root and file ~= "" and file:sub(1, #root + 1) == root .. "/" then rel = file:sub(#root + 2) end

  vim.ui.select(worktrees, {
    prompt = in_tab and "Open worktree in new tab" or "Switch worktree",
    format_item = function(wt) return string.format("%-28s %s", label(wt), wt.path) end,
  }, function(choice)
    if choice then M.goto_worktree(choice, rel, in_tab) end
  end)
end

--- Create a new worktree (prompts for branch + path) and switch to it.
function M.create()
  local root = toplevel()
  if not root then return end

  vim.ui.input({ prompt = "New worktree branch: " }, function(branch)
    if not branch or branch == "" then return end
    local parent = vim.fn.fnamemodify(root, ":h")
    local repo = vim.fn.fnamemodify(root, ":t")
    local default = string.format("%s/%s-%s", parent, repo, (branch:gsub("[/ ]", "-")))

    vim.ui.input({ prompt = "Worktree path: ", default = default, completion = "dir" }, function(path)
      if not path or path == "" then return end
      path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")

      -- Try to create a new branch; if it already exists, check it out instead.
      local out, err = git { "worktree", "add", "-b", branch, path }
      if not out then out, err = git { "worktree", "add", path, branch } end
      if not out then
        vim.notify("Failed to create worktree: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end
      M.goto_worktree { path = path, branch = branch }
    end)
  end)
end

--- Pick a worktree (excluding the current one) and remove it.
function M.remove()
  local root = toplevel()
  local worktrees = vim.tbl_filter(
    function(wt) return not wt.bare and wt.path ~= root end,
    M.list()
  )
  if #worktrees == 0 then
    vim.notify("No other worktrees to remove", vim.log.levels.WARN)
    return
  end

  vim.ui.select(worktrees, {
    prompt = "Remove worktree",
    format_item = function(wt) return string.format("%-28s %s", label(wt), wt.path) end,
  }, function(choice)
    if not choice then return end
    vim.ui.select({ "No", "Yes" }, { prompt = "Remove " .. choice.path .. "?" }, function(confirm)
      if confirm ~= "Yes" then return end
      local out, err = git { "worktree", "remove", choice.path }
      if out then
        vim.notify("Removed worktree: " .. choice.path, vim.log.levels.INFO)
        return
      end
      vim.ui.select({ "No", "Yes (force)" }, {
        prompt = "Remove failed (" .. (err or "?") .. "). Force remove?",
      }, function(force)
        if force ~= "Yes (force)" then return end
        local o2, e2 = git { "worktree", "remove", "--force", choice.path }
        if o2 then
          vim.notify("Force-removed worktree: " .. choice.path, vim.log.levels.INFO)
        else
          vim.notify("Force remove failed: " .. (e2 or "?"), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
