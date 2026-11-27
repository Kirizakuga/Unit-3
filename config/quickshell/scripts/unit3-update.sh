#!/usr/bin/env bash
# ── Unit-3 safe system update ──
#   unit3-update.sh           interactive update (run in a terminal; opened by the Control Center)
#   unit3-update.sh --check   print pending updates as JSON (used by the Control Center)
#
# Safety:
#   1. Shows Arch news posted since your last upgrade and stops if you don't confirm.
#   2. Takes a snapper snapshot of / first (snap-pac also snapshots every pacman run, and
#      limine-snapper-sync puts snapshots in the boot menu, so any update can be undone
#      by booting the snapshot and running `sudo snapper rollback`).
#   3. Full repo upgrade (never a partial one), then AUR; stops at the first failure.
#   4. Re-applies Unit-3 tweaks that updates can undo: Papirus folder color, Spotify theme.
#   5. Lists .pacnew config files and tells you if a reboot is needed.

if [[ "$1" == "--check" ]]; then
    repo=$(checkupdates 2>/dev/null | awk '{print $1" "$4}')
    aur=$(paru -Qua 2>/dev/null | awk '{print $1" "$4}')
    python3 -I -c '
import json, sys
repo = [l.split() for l in sys.argv[1].splitlines() if l.strip()]
aur  = [l.split() for l in sys.argv[2].splitlines() if l.strip()]
print(json.dumps({"repo": [{"name": n, "to": v} for n, v in repo],
                  "aur":  [{"name": n, "to": v} for n, v in aur]}))' "$repo" "$aur"
    exit 0
fi

ink=$'\e[38;2;200;184;154m'; dim=$'\e[38;2;122;115;88m'; red=$'\e[38;2;200;112;96m'
grn=$'\e[38;2;96;168;128m'; bold=$'\e[1m'; off=$'\e[0m'
step() { printf '\n%s%s▸ %s%s\n' "$ink" "$bold" "$1" "$off"; }
note() { printf '%s  %s%s\n' "$dim" "$1" "$off"; }
fail() { printf '\n%s%s✕ %s%s\n' "$red" "$bold" "$1" "$off"; finish 1; }
finish() {
    printf '\n%sPress Enter to close.%s' "$dim" "$off"; read -r _
    exit "${1:-0}"
}
ask() { local a; read -r -p "  $1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

# Take keyboard focus so the password prompt is ready to type into. Again after the
# Control Center has finished closing, since it holds the keyboard while it animates out.
focus_me() { hyprctl dispatch 'hl.dsp.focus({window = "class:^(unit3-update)$"})' >/dev/null 2>&1; }
focus_me; (sleep 0.6; focus_me) &

clear
printf '%s%sUNIT-3 · SYSTEM UPDATE%s\n' "$ink" "$bold" "$off"
note "Snapshot first, then repo packages, then AUR. Nothing runs without your password."

# ── 1. What's pending ──
step "Checking for updates"
repo=$(checkupdates 2>/dev/null); aur=$(paru -Qua 2>/dev/null)
[[ -z "$repo$aur" ]] && { printf '%s  Everything is up to date.%s\n' "$grn" "$off"; finish 0; }
[[ -n "$repo" ]] && { note "Repo:"; sed 's/^/    /' <<<"$repo"; }
[[ -n "$aur"  ]] && { note "AUR:";  sed 's/^/    /' <<<"$aur"; }
old_spicetify=$(pacman -Q spicetify-cli spicetify-marketplace-bin 2>/dev/null)
old_kernel=$(uname -r)

# ── 2. Arch news since the last upgrade ──
step "Arch news since your last upgrade"
news=$(paru -Pw 2>/dev/null | grep -v -i -x "no new news")
if [[ -n "$news" ]]; then
    printf '%s\n' "$news" | sed 's/^/    /'
    note "News items can mean an update needs a manual step. Read them before continuing."
    ask "Continue with the update?" || { note "Stopped. Nothing was changed."; finish 0; }
else
    note "No new news."
fi

# ── 3. Save Unit-3 customizations, then snapshot ──
KEEP="$HOME/unit3-custom/unit3-keep.sh"
if [[ -x "$KEEP" ]]; then
    step "Saving your Unit-3 customizations"
    "$KEEP" save >/dev/null 2>&1 && note "Saved to ~/unit3-custom/keep (restore any time: unit3-keep restore)."
fi

step "Taking a snapshot of / (undo point)"
sudo -v || fail "Could not get sudo."
snap=$(sudo snapper -c root create --print-number --cleanup-algorithm number \
       --description "Before Unit-3 system update") || fail "Snapshot failed, so nothing was updated."
note "Snapshot #$snap saved. To undo: reboot, pick it in the Limine menu, then run 'sudo snapper rollback'."

# ── 4. Repo packages (full upgrade, keyrings first) ──
step "Updating repo packages"
sudo pacman -Sy --needed --noconfirm archlinux-keyring cachyos-keyring >/dev/null 2>&1 || true
sudo pacman -Su || fail "pacman stopped. Your system is as it was before this step (snapshot #$snap)."

# ── 5. AUR packages ──
if [[ -n "$aur" ]]; then
    step "Updating AUR packages"
    # paru keeps going past a failed package, so don't skip the repairs below:
    # note the failure and report it at the end
    paru -Sua || aur_failed=1
fi

# ── 6. Re-apply Unit-3 tweaks ──
step "Re-applying Unit-3 tweaks"
sudo papirus-folders -C paleorange --theme Papirus-Dark >/dev/null 2>&1 && note "Folder icons: sand (paleorange)."

# Spotify: a fresh (unthemed) install still has Apps/xpui.spa; Spicetify replaces it with
# an extracted xpui/ folder. So re-theme whenever the .spa is back, whatever the version.
new_spicetify=$(pacman -Q spicetify-cli spicetify-marketplace-bin 2>/dev/null)
if [[ -f /opt/spotify/Apps/xpui.spa ]]; then
    note "Spotify is unthemed (new install or update): re-theming."
    # Spicetify only needs /opt/spotify/Apps: give that folder to you, keep /opt/spotify root-owned 755
    sudo chmod 755 /opt/spotify && sudo chown -R --no-dereference "$USER:$USER" /opt/spotify/Apps
    # the extracted folders next to fresh .spa files are Spicetify's stale copies
    for app in xpui login; do
        [[ -f /opt/spotify/Apps/$app.spa && -d /opt/spotify/Apps/$app ]] && rm -rf "/opt/spotify/Apps/$app"
    done
    if spicetify backup apply -n >/dev/null 2>&1; then
        note "Spotify theme re-applied."
    else
        printf '%s  Spotify theme could not be re-applied; run: spicetify backup apply%s\n' "$red" "$off"
    fi
elif [[ "$new_spicetify" != "$old_spicetify" ]]; then
    spicetify apply -n >/dev/null 2>&1 && note "Spicetify updated: theme refreshed."
fi

# ── 7. Config files that need a look ──
step "Config files changed by packages"
pacnew=$(pacdiff -o 2>/dev/null)
if [[ -n "$pacnew" ]]; then
    sed 's/^/    /' <<<"$pacnew"
    note "These are new default configs (.pacnew). Merge when convenient: sudo DIFFPROG=meld pacdiff"
else
    note "None."
fi

# ── 8. Did the update change any customization? ──
if [[ -x "$KEEP" ]]; then
    step "Checking your Unit-3 customizations"
    "$KEEP" check 2>&1 | grep -v -E '^.{0,20}Comparing' | sed 's/^/  /'
fi

# ── 9. Reboot needed? ──
step "Done"
if [[ -n "$aur_failed" ]]; then
    printf '%s  Some AUR packages failed to build (see above). Everything else is updated.%s\n' "$red" "$off"
    note "Build failures are often a download hiccup: open Update again to retry just those."
fi
if [[ ! -d "/usr/lib/modules/$old_kernel" ]]; then
    printf '%s  The kernel was updated: reboot soon so drivers and modules match.%s\n' "$ink" "$off"
else
    printf '%s  System updated. No reboot needed.%s\n' "$grn" "$off"
fi
note "Undo point: snapshot #$snap."
finish 0
