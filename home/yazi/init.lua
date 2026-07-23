-- Yazi init.lua — plugin bootstrap + Doom-flavoured UI polish.
-- Plugins live in ~/.config/yazi/plugins, symlinked from pkgs.yaziPlugins by
-- home/yazi.nix. Colours below are the Doom Vibrant palette (see theme.toml).

-- ── Rounded full border (matches zellij rounded_corners / ghostty) ─────────
require("full-border"):setup({
	type = ui.Border.ROUNDED,
})

-- ── Git status flags in the file list ──────────────────────────────────────
-- Paired with the fetcher/preloader declared in yazi.toml.
require("git"):setup()

-- ── Git branch/ahead-behind segment in the header ──────────────────────────
require("githead"):setup({
	branch = { fg = "#c57bdb", bold = true }, -- magenta
	branch_prefix = "on ",
	commit = { fg = "#5cefff" }, -- cyan
	changes = { fg = "#fcce7b" }, -- yellow
	staged = { fg = "#7bc275" }, -- green
	unstaged = { fg = "#e69055" }, -- orange
	stashes = { fg = "#a991f1" }, -- violet
})

-- ── Relative vim motions with visible line numbers ─────────────────────────
require("relative-motions"):setup({
	show_numbers = "relative_absolute",
	show_motion = true,
	enter_mode = "first",
})

-- ── Bookmarks (harpoon-like quick jumps): m to add, ' to jump ──────────────
-- Plugin registers its own m/' keys; nothing else to wire.
require("bookmarks"):setup({
	last_directory = { enable = true, persist = true },
	persist = "all",
	notify = { enable = true, timeout = 1 },
})

-- ── Custom linemode: right-aligned size + short mtime ──────────────────────
-- Selected via `linemode = "size_and_mtime"` in yazi.toml.
function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	local timestr = time == 0 and "" or os.date("%b %d %H:%M", time)

	local size = self._file:size()
	local sizestr = size and ya.readable_size(size) or "-"

	return string.format("%s  %s", sizestr, timestr)
end
