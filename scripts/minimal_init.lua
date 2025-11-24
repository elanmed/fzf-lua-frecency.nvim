-- https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md#file-organization
vim.cmd [[let &rtp.=','.getcwd()]]

if #vim.api.nvim_list_uis() == 0 then
  vim.cmd "set rtp+=deps/mini.nvim"
  vim.cmd "set rtp+=deps/fzf-lua"
  require "mini.test".setup()
end
