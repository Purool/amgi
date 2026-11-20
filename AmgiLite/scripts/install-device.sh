#!/bin/bash
# Builds a signed Debug build and installs it on a connected iPhone.
#
#   TEAM_ID=XXXXXXXXXX DEVICE_UDID=<udid> ./scripts/install-device.sh
#
# The deployment target stays 14.0, so this is the only way to check the parts
# the simulator cannot: WebKit's iOS 14 engine, SQLite on device, memory.
# `verify.sh` remains the acceptance command; this script is delivery only.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVICE_UDID:?set DEVICE_UDID (Xcode → Window → Devices and Simulators, or: xcrun devicectl list devices)}"
: "${TEAM_ID:?set TEAM_ID (Apple Developer team; see: security find-identity -v -p codesigning)}"

export PATH="$HOME/.local/share/mise/shims:$PATH"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$PWD/.build/xdg-state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.build/xdg-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$PWD/.build/xdg-config}"
mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

BUNDLE_ID="com.amgiapp.AmgiLite"
DERIVED_DATA="$PWD/.build/DerivedData"

echo "==> tuist generate"
tuist generate --path . --no-open > /dev/null

echo "==> build for device $DEVICE_UDID (team $TEAM_ID, target iOS 14.0)"
xcodebuild build \
    -workspace AmgiLite.xcworkspace \
    -scheme AmgiLite \
    -configuration Debug \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    IPHONEOS_DEPLOYMENT_TARGET=14.0 \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/AmgiLite.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found"; exit 1; }

echo "==> install"
# CoreDevice (devicectl) only speaks to iOS 17+. For an iOS 14 device Xcode's
# legacy install path is the one that works — open AmgiLite.xcworkspace, select
# the device and press Run if this step fails.
if xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"; then
    echo "==> launch"
    xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || true
else
    echo
    echo "devicectl could not install (expected for iOS 14 devices)."
    echo "Open AmgiLite.xcworkspace in Xcode, select the iPhone, press Run."
    echo "The signed app is at: $APP"
fi
