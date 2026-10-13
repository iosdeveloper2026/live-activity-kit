#!/usr/bin/env bash
# Stage 6: real iPhone helpers. Run only when the user asks for the physical device.
#
#   device.sh status
#   device.sh install <path/to/App.app>
#   device.sh open <bundle-id>             # opens the app (saves tokens, downloads images)
#   device.sh close <AppName>              # the .app name, e.g. LiveActivityDemo
#   device.sh screenshot <out.png>         # black if the screen is off
set -euo pipefail

device=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected|available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')
state=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ {print}')

case "${1:-}" in
  status)
    echo "${state:-No physical device paired.}"
    ;;
  install|open|close|screenshot)
    [[ -n "$device" ]] || {
      echo "iPhone not reachable. Ask the user to connect it by cable, unlock it (tap Trust if asked) and keep it unlocked."
      echo "$state"; exit 3; }
    case "$1" in
      install) xcrun devicectl device install app --device "$device" "$2" 2>&1 | grep -E "App installed|ERROR" ;;
      open) xcrun devicectl device process launch --device "$device" "$2" 2>&1 | grep -E "Launched|ERROR" ;;
      close)
        pid=$(xcrun devicectl device info processes --device "$device" 2>/dev/null | grep "/$2.app/" | awk '{print $1}' | head -1)
        [[ -n "$pid" ]] && xcrun devicectl device process terminate --device "$device" --pid "$pid" >/dev/null 2>&1 && echo "Closed" || echo "Not running" ;;
      screenshot) xcrun devicectl device capture screenshot --device "$device" --destination "$2" 2>&1 | grep ERROR || echo "Saved $2" ;;
    esac
    ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
