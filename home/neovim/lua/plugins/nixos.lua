-- NixOS adjustments.
--
-- mason downloads prebuilt binaries that expect an FHS layout, so they cannot
-- run here. Every language server, formatter and CLI tool comes from
-- programs.neovim.extraPackages in home/neovim.nix instead. With mason absent,
-- LazyVim falls back to plain vim.lsp.config + vim.lsp.enable for whatever is
-- listed in `servers`.
local servers = {}
for server, bin in pairs({
	bashls = "bash-language-server",
	lua_ls = "lua-language-server",
	marksman = "marksman",
	nil_ls = "nil",
	rust_analyzer = "rust-analyzer",
	ts_ls = "typescript-language-server",
}) do
	-- Only enable a server we can actually spawn, so binaries that only exist
	-- inside a project devShell (rust-analyzer, tsserver) stay optional.
	if vim.fn.executable(bin) == 1 then
		servers[server] = {}
	end
end

if servers.lua_ls then
	servers.lua_ls = { settings = { Lua = { diagnostics = { globals = { "vim" } } } } }
end

return {
	{ "mason-org/mason.nvim", enabled = false },
	{ "mason-org/mason-lspconfig.nvim", enabled = false },

	{
		"neovim/nvim-lspconfig",
		opts = { servers = servers },
	},

	-- blink.cmp's fuzzy matcher ships as a prebuilt Rust binary (or wants cargo
	-- to build one). The Lua implementation avoids both.
	{
		"saghen/blink.cmp",
		opts = { fuzzy = { implementation = "lua" } },
	},
}
