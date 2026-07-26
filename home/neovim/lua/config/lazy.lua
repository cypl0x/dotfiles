-- lazy.nvim itself is installed by Nix (programs.neovim.plugins), so there is
-- no bootstrap clone here. Everything in the LazyVim spec is still managed by
-- lazy.nvim at runtime under stdpath("data")/lazy.
--
-- Both of lazy.nvim's state files are pushed into stdpath("data"): the config
-- dir is a read-only Nix store symlink, so the lockfile and the LazyExtras
-- state cannot live next to the Lua sources like they do upstream.
vim.g.lazyvim_json = vim.fn.stdpath("data") .. "/lazyvim.json"

-- Leader must be set before lazy.nvim parses the spec, otherwise plugin keymaps
-- get bound to the old leader.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("lazy").setup({
	spec = {
		{ "LazyVim/LazyVim", import = "lazyvim.plugins" },
		{ import = "plugins" },
	},
	defaults = { lazy = false, version = false },
	lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
	install = { colorscheme = { "doom-vibrant", "habamax" } },
	checker = { enabled = true, notify = false },
	change_detection = { notify = false },
	performance = {
		rtp = {
			disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
		},
	},
})
