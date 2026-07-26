-- Doom-flavoured additions on top of LazyVim's defaults. LazyVim already ships
-- <C-hjkl> window nav (incl. terminal), <S-h>/<S-l> buffer cycling, <leader>bd,
-- <leader>| / <leader>- splits and the <leader>u* UI toggles, so none of that is
-- repeated here.
local map = vim.keymap.set
local opts = { silent = true }

map("i", "jk", "<Esc>", opts) -- evil-escape muscle memory

map("n", "J", "mzJ`z", opts) -- keep the cursor put when joining
map("n", "Y", "y$", opts)

-- SPC w — windows (Doom: SPC w)
map("n", "<leader>wv", "<C-w>v", { desc = "Split vertical", silent = true })
map("n", "<leader>ws", "<C-w>s", { desc = "Split horizontal", silent = true })
map("n", "<leader>wc", "<C-w>c", { desc = "Close window", silent = true })
map("n", "<leader>wo", "<C-w>o", { desc = "Only window", silent = true })
map("n", "<leader>wh", "<C-w>h", { desc = "Move left", silent = true })
map("n", "<leader>wj", "<C-w>j", { desc = "Move down", silent = true })
map("n", "<leader>wk", "<C-w>k", { desc = "Move up", silent = true })
map("n", "<leader>wl", "<C-w>l", { desc = "Move right", silent = true })
map("n", "<leader>w=", "<C-w>=", { desc = "Equalize", silent = true })
map("n", "<leader>wm", function()
	vim.cmd("wincmd |")
	vim.cmd("wincmd _")
end, { desc = "Maximize", silent = true })

-- SPC b — buffers
map("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "Next buffer", silent = true })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Previous buffer", silent = true })

-- SPC p — projects (Doom: SPC p). Backed by snacks.picker, LazyVim's default.
map("n", "<leader>pp", function()
	Snacks.picker.projects()
end, { desc = "Switch project", silent = true })
map("n", "<leader>pf", function()
	Snacks.picker.files()
end, { desc = "Find file in project", silent = true })
map("n", "<leader>pg", function()
	Snacks.picker.grep()
end, { desc = "Grep project", silent = true })
map("n", "<leader>pb", function()
	Snacks.picker.buffers()
end, { desc = "Project buffers", silent = true })
map("n", "<leader>pr", function()
	Snacks.picker.recent()
end, { desc = "Recent files", silent = true })

-- SPC t — toggles. Note: LazyVim's `test` extra also claims <leader>t; enable it
-- and these move.
map("n", "<leader>tn", function()
	vim.opt.number = not vim.opt.number:get()
end, { desc = "Toggle line numbers", silent = true })
map("n", "<leader>tr", function()
	vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = "Toggle relative numbers", silent = true })
map("n", "<leader>tw", function()
	vim.opt.wrap = not vim.opt.wrap:get()
end, { desc = "Toggle wrap", silent = true })
map("n", "<leader>ts", function()
	vim.opt.spell = not vim.opt.spell:get()
end, { desc = "Toggle spell", silent = true })

-- SPC o — open
map("n", "<leader>ot", "<cmd>belowright split | terminal<cr>", { desc = "Open terminal", silent = true })
map("n", "<leader>ov", "<cmd>vsplit<cr>", { desc = "Open vertical split", silent = true })
map("n", "<leader>os", "<cmd>split<cr>", { desc = "Open horizontal split", silent = true })
