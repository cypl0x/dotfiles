-- org-mode: syntax highlighting (incl. injected #+begin_src blocks via the
-- `org` treesitter grammar) and Doom-style structure editing.
--   <localleader>' (Space ') → edit the src block in a dedicated buffer
--                              (Doom's SPC m ' / org-edit-special)
--   <localleader>oa / oc     → agenda / capture
return {
	{
		"nvim-orgmode/orgmode",
		ft = "org",
		event = "VeryLazy",
		opts = {
			org_agenda_files = { "~/Nextcloud/**/*.org" },
			org_default_notes_file = "~/Nextcloud/notes.org",
			highlight_latex_and_related = "entities",
		},
	},
}
