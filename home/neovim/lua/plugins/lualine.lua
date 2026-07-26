-- Dress LazyVim's lualine in the Doom Vibrant palette.
return {
	{
		"nvim-lualine/lualine.nvim",
		opts = function(_, opts)
			opts.options = opts.options or {}
			opts.options.theme = require("config.theme").lualine
			opts.options.section_separators = ""
			opts.options.component_separators = "|"
		end,
	},
}
