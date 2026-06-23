-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

vim.pack.add {
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '\\', '<Cmd>Neotree reveal<CR>', { desc = 'NeoTree reveal', silent = true })

require('neo-tree').setup {
  window = {
    position = 'right',
  },
  filesystem = {
    window = {
      mappings = {
        ['\\'] = 'close_window',
        -- hjkl navigation: j/k move the cursor (vim defaults),
        --  l opens/expands a directory or opens a file,
        --  h collapses the current directory (or jumps to its parent).
        ['l'] = 'open',
        ['<CR>'] = 'open',
        ['h'] = 'close_node',
      },
    },
  },
}
