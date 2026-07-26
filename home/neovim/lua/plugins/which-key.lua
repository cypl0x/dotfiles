-- Name the Doom-style leader groups added in config/keymaps.lua. LazyVim already
-- registers b/c/f/g/q/s/u/w and friends.
return {
	{
		"folke/which-key.nvim",
		opts = {
			preset = "modern",
			delay = 300,
			spec = {
				{ "<leader>o", group = "open" },
				{ "<leader>p", group = "project" },
				{ "<leader>t", group = "toggle" },
			},
		},
	},
}
