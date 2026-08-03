#!/usr/bin/env bash
# Build and install the native iOS app on a paired device.
#
#   ios/build.sh            build + install to the first paired iPhone
#   ios/build.sh --launch   ...and start it
#
# Godot emits the Xcode project only (export_project_only=true); xcodebuild is
# driven here so a signing failure is visible rather than buried in an export
# that reports "code 0" on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

# devicectl's table columns shift with the model name's width, so read the JSON
# and select on hardware type -- grepping the rendered table matches any device
# merely *named* "iPhone" and lands on the wrong column.
DEVICE="${IOS_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  JSON=$(mktemp -t devicectl)
  trap 'rm -f "$JSON"' EXIT
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  DEVICE=$(jq -r 'first(.result.devices[]
    | select(.hardwareProperties.deviceType == "iPhone")
    | select(.connectionProperties.pairingState == "paired")
    | .identifier) // empty' "$JSON")
fi
[ -z "$DEVICE" ] && { echo "no paired iPhone found (set IOS_DEVICE=<udid> to override)"; exit 1; }

rm -rf build/ios && mkdir -p build/ios
godot --headless --export-release "iOS" build/ios/elevator.xcodeproj

xcodebuild -project build/ios/elevator.xcodeproj -target elevator \
  -configuration Release -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build

xcrun devicectl device install app --device "$DEVICE" \
  build/ios/build/Release-iphoneos/elevator.app

[ "${1:-}" = "--launch" ] && xcrun devicectl device process launch \
  --device "$DEVICE" com.seanperkins.elevator
echo "done"
