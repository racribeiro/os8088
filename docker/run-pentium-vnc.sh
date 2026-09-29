#!/bin/sh
# Run the 86Box Pentium profile on an isolated X display and publish it via
# VNC.  The accompanying Make target starts noVNC in a small container.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state=${PENTIUM_VNC_STATE_DIR:-/tmp/os8088-pentium-vnc}
display=${PENTIUM_VNC_DISPLAY:-:99}
vnc_port=${PENTIUM_VNC_PORT:-5901}
box=${BOX:-86Box}
rom=${BOXROM:-}
appimage_arg=
case "$box" in
    *.AppImage) appimage_arg=--appimage-extract-and-run ;;
esac

mkdir -p "$state"
runtime_vm=$(mktemp -d "$state/vm.XXXXXX")
cleanup() {
    kill "${box_pid:-}" "${launcher_pid:-}" "${vnc_pid:-}" "${xvfb_pid:-}" 2>/dev/null || true
    rm -rf "$runtime_vm"
    rm -f "$state/pentium.pid"
}
trap cleanup EXIT INT TERM

# 86Box updates a few host-specific fields in its VM configuration.  Running
# from a temporary copy keeps a development checkout clean.
cp "$root/vm/pentium/86box.cfg" "$runtime_vm/86box.cfg"
sed -i \
    -e "s|\.\./\.\./build/os8088.img|$root/build/os8088.img|" \
    -e "s|\.\./\.\./build/apps.img|$root/build/apps.img|" \
    "$runtime_vm/86box.cfg"

Xvfb "$display" -screen 0 1024x768x24 -nolisten tcp >"$state/xvfb.log" 2>&1 &
xvfb_pid=$!
display_number=${display#:}
attempt=0
while [ ! -S "/tmp/.X11-unix/X$display_number" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        echo "Xvfb did not create display $display" >&2
        exit 1
    fi
    sleep 0.1
done
x11vnc -display "$display" -localhost -forever -shared -nopw -rfbport "$vnc_port" \
    >"$state/x11vnc.log" 2>&1 &
vnc_pid=$!

if [ -n "$rom" ]; then
    DISPLAY="$display" "$box" $appimage_arg -R "$rom" -P "$runtime_vm" -N >"$state/86box.log" 2>&1 &
else
    DISPLAY="$display" "$box" $appimage_arg -P "$runtime_vm" -N >"$state/86box.log" 2>&1 &
fi
launcher_pid=$!
# AppImage launches a child process and returns straight away.  Resolve that
# child by its unique temporary VM path so the supervisor stays alive.
box_pid=
attempt=0
while [ -z "$box_pid" ] && [ "$attempt" -lt 15 ]; do
    sleep 1
    box_pid=$(pgrep -f "86Box.*-P $runtime_vm" | tail -n 1 || true)
    attempt=$((attempt + 1))
done
if [ -z "$box_pid" ]; then
    echo "86Box did not start" >&2
    exit 1
fi
printf '%s\n' "$$" >"$state/pentium.pid"
printf '%s\n' "$box_pid" >"$state/86box.pid"
while kill -0 "$box_pid" 2>/dev/null; do
    sleep 1
done
