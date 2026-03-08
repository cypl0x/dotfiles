local map = vim.keymap.set

local opts = {silent = true}

map({"n", "v"}, "<Space>", "<Nop>", opts)

map("i", "jk", "<Esc>", opts)

map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)
map("n", "<C-l>", "<C-w>l", opts)

map("t", "<C-h>", "<C-\\><C-n><C-w>h", opts)
map("t", "<C-j>", "<C-\\><C-n><C-w>j", opts)
map("t", "<C-k>", "<C-\\><C-n><C-w>k", opts)
map("t", "<C-l>", "<C-\\><C-n><C-w>l", opts)

map("n", "<S-h>", ":bprevious<CR>", opts)
map("n", "<S-l>", ":bnext<CR>", opts)

map("n", "n", "nzzzv", opts)
map("n", "N", "Nzzzv", opts)
map("n", "J", "mzJ`z", opts)
map("n", "Y", "y$", opts)

map("n", "<leader>wv", "<C-w>v", {desc = "Split vertical", silent = true})
map("n", "<leader>ws", "<C-w>s", {desc = "Split horizontal", silent = true})
map("n", "<leader>wc", "<C-w>c", {desc = "Close window", silent = true})
map("n", "<leader>wo", "<C-w>o", {desc = "Only window", silent = true})
map("n", "<leader>wh", "<C-w>h", {desc = "Move left", silent = true})
map("n", "<leader>wj", "<C-w>j", {desc = "Move down", silent = true})
map("n", "<leader>wk", "<C-w>k", {desc = "Move up", silent = true})
map("n", "<leader>wl", "<C-w>l", {desc = "Move right", silent = true})
map("n", "<leader>w=", "<C-w>=", {desc = "Equalize", silent = true})
map("n", "<leader>wm", function()
  vim.cmd("wincmd |")
  vim.cmd("wincmd _")
end, {desc = "Maximize", silent = true})

map("n", "<leader>bn", ":bnext<CR>", {desc = "Next buffer", silent = true})
map("n", "<leader>bp", ":bprevious<CR>", {desc = "Previous buffer", silent = true})
map("n", "<leader>bd", ":bdelete<CR>", {desc = "Delete buffer", silent = true})

map("n", "<leader>tn", function()
  vim.opt.number = not vim.opt.number:get()
end, {desc = "Toggle line numbers", silent = true})

map("n", "<leader>tr", function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, {desc = "Toggle relative numbers", silent = true})

map("n", "<leader>tw", function()
  vim.opt.wrap = not vim.opt.wrap:get()
end, {desc = "Toggle wrap", silent = true})

map("n", "<leader>ts", function()
  vim.opt.spell = not vim.opt.spell:get()
end, {desc = "Toggle spell", silent = true})

map("n", "<leader>ot", ":belowright split | terminal<CR>", {desc = "Open terminal", silent = true})
map("n", "<leader>ov", ":vsplit<CR>", {desc = "Open vertical split", silent = true})
map("n", "<leader>os", ":split<CR>", {desc = "Open horizontal split", silent = true})
