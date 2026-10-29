#!/bin/bash
# Renders the App Store creative assets (product page header + search
# results) from the HTML in this folder with headless Chrome. Run
# tool/make_store_shots.sh iphone_pro_max first — the pages embed those PNGs.
#
# Specs (App Store Connect Help, "Creative assets specifications"):
#   header  21:9  3840x1646            .png/.jpg, no alpha
#   search   3:2  1920x1280..3840x2560 .png/.jpg, no alpha
#
# Usage: bash tool/store_ads/render.sh
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="../../assets/store_screenshots/app_store_ads"
mkdir -p "$OUT"

render () { # name cssW cssH
  local tmp; tmp="$(mktemp -d)"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=2 \
    --default-background-color=070B16ff --virtual-time-budget=3000 \
    --window-size="$2,$3" --screenshot="$tmp/$1.png" \
    "file://$PWD/$1.html" >/dev/null 2>&1
  # Apple rejects alpha channels: flatten through JPEG, then back to PNG.
  sips -s format jpeg -s formatOptions 100 "$tmp/$1.png" --out "$tmp/$1.jpg" >/dev/null
  sips -s format png "$tmp/$1.jpg" --out "$OUT/$1.png" >/dev/null
  rm -rf "$tmp"
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT/$1.png" | tail -3 | xargs echo "$1:"
}
render header 1920 823
render search 1920 1280
