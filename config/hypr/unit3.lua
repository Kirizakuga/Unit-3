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
end)

-- Reliable app-menu shortcut (in addition to tapping SUPER)
hl.bind("SUPER + Space", hl.dsp.exec_cmd("echo t >> /tmp/qs-menu"), { dont_inhibit = true })

-- ── Monitors ──
-- Layout, refresh rates and primary screen are set in the Control Center (System > Display),
-- which writes monitors.lua next to this file.
require("monitors")

-- File manager
hl.bind("SUPER + E", hl.dsp.exec_cmd("thunar"))

-- System update terminal (Control Center > System > Update): centered floating window
hl.window_rule({
    match = { class = "^(unit3-update)$" },
    float = true,
    center = true,
})

-- Alt+Tab window switcher with live previews (quickshell/widgets/AltTab.qml).
-- Replaces Hyprland's plain cycle_next binds from hyprland.lua.
-- Releasing Alt switches: while the switcher is open, a timer polls whether Alt is still held.
-- is_key_down's key format isn't documented, so the first Alt+Tab detects it: Alt is
-- certainly held at that moment, so whichever names report "down" are the ones to watch.
local alt_candidates = { "Alt_L", "Alt_R", "ALT_L", "ALT_R", "alt_l", "alt_r", 64, 108, 56, 100 }
local alt_watch = {}
local alt_timer = nil
local alt_log = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/unit3-alttab.log"

local function log(msg)
    local f = io.open(alt_log, "a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

local function alt_down()
    for _, k in ipairs(alt_watch) do
        local ok, down = pcall(hl.is_key_down, k)
        if ok and down then return true end
    end
    return false
end

local function watch_alt()
    if #alt_watch == 0 then
        for _, k in ipairs(alt_candidates) do
            local ok, down = pcall(hl.is_key_down, k)
            if ok and down then table.insert(alt_watch, k) end
        end
        local names = {}
        for _, k in ipairs(alt_watch) do table.insert(names, tostring(k)) end
        log("alt key names detected: [" .. table.concat(names, ", ") .. "]")
        if #alt_watch == 0 then return end   -- can't detect: Enter / click still switch
    end
    if alt_timer then alt_timer:set_enabled(true); return end
    alt_timer = hl.timer(function()
        if alt_down() then return end
        alt_timer:set_enabled(false)
        hl.exec_cmd("qs ipc call alttab commit")
    end, { timeout = 25, type = "repeat" })
end

hl.unbind("ALT + Tab")
hl.unbind("ALT + SHIFT + Tab")
hl.bind("ALT + Tab", function() hl.exec_cmd("qs ipc call alttab next"); watch_alt() end)
hl.bind("ALT + SHIFT + Tab", function() hl.exec_cmd("qs ipc call alttab prev"); watch_alt() end)
