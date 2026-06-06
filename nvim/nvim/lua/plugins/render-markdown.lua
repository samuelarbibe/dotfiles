---@type LazySpec
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    ft = { "markdown", "markdown.mdx" },
    opts = {
      code = {
        -- Disable render-markdown decorations on mermaid code blocks
        -- so snacks.image can render the chart inline instead
        disable = { "mermaid" },
      },
    },
  },
}
