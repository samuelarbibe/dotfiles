-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here

-- Restart TS LSP when git HEAD changes (e.g. branch switch)
local last_git_head = nil

local function get_git_head()
  local result = vim.fn.system("git rev-parse HEAD 2>/dev/null")
  return vim.v.shell_error == 0 and vim.trim(result) or nil
end

-- Restart the TS LSP without relying on the :LspRestart user command, which
-- isn't guaranteed to be registered when this autocmd fires.
local function restart_ts_lsp()
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  for _, client in ipairs(get_clients({ name = "tsc" })) do
    local bufs = vim.lsp.get_buffers_by_client_id(client.id)
    client:stop()
    vim.defer_fn(function()
      for _, bufnr in ipairs(bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr }) end
      end
    end, 500)
  end
end

vim.api.nvim_create_autocmd("FocusGained", {
  callback = function()
    local head = get_git_head()
    if last_git_head and head and head ~= last_git_head then
      vim.cmd("checktime")
      restart_ts_lsp()
      vim.notify("Git ref changed - restarted TS LSP", vim.log.levels.INFO)
    end
    last_git_head = head
  end,
})

last_git_head = get_git_head()

-- Terminal buffers open in normal mode (act like regular buffers)
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.cmd.stopinsert()
  end,
})

vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.showbreak = "↪ "

require("resession").setup({
  extensions = {
    terminal = {},
  },
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local session_dir

    if vim.fn.argc(-1) == 0 then
      session_dir = vim.fn.getcwd()
    elseif vim.fn.argc(-1) == 1 then
      local arg = vim.fn.argv(0)
      if vim.fn.isdirectory(arg) == 1 then
        session_dir = vim.fn.fnamemodify(arg, ":p")
        vim.cmd.cd(session_dir)
      end
    end

    if session_dir then require("resession").load(session_dir, { dir = "dirsession", silence_errors = true }) end
  end,
  nested = true,
})
