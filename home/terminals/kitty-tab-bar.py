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
    "neovim": "",
    "vim": "",
    "vi": "",
    "hx": "",
    "helix": "",
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
    "k9s": "󱃾",
    "lazydocker": "󰡨",
    "man": "",
    "journalctl": "",
    "systemctl": "",
    "nix": "",
    "nixos-rebuild": "",
    "make": "",
    "fzf": "",
}
FALLBACK_ICON = ""

# Processes that are never what the tab is "about" — they wrap the interesting
# one, so a tab running `sudo nvim` should show the nvim icon, not a shell.
TRANSPARENT = frozenset({"sudo", "doas", "env", "sh", "dash", "nix-shell", "script"})


def _normalize(argv0: str) -> str:
    """Reduce an argv[0] to a plain program name.

    Nix stores real binaries under paths like
    /nix/store/<hash>-neovim-unwrapped-0.12.4/bin/nvim and installs wrappers
    named .nvim-wrapped, so both the directory and the decorations have to go
    before the name can be looked up.
    """
    name = os.path.basename(argv0)
    if name.startswith("."):
        name = name[1:]
    return name.removesuffix("-wrapped")


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
        # what the user is looking at rather than the shell that spawned it.
        # It can hold several entries (a pipeline, or sudo wrapping an editor),
        # and the interesting one is not reliably first or last — so prefer any
        # process we have an icon for, scanning newest first.
        names = []
        for proc in reversed(window.child.foreground_processes):
            cmdline = proc.get("cmdline") or []
            if not cmdline:
                continue
            name = _normalize(cmdline[0])
            if name in TRANSPARENT and len(cmdline) > 1:
                # `sudo nvim foo` — the argument is the real program.
                name = _normalize(cmdline[1])
            if name in ICONS:
                return ICONS[name]
            names.append(name)
        # Nothing recognised: a plain shell prompt is the common case.
        return ICONS.get(names[0], FALLBACK_ICON) if names else FALLBACK_ICON
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
