-- ═══════════════════════════════════════════════════════════════════
-- Unit-3 additions for Hyprland 0.57+ (Lua config)
-- Loaded by hyprland.lua right before user.lua, so anything in user.lua wins.
-- Personal settings (input methods, app shortcuts, autostarts) belong in user.lua.
-- ═══════════════════════════════════════════════════════════════════

-- App icons: Quickshell and Qt apps otherwise fall back to bare hicolor (many icons missing).
-- The kde platform theme makes Qt apps read ~/.config/kdeglobals (Papirus-Dark icons, Breeze style).
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QS_ICON_THEME", "Papirus-Dark")

-- Idle lock (timeout is set in Control Center > System > Lock & Idle, written to hypridle.conf)
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
    -- X11 apps (Steam, Proton games): same font smoothing and cursor as Wayland apps
    hl.exec_cmd("xrdb -merge ~/.Xresources")
end)

-- Reliable app-menu shortcut (in addition to tapping SUPER)
hl.bind("SUPER + Space", hl.dsp.exec_cmd("echo t >> /tmp/qs-menu"), { description = "Shell · App menu", dont_inhibit = true })

-- ── Monitors ──
-- Layout, refresh rates and primary screen are set in the Control Center (System > Display),
-- which writes monitors.lua next to this file.
require("monitors")

-- File manager
hl.bind("SUPER + E", hl.dsp.exec_cmd("thunar"), { description = "Apps · File manager" })

-- System update terminal (Control Center > System > Update): centered floating window
hl.window_rule({
    match = { class = "^(unit3-update)$" },
    float = true,
    center = true,
})

-- Alt+Tab window switcher with live previews (quickshell/widgets/AltTab.qml).
-- Replaces Hyprland's plain cycle_next binds from hyprland.lua.
-- Releasing Alt switches: while the switcher is open, a timer polls whether Alt is still held.
local alt_keys = { "Alt_L", "Alt_R" }
local alt_timer = nil

local function alt_down()
    for _, k in ipairs(alt_keys) do
        if hl.is_key_down(k) then return true end
    end
    return false
end

local function watch_alt()
    if alt_timer then alt_timer:set_enabled(true); return end
    alt_timer = hl.timer(function()
        if alt_down() then return end
        alt_timer:set_enabled(false)
        hl.exec_cmd("qs ipc call alttab commit")
    end, { timeout = 25, type = "repeat" })
end

hl.unbind("ALT + Tab")
hl.unbind("ALT + SHIFT + Tab")
hl.bind("ALT + Tab", function() hl.exec_cmd("qs ipc call alttab next"); watch_alt() end, { description = "Windows · Switch windows" })
hl.bind("ALT + SHIFT + Tab", function() hl.exec_cmd("qs ipc call alttab prev"); watch_alt() end, { description = "Windows · Switch windows, backwards" })

-- Minimize: SUPER+N sends the focused window to a hidden workspace without leaving yours.
-- Alt+Tab lists minimized windows (tagged MIN); picking one brings it back to your workspace.
hl.bind("SUPER + N", hl.dsp.window.move({ workspace = "special:minimized", follow = false }), { description = "Windows · Minimize" })

-- Spotify: SUPER+M shows/hides its scratchpad, or starts it if it isn't running.
-- (hyprland.lua's version used the pre-0.57 "hyprctl dispatch togglespecialworkspace" syntax.)
hl.unbind("SUPER + M")
hl.bind("SUPER + M", function()
    for _, w in ipairs(hl.get_windows()) do
        if w.class == "Spotify" or w.class == "spotify" then
            hl.dispatch(hl.dsp.workspace.toggle_special("spotify"))
            return
        end
    end
    hl.exec_cmd("spotify")
end, { description = "Apps · Spotify (show / hide)" })

-- Real session lock (quickshell/lock/lockscreen.qml uses WlSessionLock): if the lockscreen ever
-- crashes, the session stays locked; running the lock again (SUPER+L / lock.sh) takes it back over.
hl.config({ misc = { allow_session_lock_restore = true } })

-- Shortcut cheat sheet (quickshell/widgets/CheatSheet.qml), built from these descriptions
hl.bind("SUPER + slash", hl.dsp.exec_cmd("qs ipc call cheatsheet toggle"), { description = "Shell · Shortcut cheat sheet" })
