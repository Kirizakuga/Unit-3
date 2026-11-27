#!/usr/bin/env bash
# ── unit3-keep: keep every Unit-3 customization safe across updates ──
#
#   unit3-keep save               copy all customized files into the saved copy (git-tracked)
#   unit3-keep check              show what differs between the system and the saved copy
#   unit3-keep restore            put the saved home files back, reload Hyprland, restart the shell
#   unit3-keep restore --system   also restore login-screen files and pacman hooks (asks for sudo)
#
# The saved copy lives in ~/unit3-custom/keep/{home,system}, mirroring real paths.
# Re-running the Unit-3 installer replaces ~/.config/{hypr,quickshell,kitty,waybar,dunst};
# afterwards run:  unit3-keep restore
# Package updates are covered by pacman hooks (folder icons, Spotify theme).

set -u
KEEP="$HOME/unit3-custom/keep"
HOME_SAVED="$KEEP/home"
SYS_SAVED="$KEEP/system"

# Home paths (relative to $HOME) that hold Unit-3 customizations.
HOME_PATHS=(
    .config/hypr
    .config/quickshell
    .config/kitty/kitty.conf
    .Xresources
    .config/kdeglobals
    .config/gtk-3.0/gtk.css
    .config/gtk-3.0/settings.ini
    .config/gtk-4.0/gtk.css
    .config/gtk-4.0/settings.ini
    .config/fontconfig/fonts.conf
    .config/mimeapps.list
    .config/spicetify/config-xpui.ini
    .config/spicetify/Themes/unit3
    .local/share/color-schemes/Unit3.colors
)
# System paths (absolute) that Unit-3 customizations live in. No package owns these.
SYS_PATHS=(
    /usr/share/sddm/themes/unit3
    /usr/share/sddm/faces/kiri.face.icon
    /usr/local/bin/unit3-avatar-sync
    /etc/systemd/system/unit3-avatar@.path
    /etc/systemd/system/unit3-avatar@.service
    /etc/sddm/Xsetup-unit3
    /etc/sddm.conf
    /etc/sddm.conf.d
    /etc/pacman.d/hooks/zz-unit3-papirus-folders.hook
    /etc/pacman.d/hooks/zz-unit3-spotify.hook
    /usr/local/bin/unit3-spotify-retheme
)
# Things that don't live in a file.
GSETTINGS=(
    "org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'"
    "org.gnome.desktop.interface icon-theme 'Papirus-Dark'"
    "org.gnome.desktop.interface color-scheme 'prefer-dark'"
    "org.gnome.desktop.interface font-name 'JetBrains Mono 10'"
    "org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 10'"
)
# Generated/cache content not worth comparing.
DIFF_EXCLUDES=(--exclude '__pycache__' --exclude '.qmlls.ini' --exclude 'user.json.tmp')

ink=$'\e[38;2;200;184;154m'; dim=$'\e[38;2;122;115;88m'; red=$'\e[38;2;200;112;96m'
grn=$'\e[38;2;96;168;128m'; off=$'\e[0m'
say()  { printf '%s%s%s\n' "$ink" "$1" "$off"; }
note() { printf '%s  %s%s\n' "$dim" "$1" "$off"; }
good() { printf '%s  ✓ %s%s\n' "$grn" "$1" "$off"; }
bad()  { printf '%s  ✕ %s%s\n' "$red" "$1" "$off"; }

copy() {   # copy <src> <dest>: an exact mirror (a directory's old extra files are removed)
    local src="$1" dest="$2" sudo_="${3:-}"
    [[ -e "$src" ]] || return 1
    $sudo_ mkdir -p "$(dirname "$dest")"
    if [[ -d "$src" ]]; then
        $sudo_ rm -rf "${dest:?}"
        $sudo_ cp -a "$src" "$dest"
    else
        $sudo_ cp -a "$src" "$dest"
    fi
}

cmd_save() {
    say "Saving Unit-3 customizations → $KEEP"
    local p
    for p in "${HOME_PATHS[@]}"; do
        copy "$HOME/$p" "$HOME_SAVED/$p" && note "$p" || bad "missing: ~/$p"
    done
    for p in "${SYS_PATHS[@]}"; do
        # only refresh system files that exist; the saved copy also carries files to install
        [[ -e "$p" ]] && copy "$p" "$SYS_SAVED$p" && note "$p"
    done
    if [[ ! -d "$KEEP/.git" ]]; then git -C "$KEEP" init -q && git -C "$KEEP" config user.name "unit3-keep" \
        && git -C "$KEEP" config user.email "unit3-keep@localhost"; fi
    git -C "$KEEP" add -A
    if git -C "$KEEP" diff --cached --quiet; then
        good "Saved (no changes since last save)."
    else
        git -C "$KEEP" commit -q -m "save $(date '+%F %T')" && good "Saved and recorded ($(git -C "$KEEP" rev-parse --short HEAD))."
    fi
}

cmd_check() {
    local drift=0 p
    say "Comparing the system with the saved copy"
    for p in "${HOME_PATHS[@]}"; do
        if [[ ! -e "$HOME/$p" ]]; then bad "~/$p is missing"; drift=1; continue; fi
        # Spicetify rewrites its [Backup] version lines on every Spotify update: not a customization
        local ign=()
        [[ "$p" == .config/spicetify/config-xpui.ini ]] && ign=(-I '^\(version\|with\) *=')
        if ! diff -r "${DIFF_EXCLUDES[@]}" "${ign[@]}" "$HOME_SAVED/$p" "$HOME/$p" >/dev/null 2>&1; then
            bad "~/$p differs"; drift=1
        fi
    done
    for p in "${SYS_PATHS[@]}"; do
        if [[ ! -e "$p" ]]; then bad "$p is missing"; drift=1
        elif ! diff -rq "$SYS_SAVED$p" "$p" >/dev/null 2>&1; then bad "$p differs"; drift=1; fi
    done
    [[ "$(readlink /usr/share/icons/Papirus-Dark/48x48/places/folder.svg)" == folder-paleorange.svg ]] \
        && good "Folder icons are sand" || { bad "Folder icons are not sand"; drift=1; }
    if [[ -f /opt/spotify/Apps/xpui.spa ]]; then bad "Spotify is unthemed"; drift=1
    elif [[ -d /opt/spotify/Apps/xpui ]]; then good "Spotify is themed"; fi
    local g
    for g in "${GSETTINGS[@]}"; do
        read -r schema key value <<<"$g"
        [[ "$(gsettings get "$schema" "$key" 2>/dev/null)" == "$value" ]] || { bad "gsettings $key is not $value"; drift=1; }
    done
    (( drift )) && note "Run 'unit3-keep restore' (or 'save' if the changes are intentional)." \
                || good "Everything matches the saved copy."
    return $drift
}

cmd_restore() {
    local system=0 p
    [[ "${1:-}" == "--system" ]] && system=1
    say "Restoring Unit-3 customizations from $KEEP"
    for p in "${HOME_PATHS[@]}"; do
        copy "$HOME_SAVED/$p" "$HOME/$p" && note "~/$p" || bad "not in saved copy: $p"
    done
    find "$HOME/.config/hypr" "$HOME/.config/quickshell" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +
    local g
    for g in "${GSETTINGS[@]}"; do
        read -r schema key value <<<"$g"
        gsettings set "$schema" "$key" "${value//\'/}"
    done
    note "gsettings: theme, icons, dark mode, fonts"
    if (( system )); then
        sudo -v || { bad "No sudo: skipped system files."; system=0; }
    fi
    if (( system )); then
        for p in "${SYS_PATHS[@]}"; do
            [[ -e "$SYS_SAVED$p" ]] || continue
            copy "$SYS_SAVED$p" "$p" sudo && sudo chown -R root:root "$p"
            note "$p"
        done
        sudo chmod 755 /usr/local/bin/unit3-spotify-retheme /etc/sddm/Xsetup-unit3
        sudo papirus-folders -C paleorange --theme Papirus-Dark >/dev/null 2>&1 && note "folder icons: sand"
        [[ -f /opt/spotify/Apps/xpui.spa ]] && sudo /usr/local/bin/unit3-spotify-retheme
        # login-screen avatar auto-sync
        if [[ -f /etc/systemd/system/unit3-avatar@.path ]]; then
            sudo systemctl daemon-reload && sudo systemctl enable --now "unit3-avatar@$USER.path" >/dev/null 2>&1 \
                && note "avatar auto-sync enabled"
        fi
    fi
    command -v hyprctl >/dev/null && hyprctl reload >/dev/null && note "Hyprland reloaded"
    hyprctl dispatch 'hl.dsp.exec_cmd("pkill -x qs; sleep 0.5; env QT_MEDIA_BACKEND=ffmpeg qs")' >/dev/null 2>&1 \
        && note "shell restarted"
    good "Restored."
    (( system )) || note "Login screen and pacman hooks were not touched; use 'restore --system' for those."
}

case "${1:-}" in
    save)    cmd_save ;;
    check)   cmd_check ;;
    restore) shift; cmd_restore "$@" ;;
    *)       sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
