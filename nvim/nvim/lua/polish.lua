-- This will run last in the setup process.
-- This is just pure lua so anything that doesn't
-- fit in the normal config locations above can go here


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
