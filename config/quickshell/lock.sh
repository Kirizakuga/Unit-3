#!/usr/bin/env bash
# ── Unit-3 Lockscreen launcher ──
# Usage:
#   lock.sh         → full reveal animation (~4s startup)
#   lock.sh --fast  → instant lock with static PNG bg (~2s startup)

# Skip if lockscreen is already running
pgrep -f "lockscreen.qml" >/dev/null && exit 0

# No input method on the lockscreen: an active IME (e.g. fcitx5 Bamboo in Vietnamese mode)
# would rewrite the password as it is typed ("aa" → "â"), so unlocking would fail.
export QT_IM_MODULE=none QT_IM_MODULES=none
unset XMODIFIERS GTK_IM_MODULE

# Pass fast mode to Quickshell via environment variable
if [[ "$1" == "--fast" ]]; then
   UNIT3_LOCK_FAST=1 QT_MEDIA_BACKEND=ffmpeg qs -p ~/.config/quickshell/lock/lockscreen.qml
   else
    QT_MEDIA_BACKEND=ffmpeg qs -p ~/.config/quickshell/lock/lockscreen.qml
fi

