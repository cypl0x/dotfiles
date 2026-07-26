-- oil.nvim — dired for nvim: edit the filesystem as a normal, editable buffer.
--   -          → open the parent directory (like `dired-jump`)
--   <leader>fd → open oil (Doom's file/dired entry)
return {
	{
		"stevearc/oil.nvim",
		lazy = false,
		opts = {
			view_options = { show_hidden = true },
			keymaps = {
				["<C-h>"] = false, -- keep LazyVim's window nav
				["q"] = "actions.close",
			},
		},
		keys = {
			{ "-", "<cmd>Oil<cr>", desc = "Open parent dir (oil)" },
			{ "<leader>fd", "<cmd>Oil<cr>", desc = "Dired (oil)" },
		},
	},
}
