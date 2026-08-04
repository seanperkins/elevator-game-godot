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

# Read the bundle id from export_presets.cfg rather than hardcoding it. A
# hardcoded one silently relaunches the PREVIOUS app after a rename: the
# install goes to the new bundle, the launch goes to the old one, and you sit
# there screenshotting a build you did not just make.
BUNDLE=$(sed -n 's/^application\/bundle_identifier="\(.*\)"$/\1/p' export_presets.cfg | head -1)
[ -z "$BUNDLE" ] && { echo "no bundle_identifier in export_presets.cfg"; exit 1; }
echo "bundle: $BUNDLE"

if [ "${1:-}" = "--launch" ]; then
  # A locked phone refuses the launch (FBSOpenApplicationErrorDomain 7) even
  # though the install succeeded, so say which it was.
  if ! xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"; then
    # The install succeeded and the launch did not -- a locked phone refuses it
    # with FBSOpenApplicationErrorDomain 7. Say so on stderr and exit non-zero:
    # a caller cannot otherwise tell "installed and launched" from "installed".
    echo "installed, but could not launch -- is the phone unlocked?" >&2
    exit 3
  fi
fi
echo "done"
