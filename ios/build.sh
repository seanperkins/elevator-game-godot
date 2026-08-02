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

DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | awk '/iPhone/ {print $(NF-3); exit}')
[ -z "$DEVICE" ] && { echo "no paired iPhone found"; exit 1; }

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
