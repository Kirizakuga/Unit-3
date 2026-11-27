#!/usr/bin/env bash
# Install the Unit-3 SDDM login theme and fill in what a login theme can't detect itself:
#   - your avatar (~/.face → /usr/share/sddm/faces/<user>.face.icon)
#   - the machine name shown as user@node (lock.node in quickshell settings, else the hostname)
#   - the distro and GPU line (e.g. "CACHYOS · RTX 4050")
# Run as your normal user (it asks for sudo). Avatar changes are then synced automatically
# (unit3-avatar@<user>.path); re-run only after changing the hostname, lock.node or GPU.
set -euo pipefail

SRC="$(dirname "$(readlink -f "$0")")/unit3"
DEST=/usr/share/sddm/themes/unit3
user="${SUDO_USER:-$USER}"
home="$(getent passwd "$user" | cut -d: -f6)"

# machine name: same override the lockscreen uses
node="$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1]))["lock"].get("node",""))
except Exception: print("")' "$home/.config/quickshell/settings/user.json")"

# distro + dedicated GPU (same rules as the lockscreen)
sysTag="$( { . /etc/os-release 2>/dev/null; echo "OS|${NAME:-Linux}"
            lspci -mm 2>/dev/null | awk -F'"' '$2 ~ /VGA|3D|Display/ {print "GPU|" $4 "|" $6}'; } |
python3 -I -c 'import re,sys
os_, gpus = "LINUX", []
for l in sys.stdin.read().splitlines():
    f = l.split("|")
    if f[0] == "OS": os_ = re.sub(r" Linux$", "", f[1]).upper()
    elif f[0] == "GPU": gpus.append((f[1], f[2]))
g = next((x for x in gpus if "NVIDIA" in x[0].upper()), gpus[-1] if gpus else None)
name = ""
if g:
    m = re.search(r"\[(.*)\]", g[1])
    name = re.split(r" Max-Q| /| Mobile| Laptop", re.sub(r"^GeForce ", "", m.group(1) if m else g[1]))[0].strip()
    if not m and re.search("AMD|ATI", g[0], re.I): name = "AMD " + name
    elif not m and re.search("Intel", g[0], re.I): name = "INTEL " + name
print(os_ + (" · " + name.upper() if name else ""))')"

# Only safe characters reach the root-run sed below (the settings file is user-writable)
[[ "$node" =~ ^[A-Za-z0-9._-]{1,63}$ ]] || node=""
sysTag="$(printf '%s' "$sysTag" | tr -cd 'A-Za-z0-9 ·._/+-' | cut -c1-60)"

echo "Installing $DEST  (user $user, node '${node:-<hostname>}', '$sysTag')"
sudo install -d "$DEST"
sudo cp -r "$SRC/." "$DEST/"
sudo sed -i -e "s|^node=.*|node=$node|" -e "s|^sysTag=.*|sysTag=$sysTag|" "$DEST/theme.conf"
# Avatar: a root path unit watches ~/.face and updates the login picture whenever it changes.
# The helper reads ~/.face as the user and accepts only JPEG/PNG (never follows a symlink as root).
UNITS="$(dirname "$(readlink -f "$0")")/systemd"
if [[ -d "$UNITS" ]]; then
    sudo install -m755 -o root -g root "$UNITS/unit3-avatar-sync" /usr/local/bin/unit3-avatar-sync
    sudo install -m644 -o root -g root "$UNITS/unit3-avatar@.path" "$UNITS/unit3-avatar@.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now "unit3-avatar@$user.path"
    sudo /usr/local/bin/unit3-avatar-sync "$user"
    echo "Avatar auto-sync: unit3-avatar@$user.path enabled"
fi
grep -E '^(node|sysTag)=' "$DEST/theme.conf"
