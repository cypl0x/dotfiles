local M = {}

M.palette = {
  bg = "#242730",
  bg_alt = "#2a2e38",
  bg_highlight = "#3d4451",
  bg_visual = "#303540",
  bg_cursorline = "#2a2e38",
  fg = "#bbc2cf",
  fg_alt = "#9ca0a4",
  comment = "#62686E",
  blue = "#51afef",
  cyan = "#5cEfFF",
  green = "#7bc275",
  yellow = "#FCCE7B",
  orange = "#e69055",
  red = "#ff665c",
  magenta = "#C57BDB",
  violet = "#a991f1",
  border = "#484854",
}

M.lualine = {
  normal = {
    a = {fg = M.palette.bg, bg = M.palette.blue, gui = "bold"},
    b = {fg = M.palette.fg, bg = M.palette.bg_alt},
    c = {fg = M.palette.fg_alt, bg = M.palette.bg},
  },
  insert = {
    a = {fg = M.palette.bg, bg = M.palette.green, gui = "bold"},
    b = {fg = M.palette.fg, bg = M.palette.bg_alt},
  },
  visual = {
    a = {fg = M.palette.bg, bg = M.palette.magenta, gui = "bold"},
    b = {fg = M.palette.fg, bg = M.palette.bg_alt},
  },
  replace = {
    a = {fg = M.palette.bg, bg = M.palette.orange, gui = "bold"},
    b = {fg = M.palette.fg, bg = M.palette.bg_alt},
  },
  command = {
    a = {fg = M.palette.bg, bg = M.palette.cyan, gui = "bold"},
    b = {fg = M.palette.fg, bg = M.palette.bg_alt},
  },
  inactive = {
    a = {fg = M.palette.comment, bg = M.palette.bg_alt},
    b = {fg = M.palette.comment, bg = M.palette.bg_alt},
    c = {fg = M.palette.comment, bg = M.palette.bg},
  },
}

return M
