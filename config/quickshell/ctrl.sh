#!/usr/bin/env bash
# ── Unit-3 ControlCenter toggle ──
#   ctrl.sh [toggle|hide]   (default: toggle)
# Sends an IPC call to the running Quickshell instance; it does not spawn a new qs process.
exec qs ipc call ctrl "${1:-toggle}"
