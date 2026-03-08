local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local yank_group = augroup("YankHighlight", {clear = true})
autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.highlight.on_yank({timeout = 150})
  end,
})

local resize_group = augroup("ResizeSplits", {clear = true})
autocmd("VimResized", {
  group = resize_group,
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})
