local wezterm = require "wezterm"

local config = wezterm.config_builder()
local act = wezterm.action

config.automatically_reload_config = true

config.color_schemes = {
  ["Doom Vibrant"] = {
    foreground = "#bbc2cf",
    background = "#242730",
    cursor_bg = "#51afef",
    cursor_fg = "#242730",
    cursor_border = "#51afef",
    selection_bg = "#3d4451",
    selection_fg = "#bbc2cf",
    ansi = {
      "#1c1f24",
      "#ff665c",
      "#7bc275",
      "#FCCE7B",
      "#51afef",
      "#C57BDB",
      "#5cEfFF",
      "#bbc2cf",
    },
    brights = {
      "#484854",
      "#ff665c",
      "#7bc275",
      "#FCCE7B",
      "#51afef",
      "#C57BDB",
      "#5cEfFF",
      "#DFDFDF",
    },
    tab_bar = {
      background = "#1c1f24",
      active_tab = {
        bg_color = "#242730",
        fg_color = "#bbc2cf",
        intensity = "Bold",
      },
      inactive_tab = {
        bg_color = "#1c1f24",
        fg_color = "#62686E",
      },
      inactive_tab_hover = {
        bg_color = "#2a2e38",
        fg_color = "#bbc2cf",
      },
      new_tab = {
        bg_color = "#1c1f24",
        fg_color = "#62686E",
      },
      new_tab_hover = {
        bg_color = "#2a2e38",
        fg_color = "#bbc2cf",
        intensity = "Bold",
      },
    },
  },
}

config.color_scheme = "Doom Vibrant"

config.window_close_confirmation = "NeverPrompt"
config.adjust_window_size_when_changing_font_size = false
config.use_resize_increments = true
config.enable_scroll_bar = false
config.check_for_updates = false
config.audible_bell = "Disabled"
config.window_padding = { left = 6, right = 6, top = 6, bottom = 6 }
config.scrollback_lines = 10000
config.max_fps = 120

config.font = wezterm.font_with_fallback({
  "Cascadia Code NF",
  "JetBrains Mono",
  "FiraCode Nerd Font",
  "Iosevka",
  "Noto Sans Mono",
  "DejaVu Sans Mono",
})
config.font_size = 12.0
config.line_height = 1.08

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.show_new_tab_button_in_tab_bar = false
config.tab_bar_at_bottom = true
config.tab_max_width = 28

local function basename(path)
  return string.gsub(path, "(.*[/\\])(.*)", "%2")
end

local function tab_icon_for_process(pane)
  local proc = pane.foreground_process_name
  if proc == nil or proc == "" then
    return ""
  end

  local name = basename(proc)
  local map = {
    ["aria2c"] = "󰀂",
    ["bash"] = "",
    ["zsh"] = "",
    ["fish"] = "",
    ["nu"] = "󰟆",
    ["ssh"] = "󰢹",
    ["git"] = "",
    ["gitui"] = "",
    ["lazygit"] = "",
    ["nvim"] = "",
    ["vim"] = "",
    ["tmux"] = "",
    ["zellij"] = "󰖲",
    ["htop"] = "󱄖",
    ["btop"] = "󰍛",
    ["bat"] = "󰭟",
    ["less"] = "󰭟",
    ["python"] = "󰌠",
    ["node"] = "󰎙",
    ["deno"] = "",
    ["go"] = "",
    ["cargo"] = "",
    ["rustc"] = "",
    ["docker"] = "󰡨",
    ["tig"] = "",
    ["rg"] = "󰑐",
    ["top"] = "󰍛",
    ["wezterm"] = "",
  }

  return map[name] or ""
end

wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
  local is_active = tab.is_active
  local title = tab.active_pane.title
  local index = tab.tab_index + 1
  local icon = tab_icon_for_process(tab.active_pane)

  local bg = is_active and "#51afef" or "#242730"
  local fg = is_active and "#1c1f24" or "#62686E"
  if hover and not is_active then
    bg = "#2a2e38"
    fg = "#bbc2cf"
  end

  local label = string.format(" %s %d:%s ", icon, index, title)
  if #label > max_width then
    label = wezterm.truncate_right(label, max_width)
  end

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Attribute = { Intensity = "Bold" } },
    { Text = label },
  }
end)

wezterm.on("update-status", function(window, pane)
  local date = wezterm.strftime("%Y-%m-%d %H:%M")
  local workspace = window:active_workspace() or "default"
  local host = wezterm.hostname()

  window:set_left_status(wezterm.format({
    { Background = { Color = "#51afef" } },
    { Foreground = { Color = "#1c1f24" } },
    { Attribute = { Intensity = "Bold" } },
    { Text = " " .. workspace .. " " },
    { Background = { Color = "#242730" } },
    { Foreground = { Color = "#51afef" } },
    { Text = " " .. host .. " " },
  }))

  window:set_right_status(wezterm.format({
    { Background = { Color = "#242730" } },
    { Foreground = { Color = "#62686E" } },
    { Text = " " .. date .. " " },
  }))
end)

config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
  { key = "r", mods = "LEADER", action = act.ReloadConfiguration },
  { key = " ", mods = "LEADER", action = act.SendKey({ key = "Space", mods = "CTRL" }) },

  { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
  { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
  { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
  { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
  { key = "H", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "J", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 3 }) },
  { key = "K", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 3 }) },
  { key = "L", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

  { key = "w", mods = "LEADER", action = act.ActivateKeyTable({ name = "window", one_shot = true, timeout_milliseconds = 1000 }) },
  { key = "b", mods = "LEADER", action = act.ActivateKeyTable({ name = "buffer", one_shot = true, timeout_milliseconds = 1000 }) },
  { key = "p", mods = "LEADER", action = act.ActivateKeyTable({ name = "project", one_shot = true, timeout_milliseconds = 1000 }) },
  { key = "t", mods = "LEADER", action = act.ActivateKeyTable({ name = "toggle", one_shot = true, timeout_milliseconds = 1000 }) },
  { key = "o", mods = "LEADER", action = act.ActivateKeyTable({ name = "open", one_shot = true, timeout_milliseconds = 1000 }) },

  { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
  { key = "f", mods = "LEADER", action = act.QuickSelect },
  { key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") },
  { key = "u", mods = "LEADER", action = act.ClearScrollback("ScrollbackAndViewport") },
}

config.key_tables = {
  window = {
    { key = "w", action = act.PaneSelect },
    { key = "v", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "s", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "c", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "z", action = act.TogglePaneZoomState },
    { key = "=", action = act.AdjustPaneSize({ "Left", 0 }) },
  },
  buffer = {
    { key = "n", action = act.ActivateTabRelative(1) },
    { key = "p", action = act.ActivateTabRelative(-1) },
    { key = "b", action = act.ShowTabNavigator },
    { key = "k", action = act.CloseCurrentTab({ confirm = true }) },
    { key = "c", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "1", action = act.ActivateTab(0) },
    { key = "2", action = act.ActivateTab(1) },
    { key = "3", action = act.ActivateTab(2) },
    { key = "4", action = act.ActivateTab(3) },
    { key = "5", action = act.ActivateTab(4) },
    { key = "6", action = act.ActivateTab(5) },
    { key = "7", action = act.ActivateTab(6) },
    { key = "8", action = act.ActivateTab(7) },
    { key = "9", action = act.ActivateTab(8) },
  },
  project = {
    { key = "s", action = act.ShowLauncherArgs({ flags = "FUZZY|TABS|WORKSPACES" }) },
    { key = "w", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
    {
      key = "n",
      action = act.PromptInputLine({
        description = "New workspace name",
        action = wezterm.action_callback(function(window, pane, line)
          if line and line ~= "" then
            window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
          end
        end),
      }),
    },
  },
  toggle = {
    { key = "f", action = act.ToggleFullScreen },
    { key = "z", action = act.TogglePaneZoomState },
    { key = "d", action = act.ShowDebugOverlay },
  },
  open = {
    { key = "l", action = act.ShowLauncherArgs({ flags = "FUZZY|TABS|WORKSPACES|COMMANDS" }) },
    { key = "t", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "s", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "v", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  },
}

config.quick_select_patterns = {
  "[0-9a-fA-F]{7,40}",
  "https?://[^\\s)]+",
  "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
  "\\b\\d+\\b",
}

config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.85,
}

config.disable_default_mouse_bindings = true
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = act.SelectTextAtMouseCursor("Cell"),
  },
  {
    event = { Drag = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = act.ExtendSelectionToMouseCursor("Cell"),
  },
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = act.CompleteSelection("PrimarySelection"),
  },
  {
    event = { Down = { streak = 2, button = "Left" } },
    mods = "NONE",
    action = act.SelectTextAtMouseCursor("Word"),
  },
  {
    event = { Drag = { streak = 2, button = "Left" } },
    mods = "NONE",
    action = act.ExtendSelectionToMouseCursor("Word"),
  },
  {
    event = { Down = { streak = 3, button = "Left" } },
    mods = "NONE",
    action = act.SelectTextAtMouseCursor("Line"),
  },
  {
    event = { Drag = { streak = 3, button = "Left" } },
    mods = "NONE",
    action = act.ExtendSelectionToMouseCursor("Line"),
  },
  {
    event = { Down = { streak = 1, button = "Right" } },
    mods = "NONE",
    action = act.ShowLauncherArgs({ flags = "FUZZY|TABS|WORKSPACES|COMMANDS" }),
  },
}

return config
