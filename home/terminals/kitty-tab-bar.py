# kitty custom tab bar — per-process Nerd Font icons in powerline tabs.
#
# Selected by `tab_bar_style custom` in home/kitty-thinkpad.nix, which makes
# kitty import this file as ~/.config/kitty/tab_bar.py and call draw_tab() once
# per tab per redraw.
#
# Why a Python module at all: kitty's declarative `tab_title_template` can
# interpolate values ({index}, {title}, {tab.active_exe}) but cannot branch on
# them, so "pick an icon for the running program" is not expressible there.
# This mirrors tab_icon_for_process() in home/wezterm/wezterm.lua.
#
# NOTE: kitty's tab bar has no hover state. TabBarData carries is_active,
# needs_attention and activity flags but nothing about the pointer, and the
# draw callback is not invoked on mouse motion — so the hover styling the
# wezterm config does (wezterm.lua's `hover` argument) has no counterpart here.

import os

from kitty.boss import get_boss
from kitty.tab_bar import DrawData, ExtraData, Screen, TabBarData, draw_tab_with_powerline

# Keep in sync with tab_icon_for_process() in home/wezterm/wezterm.lua.
ICONS = {
    "aria2c": "󰀂",
    "bash": "",
    "zsh": "",
    "fish": "",
    "nu": "󰟆",
    "ssh": "󰢹",
    "git": "",
    "gitui": "",
    "lazygit": "",
    "nvim": "",
    "vim": "",
    "tmux": "",
    "zellij": "󰖲",
    "htop": "󱄖",
    "btop": "󰍛",
    "bat": "󰭟",
    "less": "󰭟",
    "python": "󰌠",
    "python3": "󰌠",
    "node": "󰎙",
    "deno": "",
    "go": "",
    "cargo": "",
    "rustc": "",
    "docker": "󰡨",
    "tig": "",
    "rg": "󰑐",
    "top": "󰍛",
    "kitty": "",
    "emacs": "",
    "emacsclient": "",
    "yazi": "",
    "claude": "󰚩",
}
FALLBACK_ICON = ""


def _icon_for(tab_id: int) -> str:
    """Nerd Font glyph for whatever is in the foreground of this tab.

    Everything here is best-effort: a tab can be mid-teardown while the bar is
    redrawing, and a wrong icon must never take the tab bar (and with it the
    window) down, so any failure falls through to the generic glyph.
    """
    try:
        tab = get_boss().tab_for_id(tab_id)
        if tab is None:
            return FALLBACK_ICON
        window = tab.active_window
        if window is None:
            return FALLBACK_ICON
        # foreground_processes is the process group attached to the tty, i.e.
        # what the user is actually looking at, not the shell that spawned it.
        procs = window.child.foreground_processes
        if not procs:
            return FALLBACK_ICON
        cmdline = procs[-1].get("cmdline") or []
        if not cmdline:
            return FALLBACK_ICON
        name = os.path.basename(cmdline[0])
        # Strip the interpreter so `python3 foo.py` and wrappers like
        # `.nvim-wrapped` still resolve to a sensible name.
        name = name.lstrip(".").removesuffix("-wrapped")
        return ICONS.get(name, FALLBACK_ICON)
    except Exception:
        return FALLBACK_ICON


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    # TabBarData is a NamedTuple, so this hands the powerline renderer a tab
    # whose title already carries the icon — no need to reimplement separator
    # and truncation logic, which is edge-aware and gets the vertical (left/
    # right) tab bar right for free.
    icon = _icon_for(tab.tab_id)
    tab = tab._replace(title=f"{icon} {tab.title}")
    return draw_tab_with_powerline(
        draw_data, screen, tab, before, max_title_length, index, is_last, extra_data
    )
