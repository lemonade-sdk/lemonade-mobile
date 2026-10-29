#!/bin/bash
# Renders the app's store screenshots on the macOS desktop target.
#
# Prereq: the debug .app built WITH the shot harness:
#   flutter build macos --debug --dart-define=STORE_SHOT=true
#
# The macOS app is sandboxed, so it writes inside its own container; this
# script copies the results back into assets/store_screenshots/<device>/.
#
# Usage:
#   bash tool/make_store_shots.sh                # all devices
#   bash tool/make_store_shots.sh iphone_pro_max # one device
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/macos/Build/Products/Debug/Lemonade Mobile.app/Contents/MacOS/Lemonade Mobile"
CONTAINER="$HOME/Library/Containers/com.lemonade.mobile.chat.ai/Data/assets/store_screenshots"

if [[ ! -x "$APP" ]]; then
  echo "Shot build not found. Build it first:"
  echo "  flutter build macos --debug --dart-define=STORE_SHOT=true"
  exit 1
fi

# device: pointW pointH   (pixel size = points * device dpr, see shot_mode.dart)
SCENES=(01_local_first 02_chat 03_models 04_modes 05_mesh_setup 06_mesh_settings)
run_shot () {
  local device="$1" ptw="$2" pth="$3"
  rm -rf "$CONTAINER/$device" "assets/store_screenshots/$device"
  mkdir -p "assets/store_screenshots/$device"
  for scene in "${SCENES[@]}"; do
    echo ">> $device / $scene  (${ptw}x${pth}pt)"
    SHOT_DEVICE="$device" SHOT_PT_W="$ptw" SHOT_PT_H="$pth" \
      SHOT_SCENE="$scene" SHOT_OUT="$CONTAINER/$device" \
      timeout 90 "$APP" 2>&1 | grep -E "flutter: \[|Error|error" || true
    cp "$CONTAINER/$device/$scene.png" "assets/store_screenshots/$device/" 2>/dev/null \
      || echo "   (missing $scene)"
  done
  # App Store Connect rejects any alpha channel; the frames are opaque, so
  # dropping it changes no pixel.
  for f in "assets/store_screenshots/$device"/*.png; do
    magick "$f" -alpha off "PNG24:$f"
  done
  ls -1 "assets/store_screenshots/$device/"
}

only="${1:-all}"
case "$only" in
  all|iphone_pro_max) run_shot iphone_pro_max 440 956 ;;
esac
case "$only" in
  all|iphone_6_3)     run_shot iphone_6_3 402 874 ;;
esac
case "$only" in
  all|iphone_6_5)     run_shot iphone_6_5 428 926 ;;
esac
case "$only" in
  all|ipad_pro_13)    run_shot ipad_pro_13 1376 1032 ;;
esac
case "$only" in
  all|android_phone)  run_shot android_phone 411.4286 891.4286 ;;
esac
case "$only" in
  all|android_tablet) run_shot android_tablet 1280 800 ;;
esac
echo "done -> assets/store_screenshots/"
