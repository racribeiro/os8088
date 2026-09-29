#!/bin/sh
set -eu

state=${PENTIUM_VNC_STATE_DIR:-/tmp/os8088-pentium-vnc}
if [ -r "$state/pentium.pid" ]; then
    pid=$(cat "$state/pentium.pid")
    kill "$pid" 2>/dev/null || true
fi
if [ -r "$state/86box.pid" ]; then
    pid=$(cat "$state/86box.pid")
    kill "$pid" 2>/dev/null || true
fi
rm -f "$state/pentium.pid"
