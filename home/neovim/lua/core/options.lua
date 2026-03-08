local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = " "

opt.termguicolors = true
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.wrap = false
opt.linebreak = true
opt.scrolloff = 6
opt.sidescrolloff = 8

opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

opt.splitbelow = true
opt.splitright = true

opt.hidden = true
opt.updatetime = 200
opt.timeoutlen = 400
opt.signcolumn = "yes"
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.mouse = "a"
opt.completeopt = {"menu", "menuone", "noselect"}

vim.cmd.colorscheme("doom-vibrant")
