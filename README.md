> [!NOTE]
> **This is a fork of [samyns/Unit-3](https://github.com/samyns/Unit-3)** ported to **Hyprland 0.57 (Lua config)**,
> with a settings page, Alt+Tab switcher, safe updater and matching app themes. All credit for the original rice goes to samyns.

## What this fork adds

- **Hyprland 0.57 Lua config:** `hypr/hyprland.lua` (converted from `hyprland.conf`), plus `unit3.lua` for the additions below.
  Personal overrides go in `hypr/user.lua`, which the installer creates empty and never overwrites.
- **Control Center → System card** (`SUPER+Tab`, then →):
  - **Display:** primary screen, external screen side, refresh rate per screen (writes `hypr/monitors.lua`)
  - **Lock & Idle:** lock after 5–30 min idle or never, lock before suspend, lock now (writes `hypr/hypridle.conf`)
  - **Power:** power profile, laptop brightness
  - **Shell:** music player, player background, companions (applies instantly)
  - **Update:** pending repo/AUR updates and a guarded updater: Arch news check, snapper snapshot first,
    repo then AUR, re-applies theme tweaks, lists `.pacnew` files, says when to reboot
  - Open a page directly: `qs ipc call ctrl page display`
- **Alt+Tab switcher** with live window previews: hold Alt, Tab / Shift+Tab to move, release to switch;
  W / Q / Delete or × closes a window without leaving the switcher.
- **Workspace overview:** `SUPER+A` shows every workspace in use with live window previews at their real
  positions; click a window or tile to go there, or use arrows + Enter / number keys.
- **Shortcut cheat sheet:** `SUPER+/` lists every keybind, grouped, read live from Hyprland
  (each bind has a `description = "Group · What it does"`).
- **Minimize:** `SUPER+N` hides the focused window; it shows up in Alt+Tab tagged MIN, and picking it brings it back.
- **Fix:** `SUPER+M` (Spotify scratchpad) works again on Hyprland 0.57.
- **Lockscreen is a real session lock** (ext-session-lock): if it ever crashes the session stays locked,
  and pressing the lock key again takes it back over (`misc.allow_session_lock_restore`).
- **Lockscreen:** shows your avatar (`~/.face`), `user@hostname` and your distro + GPU, all detected;
  to show another machine name: `unit3-settings.py set lock.node <name>`. Opens in ~0.7 s (moved out of the `widgets` module), readable cream labels, unlock wipe reveals the desktop,
  no second lock right after login.
  A **now playing** card (MPRIS: Spotify, browsers, VLC…) appears under the login box when music is playing,
  with album art, progress and ⏮ ⏯ ⏭ controls.
- **SDDM login theme `unit3`** matching the lockscreen (`config/sddm/`), plus an example Xsetup for monitor layout.
- **App themes in the same palette and JetBrains Mono:** GTK3/4 (`adw-gtk3` + `gtk.css`), Qt/KDE (`Unit3.colors`),
  kitty, Spotify (Spicetify theme `unit3`).
- **Survives updates:** pacman hooks re-apply sand Papirus folders and the Spotify theme after every update;
  `scripts/unit3-keep.sh` saves/checks/restores every customization.
- **Fixes:** `ctrl.sh` no longer kills `cloudflared`; `ext_last_fr.py` no longer writes to a hard-coded home folder.

### Extra setup (not done by the installer)

```bash
sudo pacman -S --needed adw-gtk-theme papirus-icon-theme papirus-folders ttf-jetbrains-mono nodejs hypridle
sudo papirus-folders -C paleorange --theme Papirus-Dark
cp -r config/gtk-3.0 config/gtk-4.0 config/fontconfig ~/.config/
mkdir -p ~/.local/share/color-schemes && cp config/color-schemes/Unit3.colors ~/.local/share/color-schemes/
# Qt apps: set ColorScheme=Unit3 in ~/.config/kdeglobals (QT_QPA_PLATFORMTHEME=kde is set in unit3.lua)
cp -r config/spicetify/Themes/unit3 ~/.config/spicetify/Themes/ && spicetify config current_theme unit3 color_scheme unit3 && spicetify apply
sudo cp -r config/sddm/unit3 /usr/share/sddm/themes/ && sudo cp config/sddm/10-unit3.conf /etc/sddm.conf.d/
sudo cp config/system/pacman-hooks/*.hook /etc/pacman.d/hooks/ && sudo install -m755 config/system/pacman-hooks/unit3-spotify-retheme /usr/local/bin/
cp config/Xresources ~/.Xresources   # X11 apps (Steam, Proton) get the same font smoothing and cursor
```

---


# Unit-3

Hyprland + Quickshell + Waybar rice for Arch Linux, with a NieR:Automata aesthetic.


## Support

[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white&labelColor=101418)](https://ko-fi.com/samyns)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black&labelColor=101418)](https://www.buymeacoffee.com/samyns)

A ⭐ on the repo or sharing your own rice in the issues makes me just as happy.


# SHOW OFF
https://github.com/user-attachments/assets/f3366b70-cfa0-46ef-b4f5-e461546364e2

## Quick install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/samyns/Unit-3/main/install.sh)
```
or
```
curl -fsSL https://raw.githubusercontent.com/samyns/Unit-3/main/install.sh | bash
```

## What's included

- **Window manager**: Hyprland with custom keybinds (QWERTY layout)
- **Shell/widgets**: Quickshell with custom QML widgets (menu, lockscreen, wallpaper picker, notifications, player)
- **Bar**: Waybar
- **Terminal**: Kitty
- **Theme**: NieR-inspired with custom video transitions

## Control Center

A NieR:Automata-style radial menu accessible via `SUPER + Tab`. The interface is built around a cross of four sub-menus orbiting a central node, with full keyboard navigation.

> [!NOTE]
> The Control Center runs as a separate Quickshell instance and exposes an IPC target named `ctrl`. It can also be toggled from anywhere via `qs ipc call ctrl toggle`.

https://github-production-user-asset-6210df.s3.amazonaws.com/102748858/590523311-2ce7dc52-bffb-43b9-acf0-cfcdc42aadb8.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAVCODYLSA53PQK4ZA%2F20260511%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20260511T144937Z&X-Amz-Expires=300&X-Amz-Signature=e8595addcfe5bcf43b9f9265de0280b5788952a0f8cdea90e6aa9b2547a7b054&X-Amz-SignedHeaders=host&response-content-type=video%2Fmp4

### Features

- **Connection** — Wi-Fi & Bluetooth
  - Toggle radio on/off
  - Scan and connect to Wi-Fi networks with an inline password prompt (no external GUI)
  - List paired Bluetooth devices with connect/disconnect, pair, unpair, and live scan for new devices
- **Audio** — Output & Volume
  - Switch between PipeWire/PulseAudio sinks on the fly
  - Interactive volume slider (click to set, scroll to adjust, right-click to mute)
- **Quickshare** — Send & Receive (KDE Connect)
  - Pick files via a floating Yazi instance and send to paired devices
  - Pair/unpair devices directly from the panel, with a refresh button for discovery
  - Falls back to a clear "Install KDE Connect" prompt if missing
- **Notifications** — History & DND
  - Live history fed by the Quickshell notification daemon (no `mako`/`dunst` needed)
  - Click a notification once to expand (body, urgency, category, app, actions), click again to invoke the source app
  - Do Not Disturb toggle silences popups while preserving history
  - Pinned "Clear All" button

### Navigation

The menu uses three focus levels:

- **L1 — Overview**: navigate between the four slots and the center node
- **L3 — Settings**: focus inside a sub-menu (sub-item + first action are focused simultaneously)

| Key | Action |
|---|---|
| `W` / `↑` | Move up (or scroll up in lists) |
| `A` / `←` | Move left (or scroll left in actions) |
| `S` / `↓` | Move down (or scroll down in lists) |
| `D` / `→` | Move right (or scroll right in actions) |
| `Enter` / `Space` | Activate focused action (or expand a notification) |
| `Esc` | Back to center (or close menu) |

**From the center node**, pressing any direction enters the corresponding sub-menu directly (no double-press). **From a slot**, pressing the same direction enters its settings; pressing the opposite direction returns to center.

When you focus a sub-menu, the whole cross slides ("pulls the tablecloth") to bring the focused panel closer to the center, while the other slots dim but stay visible.


## Customization

Personal overrides go in `~/.config/hypr/user.conf` — this file is **never** overwritten by updates.

Example:
monitor = DP-1, 2560x1440@144, 0x0, 1
input { kb_layout = us }
bind = SUPER, B, exec, firefox

## Keybinds

| Key | Action |
|-----|--------|
| `SUPER` (tap) | Open app menu |
| `SUPER + L` | Lockscreen |
| `SUPER + T` | Terminal (kitty) |
| `SUPER + Return` | Toggle Quickshell player |
| `SUPER + P` | Wallpaper picker |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `ALT + Tab` | Cycle windows |
| `ALT + 1/2/3/...` | Switch workspace (QWERTY) |
| `Print` | Screenshot |
| `ALT SHIFT + S` | Region screenshot |

## Credits

Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell).

Inspired by https://github.com/flickowoa/dotfiles.git 
## License

MIT
EOF

## Star History

[![oosmetrics](https://api.oosmetrics.com/api/v1/badge/achievement/e4d18ba3-961a-444a-99fb-aff540f61553.svg)](https://oosmetrics.com/repo/samyns/Unit-3)

## Star History

<a href="https://star-history.dera.page/samyns/Unit-3">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=samyns/Unit-3&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=samyns/Unit-3" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=samyns/Unit-3" />
 </picture>
</a>
