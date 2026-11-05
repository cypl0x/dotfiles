-- Hyprland Lua config — 1:1 translation of hyprland.conf (hyprlang) for
-- Hyprland >= 0.55 (written against 0.56.1). NOT wired into home-manager yet:
-- ~/.config/hypr/hyprland.lua is loaded INSTEAD of hyprland.conf when present.
--
-- API ground truth: share/hypr/hyprland.lua (official example) and
-- share/hypr/stubs/hl.meta.lua of hyprland-0.56.1, plus the wiki
-- (configuring/core/{dispatchers,binds/*,rules/*,animations,autostart}.md).
--
-- Mapping notes — things that are not a literal 1:1 keyword swap:
--  * exec-once  -> hl.exec_cmd() inside hl.on("hyprland.start", ...). Runs once
--    at compositor start, not on reload — same as exec-once (wiki: autostart).
--  * exec-once rule prefix "[workspace special:term silent]" -> exec_cmd's
--    second argument, a table of window-rule effects (wiki: dispatchers,
--    "Executing with rules").
--  * $variables -> Lua locals. hyprlang expanded them textually at parse time;
--    string concatenation is equivalent. Shell syntax inside them ($HOME,
--    $(date ...), ~) is still expanded by `sh -c` at exec time, as before.
--  * bind flags: binde -> { repeating = true }, bindl -> { locked = true },
--    bindel -> both, bindm -> { mouse = true }. `mouse` is missing from the
--    HL.BindOptions stub class but is the documented flag (wiki binds/flags,
--    binds/devices/mouse) and is what the official example uses. 0.56.1's
--    hl.bind does not actually read it (src/config/lua/bindings/
--    LuaBindingsToplevel.cpp); the drag/resize behaviour comes from the
--    window.drag()/window.resize() dispatchers themselves. Kept as documented.
--  * legacy dispatchers -> hl.dsp.*: workspace -> focus({ workspace }),
--    movetoworkspace[silent] -> window.move({ workspace, follow }),
--    movefocus l/r/u/d -> focus({ direction = "left"/... }) (the Lua API only
--    accepts left/right/up/down), movewindow <dir> -> window.move({ direction }),
--    killactive -> window.close() (graceful, like killactive; window.kill() is
--    SIGKILL), fullscreen 0/1 -> window.fullscreen({ mode = "fullscreen" /
--    "maximized" }), layoutmsg -> layout(), changegroupactive b/f ->
--    group.prev()/group.next(), togglespecialworkspace -> workspace.
--    toggle_special(), resizeactive -> window.resize({ x, y, relative = true }),
--    bindm movewindow/resizewindow -> window.drag()/window.resize().
--  * submap = resize ... submap = reset -> hl.define_submap("resize", fn).
--  * windowrule/layerrule blocks -> hl.window_rule()/hl.layer_rule(); size/move
--    kept as the "W H" string form (wiki: rules/window-rules, position & size).
--  * Outside this file (not translated, behaviour change once Lua is live):
--    scripts/hypr-cheatsheet.sh parses ~/.config/hypr/hyprland.conf; several
--    scripts and waybar call `hyprctl dispatch <legacy syntax>`, which under the
--    Lua config manager expects hl.dsp.* expressions instead.

------------------
---- MONITORS ----
------------------

-- Use preferred resolution at auto position and 1x scale.
-- Laptop internal display: auto-detect. Override per-host via sourced file if needed.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal       = "kitty"
local browser        = "firefox"
local fileManager    = "kitty -e yazi"
-- GUI file manager for drag-and-drop / USB / Trash (yazi stays the keyboard daily driver).
local guiFileManager = "pcmanfm"
local launcher       = "rofi -show drun -show-icons -theme ~/.config/rofi/doom-vibrant.rasi"
-- cliphist's own rofi script mode: images show as previews, not "[[ binary data ]]".
local clipMenu       = "rofi -modi clipboard:cliphist-rofi-img -show clipboard -show-icons -theme ~/.config/rofi/doom-vibrant.rasi -theme-str 'element-icon { size: 96px; }'"
local colorPick      = "hyprpicker -a"
local locker         = "hyprlock"
local powerMenu      = "wlogout --protocol layer-shell"

------------------
---- ENV VARS ----
------------------

-- Cursor. XCURSOR_THEME must be set alongside HYPRCURSOR_THEME: native Wayland
-- clients follow hyprcursor, but XWayland apps and anything using libXcursor
-- read XCURSOR_* only, and fell back to the default theme without it. Theme name
-- matches gtk.cursorTheme in home/gtk.nix; resolves via the user profile's
-- share/icons/Adwaita/cursors.
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("MOZ_USE_XINPUT2", "1")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("NIXOS_OZONE_WL", "1")
-- Zoneinfo lookup — NixOS has no /usr/share/zoneinfo, so explicit TZ=<Zone>
-- lookups (waybar's Jakarta clock, eww world clocks) fall back to UTC unless
-- TZDIR points at the system zoneinfo. Fixes both bars showing the wrong time.
hl.env("TZDIR", "/etc/zoneinfo")

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Status bar — bottom, Doom Vibrant themed
    hl.exec_cmd("waybar")

    -- Notifications: through swaync's systemd unit, the one instance. Its D-Bus
    -- activation file (org.erikreider.swaync.cc, swaync >= 0.12) starts that unit
    -- anyway when waybar's widget calls; a second plain `swaync' here lost the bus
    -- name and failed 5 times per login. systemd also restarts it if it crashes.
    hl.exec_cmd("systemctl --user start swaync")

    -- Wallpaper daemon + imperative wallpaper set (declarative directives are
    -- unreliable on hyprpaper 0.8.4 — see scripts/set-wallpaper.sh)
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("$HOME/.config/hypr/scripts/set-wallpaper.sh")

    -- Idle management (dims → locks → dpms off)
    hl.exec_cmd("hypridle")

    -- Clipboard history (text + images)
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Tray applets
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- Polkit agent
    hl.exec_cmd("/run/current-system/sw/libexec/polkit-kde-authentication-agent-1")

    -- Blue-light filter (enabled at sunset; configure via hyprsunset)
    hl.exec_cmd("hyprsunset -t 4500")

    -- eww — nerdy system overlay. `eww open` auto-starts the daemon and waits for
    -- it; do NOT use `eww daemon && eww open` — `eww daemon` blocks in the
    -- foreground so the `&&` open never runs and the panel never appears at boot.
    hl.exec_cmd("eww open syspanel")

    -- Launcher daemons — walker needs the elephant backend running first. vicinae
    -- runs its own systemd user service. (rofi on SUPER+Space needs nothing.)
    --
    -- anyrun is intentionally NOT daemonised: `anyrun daemon` + a toggling `anyrun`
    -- client desyncs its visibility state (client reports "already visible" while no
    -- window maps, and orphan client procs accumulate), so SUPER+CTRL+Space silently
    -- did nothing. The SUPER+CTRL+Space bind now fresh-launches `anyrun` each press —
    -- marginally slower first paint, but reliable like rofi.
    hl.exec_cmd("elephant")
    hl.exec_cmd("walker --gapplication-service")

    -- hyprshell — hold-ALT MRU window switcher. The daemon pushes its own ALT+Tab
    -- bind into the compositor once it is up (config in home/hyprland.nix).
    hl.exec_cmd("hyprshell run")

    -- Drop-down scratchpad terminal (Yakuake-style). A dedicated kitty parked on
    -- the `special:term` workspace, spawned once at boot and kept alive — toggling
    -- only shows/hides it (redraw, no relaunch). Distinct --class so the windowrule
    -- below targets *this* instance, never SUPER+Return terminals. Toggle: SUPER+minus.
    -- kitty is not single-instance unless asked for (--single-instance), so unlike
    -- ghostty this launch cannot be absorbed by an already-running process and
    -- quietly lose its --class.
    hl.exec_cmd("kitty --class=com.kitty.term -o background_opacity=0.9",
        { workspace = "special:term silent" })
end)

-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Doom Vibrant palette:
--   bg        #242730    base0     #1c1f24
--   bg-alt    #2a2e38    base4     #3d4451
--   border-dim #484854   comment   #62686E
--   fg        #bbc2cf    blue      #51afef
--   red       #ff665c    green     #7bc275
--   yellow    #FCCE7B    magenta   #C57BDB
--   cyan      #5cEfFF

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,

        col = {
            -- Active: blue → magenta gradient; inactive: dim border
            active_border   = { colors = { "rgba(51afefff)", "rgba(C57BDBff)" }, angle = 45 },
            inactive_border = "rgba(484854aa)",
        },

        resize_on_border        = true,
        extend_border_grab_area = 8,
        allow_tearing           = false,
        layout                  = "dwindle",
    },

    decoration = {
        rounding           = 8,
        active_opacity     = 1.0,
        inactive_opacity   = 0.95,
        fullscreen_opacity = 1.0,

        shadow = {
            enabled        = true,
            range          = 14,
            render_power   = 2,
            color          = "rgba(1c1f24cc)",
            color_inactive = "rgba(1c1f2488)",
        },

        blur = {
            enabled           = true,
            size              = 6,
            passes            = 3,
            new_optimizations = true,
            xray              = false,
            noise             = 0.0117,
            contrast          = 0.8916,
            brightness        = 0.8172,
            popups            = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Doom-inspired easing curves
local function bezier(name, x0, y0, x1, y1)
    hl.curve(name, { type = "bezier", points = { { x0, y0 }, { x1, y1 } } })
end
bezier("doom",    0.05, 0.9, 0.1, 1.05)
bezier("linear",  0.0,  0.0, 1.0, 1.0)
bezier("easeOut", 0.0,  0.0, 0.2, 1.0)
bezier("easeIn",  0.4,  0.0, 1.0, 1.0)
bezier("spring",  0.25, 1.0, 0.5, 1.0)

hl.animation({ leaf = "windows",          enabled = true, speed = 4,  bezier = "doom",   style = "slide" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 3,  bezier = "easeIn", style = "slide" })
hl.animation({ leaf = "windowsMove",      enabled = true, speed = 3,  bezier = "doom" })
hl.animation({ leaf = "border",           enabled = true, speed = 6,  bezier = "linear" })
-- borderangle without `loop`: the gradient still sweeps once when a window
-- takes focus. With `loop` it span forever, so the focused window forced a
-- continuous recomposite — a permanent GPU wakeup source on battery.
hl.animation({ leaf = "borderangle",      enabled = true, speed = 30, bezier = "linear" })
hl.animation({ leaf = "fade",             enabled = true, speed = 4,  bezier = "doom" })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 4,  bezier = "spring", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4,  bezier = "spring", style = "slidevert" })
hl.animation({ leaf = "layers",           enabled = true, speed = 3,  bezier = "doom",   style = "slide" })

hl.config({
    dwindle = {
        -- pseudotile is dispatcher-only in Hyprland 0.55 (see SUPER+P bind); the
        -- dwindle:pseudotile config option was removed.
        preserve_split = true,
    },

    master = {
        new_status  = "master",
        mfact       = 0.55,
        orientation = "left",
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
        focus_on_activate        = false,
    },

    ecosystem = {
        -- Hyprland pops an update-news window after a version bump and periodically
        -- nags about donations. Both steal focus mid-session on a rolling channel.
        no_update_news  = true,
        no_donation_nag = true,
    },

    binds = {
        -- Pressing the current workspace's own key sends you back to the previous
        -- one, so SUPER+3 SUPER+3 toggles instead of doing nothing.
        workspace_back_and_forth = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "de",
        kb_options = "caps:escape", -- Caps Lock → Escape (Doom/vim essential)

        -- Defaults (600ms / 25Hz) feel sluggish for hjkl motions in Doom and vim.
        repeat_delay = 250,
        repeat_rate  = 40,

        follow_mouse  = 1,
        sensitivity   = 0,
        accel_profile = "adaptive",

        touchpad = {
            natural_scroll          = true,
            scroll_factor           = 0.5,
            disable_while_typing    = true,
            tap_to_click            = true,
            tap_and_drag            = true,
            drag_lock               = true,
            middle_button_emulation = false,
            clickfinger_behavior    = false,
        },
    },

    cursor = {
        inactive_timeout  = 5,
        hide_on_key_press = true,
    },
})

-- 3-finger horizontal swipe switches workspaces
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

---------------
---- BINDS ----
---------------

-- Legend: mainMod = SUPER (like SPC in Doom Emacs)
--   SUPER+<key>       → leader + key (workspace, focus, launch)
--   SUPER+SHIFT+<key> → leader + SHIFT (destructive / move operations)
--   SUPER+CTRL+<key>  → system / session operations
--   Submaps below act like Doom key-chord prefixes (SPC w, SPC b, etc.)

local mainMod = "SUPER"

-- "SUPER SHIFT" + "H" -> "SUPER + SHIFT + H"; "" + "Print" -> "Print"
local function keys(mods, key)
    if mods == "" then return key end
    return (mods:gsub(" ", " + ")) .. " + " .. key
end
local function bind(mods, key, dispatcher, opts)
    return hl.bind(keys(mods, key), dispatcher, opts)
end
local exec = hl.dsp.exec_cmd

local M      = mainMod
local MS     = mainMod .. " SHIFT"
local MC     = mainMod .. " CTRL"
local MA     = mainMod .. " ALT"
local MAS    = mainMod .. " ALT SHIFT"
local MCS    = mainMod .. " CTRL SHIFT"

-- ── Core: open / launch ─────────────────────────────────────────────────────
-- SPC o t — open terminal
bind(M,  "Return", exec(terminal))
-- SPC SPC / M-x — launcher (rofi drun). Alternatives on modifier variants so
-- you can pick a favourite: walker / anyrun / vicinae (see home/launchers.nix).
bind(M,  "Space", exec(launcher))
bind(MS, "Space", exec("walker"))
bind(MC, "Space", exec("anyrun"))
bind(MA, "Space", exec("vicinae toggle"))
-- SPC , (buffers) — fuzzy switch/jump to any open window incl. terminals.
-- Type-to-search, all workspaces. ALT+Tab is the *other* cross-workspace
-- switcher (hyprshell, hold-ALT MRU cycling) — do NOT bind ALT+Tab here, the
-- hyprshell daemon installs that bind itself at startup and a static one here
-- would win back on `hyprctl reload`. See services.hyprshell in home/hyprland.nix.
bind(MS, "Tab", exec("~/.config/hypr/scripts/window-switcher.sh"))
-- Toggle the eww nerdy system overlay
bind(MS, "E", exec("eww open --toggle syspanel"))
-- Restart waybar (the status bar) — e.g. after a config tweak or if it vanished
bind(MS, "B", exec("killall -q waybar; waybar &"))

-- ── Run-or-raise: jump to an app (focus if running, else launch) ─────────────
-- SUPER+ALT+<key> — Doom "SPC a" (application) style quick-jump.
local ror = "~/.config/hypr/scripts/run-or-raise.sh"
bind(MA, "F", exec(ror .. " firefox firefox"))
bind(MA, "E", exec(ror .. ' emacs emacsclient -c -a ""'))
bind(MA, "T", exec(ror .. " kitty kitty"))
-- SPC b b — fuzzy-jump to a (Doom) Emacs buffer via rofi, then raise Emacs.
bind(MA, "B", exec("~/.config/hypr/scripts/doom-buffer-switcher.sh"))
-- Fuzzy-switch a Firefox tab via rofi (brotab), then raise Firefox.
bind(MA, "W", exec("~/.config/hypr/scripts/firefox-tab-switcher.sh"))
-- SPC o b — browser
bind(M,  "B", exec(browser))
-- SPC o e — emacs client
bind(M,  "A", exec('emacsclient -c -a ""'))
-- SPC o f — file manager (TUI: yazi)
bind(M,  "E", exec(fileManager))
-- GUI file manager (pcmanfm) — drag-and-drop, Trash, removable media.
-- Super+Shift+E is eww syspanel; Super+Alt+E is emacs run-or-raise.
bind(MC, "E", exec(guiFileManager))
-- SPC o - — open a second terminal side-by-side
bind(MS, "Return", exec(terminal))

-- ── Core: window control ─────────────────────────────────────────────────────
-- SPC b k / SPC b d — kill window (buffer kill)
bind(M,  "Q", hl.dsp.window.close())
-- SPC w v — split vertical (new pane to the right)
bind(M,  "V", hl.dsp.layout("togglesplit"))
-- SPC t f — toggle floating
bind(MS, "V", hl.dsp.window.float({ action = "toggle" }))
-- SPC w z / SPC t z — fullscreen
bind(M,  "F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- SPC w m — maximize (no gaps)
bind(MS, "F", hl.dsp.window.fullscreen({ mode = "maximized" }))
-- SPC t p — pin floating window on top
bind(M,  "I", hl.dsp.window.pin())

-- ── Window groups (tabbed stacks — free in dwindle, previously unbound) ──────
-- SUPER+G folds the focused window into a tab group with its neighbour; once
-- grouped, SUPER+ALT+, / . cycle the tabs.
bind(M,  "G",      hl.dsp.group.toggle())
bind(MA, "comma",  hl.dsp.group.prev())
bind(MA, "period", hl.dsp.group.next())

-- ── Focus: vim hjkl (SPC w h/j/k/l) ─────────────────────────────────────────
bind(M, "H", hl.dsp.focus({ direction = "left" }))
bind(M, "J", hl.dsp.focus({ direction = "down" }))
bind(M, "K", hl.dsp.focus({ direction = "up" }))
bind(M, "L", hl.dsp.focus({ direction = "right" }))

-- Arrow keys as fallback
bind(M, "left",  hl.dsp.focus({ direction = "left" }))
bind(M, "down",  hl.dsp.focus({ direction = "down" }))
bind(M, "up",    hl.dsp.focus({ direction = "up" }))
bind(M, "right", hl.dsp.focus({ direction = "right" }))

-- ── Move windows (SPC w H/J/K/L) ─────────────────────────────────────────────
bind(MS, "H", hl.dsp.window.move({ direction = "left" }))
bind(MS, "J", hl.dsp.window.move({ direction = "down" }))
bind(MS, "K", hl.dsp.window.move({ direction = "up" }))
bind(MS, "L", hl.dsp.window.move({ direction = "right" }))

-- ── Workspaces: go to (SPC b 1-9, like SPC b n/p for next/prev) ──────────────
for i = 1, 10 do
    bind(M, tostring(i % 10), hl.dsp.focus({ workspace = i })) -- key 0 → workspace 10
end

-- Next / previous workspace (SPC b n / SPC b p)
-- Using CTRL+arrow for DE-keyboard friendliness; also hjkl with ALT
bind(M,  "bracketright", hl.dsp.focus({ workspace = "+1" })) -- ] / ü on DE layout
bind(M,  "bracketleft",  hl.dsp.focus({ workspace = "-1" })) -- [ / ö on DE layout
bind(MA, "L",            hl.dsp.focus({ workspace = "+1" }))
bind(MA, "H",            hl.dsp.focus({ workspace = "-1" }))
bind(MC, "L",            hl.dsp.focus({ workspace = "+1" }))
bind(MC, "H",            hl.dsp.focus({ workspace = "-1" }))
bind(MC, "right",        hl.dsp.focus({ workspace = "+1" }))
bind(MC, "left",         hl.dsp.focus({ workspace = "-1" }))
bind(M,  "Tab",          hl.dsp.focus({ workspace = "previous" }))

-- ── Workspaces: move window to (SPC b m 1-9) ─────────────────────────────────
for i = 1, 10 do
    bind(MS, tostring(i % 10), hl.dsp.window.move({ workspace = i, follow = true })) -- key 0 → workspace 10
end

-- Move window to next/prev workspace silently
bind(MAS, "L", hl.dsp.window.move({ workspace = "+1", follow = false }))
bind(MAS, "H", hl.dsp.window.move({ workspace = "-1", follow = false }))

-- ── Drop-down terminal (Yakuake-style, SPC t s) ──────────────────────────────
-- Toggle the dedicated Ghostty on its OWN special:term workspace. Script
-- respawns it if you `exit`ed the terminal, so SUPER+minus always gives a shell.
bind(M,  "minus", exec("~/.config/hypr/scripts/toggle-scratch-term.sh"))
-- SUPER+SHIFT+minus: banish the *currently focused* window into special:scratch
-- — a SEPARATE generic scratchpad (its own workspace), unrelated to the terminal.
-- Reveal banished windows by toggling special:scratch (e.g. SUPER+CTRL+minus).
bind(MS, "minus", hl.dsp.window.move({ workspace = "special:scratch", follow = false }))
bind(MC, "minus", hl.dsp.workspace.toggle_special("scratch"))

-- ── Clipboard history (M-y / SPC y — consult-yank-pop feel) ──────────────────
bind(M, "Y", exec(clipMenu))

-- ── Notification center (swaync — KDE-style panel) ───────────────────────────
-- SUPER+N toggles the control center; SUPER+SHIFT+N toggles Do-Not-Disturb.
bind(M,   "N", exec("swaync-client --toggle-panel --skip-wait"))
bind(MS,  "N", exec("~/.config/hypr/scripts/dnd-toggle.sh"))
-- Dismiss the latest / all visible notifications.
bind(MC,  "N", exec("swaync-client --close-latest"))
bind(MCS, "N", exec("swaync-client --close-all"))

-- ── Screenshots (like flameshot in EXWM) ─────────────────────────────────────
-- Every shot goes to the clipboard *and* ~/Pictures/Screenshots (newest name
-- sorts last), so it can be pasted now and found later (SPC i S in Emacs).
local shot = "~/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png"
bind("",      "Print", exec("grimblast --notify copysave area "   .. shot))
bind("SHIFT", "Print", exec("grimblast --notify copysave output " .. shot))
bind(M,       "Print", exec("grimblast --notify copysave screen " .. shot))
bind(MS,      "Print", exec("grimblast --notify copysave active " .. shot))
-- Annotate before saving: grab a region and hand it straight to swappy (which
-- was installed and window-ruled but had no binding to reach it).
bind("CTRL",  "Print", exec("grimblast save area - | swappy -f -"))

-- ── Lid switch ───────────────────────────────────────────────────────────────
-- Lock on close, and don't leave the session unlocked on a shut laptop. Device
-- name comes from `hyprctl devices` (Switches → "Lid Switch"). locked so it fires
-- even while the screen is already locked/off.
bind("", "switch:on:Lid Switch", exec(locker), { locked = true })

-- ── Lock / session (SPC q — quit prefix in Doom) ─────────────────────────────
-- Lock: SUPER+Escape (SUPER+L is reserved for Doom-style movefocus-right)
bind(M,  "Escape", exec(locker))
-- Power menu: SUPER+SHIFT+Escape
bind(MS, "Escape", exec(powerMenu))
-- Hard exit Hyprland (SUPER+CTRL+Q)
bind(MC, "Q", hl.dsp.exit())

-- ── Keybinding cheatsheet (which-key style popup) ────────────────────────────
-- SUPER+SHIFT+/  ( = SUPER+? ) lists every hyprland.conf bind in rofi.
bind(MS, "slash", exec("~/.config/hypr/scripts/hypr-cheatsheet.sh"))

-- ── Run a shell command from rofi, output in a floating terminal ─────────────
-- SUPER+SHIFT+X — type e.g. `pwd` or `ls -la`; prefix `em ` for an emacs vterm.
bind(MS, "X", exec("~/.config/hypr/scripts/rofi-run-cmd.sh"))

-- ── Hyprland reload ──────────────────────────────────────────────────────────
bind(MC, "R", exec("hyprctl reload"))

-- ── Color picker ─────────────────────────────────────────────────────────────
bind(MS, "C", exec(colorPick))

-- ── Resize submap (SPC w r → resize mode, like evil-window-resize) ───────────
bind(M, "R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    local function resize(x, y)
        return hl.dsp.window.resize({ x = x, y = y, relative = true })
    end
    local rep = { repeating = true }
    bind("", "H",     resize(-30,   0), rep)
    bind("", "L",     resize( 30,   0), rep)
    bind("", "K",     resize(  0, -20), rep)
    bind("", "J",     resize(  0,  20), rep)
    bind("", "left",  resize(-30,   0), rep)
    bind("", "right", resize( 30,   0), rep)
    bind("", "up",    resize(  0, -20), rep)
    bind("", "down",  resize(  0,  20), rep)
    bind("", "Return", hl.dsp.submap("reset"))
    bind("", "Escape", hl.dsp.submap("reset"))
    bind("", "Q",      hl.dsp.submap("reset"))
end)

-- ── Media keys ───────────────────────────────────────────────────────────────
local lockedRepeat = { locked = true, repeating = true } -- bindel
local locked       = { locked = true }                   -- bindl
bind("", "XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@   5%+ && swayosd-client --output-volume raise"), lockedRepeat)
bind("", "XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@   5%- && swayosd-client --output-volume lower"), lockedRepeat)
bind("", "XF86AudioMute",        exec("wpctl set-mute   @DEFAULT_AUDIO_SINK@   toggle && swayosd-client --output-volume mute-toggle"), locked)
bind("", "XF86AudioMicMute",     exec("wpctl set-mute   @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
bind("", "XF86AudioPlay",        exec("playerctl play-pause"), locked)
bind("", "XF86AudioNext",        exec("playerctl next"), locked)
bind("", "XF86AudioPrev",        exec("playerctl previous"), locked)

-- ── Brightness ────────────────────────────────────────────────────────────────
bind("", "XF86MonBrightnessUp",   exec("brightnessctl set  +5% && swayosd-client --brightness raise"), lockedRepeat)
bind("", "XF86MonBrightnessDown", exec("brightnessctl set   5%- && swayosd-client --brightness lower"), lockedRepeat)

-- ── Keyboard backlight (ThinkPad tpacpi::kbd_backlight — 3 levels, 0-2) ───────
-- NOTE: on many ThinkPads Fn+Space is handled in firmware/EC and cycles the LED
-- WITHOUT emitting an evdev key — then these binds never fire (nothing to bind).
-- Test with `wev` whether a key is actually sent; if not, it's firmware-only.
bind("", "XF86KbdBrightnessUp",   exec("brightnessctl -d tpacpi::kbd_backlight set +1"), locked)
bind("", "XF86KbdBrightnessDown", exec("brightnessctl -d tpacpi::kbd_backlight set 1-"), locked)
bind("", "XF86KbdLightOnOff",     exec("brightnessctl -d tpacpi::kbd_backlight set +1"), locked)

-- ── Mouse: drag / resize floating windows ────────────────────────────────────
bind(M, "mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(M, "mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Mouse scroll on empty desktop ────────────────────────────────────────────
bind(M, "mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind(M, "mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Suppress maximize requests — Hyprland handles fullscreen natively
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- ── Floating rules ────────────────────────────────────────────────────────────
-- Agent test frames (Emacs frames titled CLAUDE-LAB or claude-*) open on the
-- hidden special:claude workspace and never take focus: a test frame once
-- took the keyboard from a minibuffer you were typing in.
hl.window_rule({
    name  = "agent-test-frames",
    match = { title = "^(CLAUDE-LAB|claude-.*)$" },
    workspace = "special:claude silent",
    no_initial_focus = true,
})
hl.window_rule({
    name  = "float-misc",
    match = { class = [[^(nm-applet|blueman-manager|pavucontrol|wlogout|org\.kde\.ark|org\.kde\.kcalc|gnome-calculator|swappy|hyprpicker)$]] },
    float = true,
})
hl.window_rule({
    name  = "float-dialogs",
    match = { title = "^(Open File|Save As|Confirm|Picture-in-Picture|Firefox — Sharing Indicator)" },
    float = true,
})
-- Picture-in-Picture should follow you across workspaces — floating alone left
-- it behind on every switch, which defeats the point of a PiP window.
-- NB: Hyprland 0.56 has no windowrule:keepaspectratio key (config error); the
-- PiP window manages its own aspect ratio anyway.
hl.window_rule({
    name  = "pip-pin",
    match = { title = "^(Picture-in-Picture)$" },
    pin   = true,
})
-- rofi-run-cmd.sh output terminal — float + centre.
hl.window_rule({
    name   = "float-rofi-cmd",
    match  = { class = [[^(com\.rofi\.cmd)$]] },
    float  = true,
    size   = "900 500",
    center = true,
})
-- Drop-down terminal (spawned to special:term in AUTOSTART). Toggle: SUPER+minus.
-- Wide, top-anchored (drops from the top via slidevert). Ghostty runs with
-- --background-opacity=0.9 so Hyprland blur (xray off) frosts what sits behind
-- it. 1766×921 on 1920×1080: x=77 → 77px left/right margins; y=82 clears the
-- 74px top waybar (+8 gap); height 921 leaves a matching 77px bottom margin
-- (1080-82-921). The toggle script re-pins position on every show.
-- NB: Hyprland 0.55 rejects noborder/bordersize as block-rule keys, so for now
-- the window keeps the normal 2px gradient border.
hl.window_rule({
    name     = "dropdown-term",
    match    = { class = [[^(com\.kitty\.term)$]] },
    float    = true,
    size     = "1766 921",
    move     = "77 82",
    rounding = 10,
})

-- ── Float sizes ──────────────────────────────────────────────────────────────
hl.window_rule({
    name   = "size-pavucontrol",
    match  = { class = "^(pavucontrol)$" },
    size   = "900 600",
    center = true,
})
hl.window_rule({
    name   = "size-nm-editor",
    match  = { class = "^(nm-connection-editor)$" },
    size   = "1000 700",
    center = true,
})
hl.window_rule({
    name   = "size-blueman",
    match  = { class = "^(blueman-manager)$" },
    size   = "800 600",
    center = true,
})
hl.window_rule({
    name   = "center-swappy",
    match  = { class = "^(swappy)$" },
    center = true,
})

-- ── Workspace pin: apps go to their "natural" workspace on open ───────────────
hl.window_rule({
    name      = "ws-browser",
    match     = { class = "^(firefox|vivaldi-stable|brave-browser|google-chrome|chromium-browser)$" },
    workspace = "2",
})
hl.window_rule({
    name      = "ws-emacs",
    match     = { class = "^([Ee]macs)$" },
    workspace = "3",
})
hl.window_rule({
    name      = "ws-mail",
    match     = { class = "^(thunderbird)$" },
    workspace = "4",
})
hl.window_rule({
    name      = "ws-chat",
    match     = { class = "^(telegram-desktop|beeper|Element)$" },
    workspace = "5",
})
hl.window_rule({
    name      = "ws-cloud",
    match     = { class = [[^(org\.nextcloud\.desktopclient)$]] },
    workspace = "6",
})
-- Tasks / notes → planify (io.github.alainm23.planify). The old anytype,
-- super-productivity, Spotify and bitwarden-desktop pins were dropped — those
-- apps are no longer installed (electron purge), so their rules were dead.
hl.window_rule({
    name      = "ws-tasks",
    match     = { class = [[^(io\.github\.alainm23\.planify)$]] },
    workspace = "7",
})

-- ── Opacity: terminals slightly transparent when unfocused ───────────────────
hl.window_rule({
    name    = "opacity-terminals",
    match   = { class = [[^(kitty|com\.kitty\.term|Alacritty|org\.wezfurlong\.wezterm|com\.mitchellh\.ghostty)$]] },
    opacity = "1.0 override 0.88 override",
})

-- ── Idle inhibit: no dim/lock while any window is fullscreen (video, slides) ──
-- Hyprland 0.56 spells this idle_inhibit; value fullscreen inhibits idle only while the window is actually fullscreen.
hl.window_rule({
    name         = "idleinhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})

-- ── Layer rules: blur the shell surfaces ─────────────────────────────────────
-- Namespaces verified with `hyprctl layers` — the previous rule matched `mako`,
-- which was replaced by swaync long ago, so the notification centre and the eww
-- overlay rendered unblurred:
--   waybar                      → waybar
--   swaync panel                → swaync-control-center
--   swaync popups               → swaync-notification-window
--   eww syspanel                → gtk-layer-shell
hl.layer_rule({
    name  = "blur-bars",
    match = { namespace = "waybar|swaync-control-center|gtk-layer-shell" },
    blur  = true,
})
-- swaync's popup surface is anchored full-height (400x1036) so toasts can stack
-- downwards, but the area below the toast is fully transparent. Blurring the
-- whole surface painted a glass bar down the screen, so restrict the blur to
-- pixels above the alpha threshold — i.e. the toast itself.
hl.layer_rule({
    name         = "blur-notifications",
    match        = { namespace = "swaync-notification-window" },
    blur         = true,
    ignore_alpha = 0.4,
})
-- Launchers — rofi on SUPER+Space plus the three alternates (see AUTOSTART).
hl.layer_rule({
    name  = "blur-launchers",
    match = { namespace = "rofi|walker|anyrun|vicinae" },
    blur  = true,
})
