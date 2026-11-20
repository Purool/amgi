#!/bin/bash
# Single acceptance command for every AmgiLite shard.
#
#   ./scripts/verify.sh            # build for the iOS 14 deployment target
#   ./scripts/verify.sh --test     # build + run unit tests on a simulator
#
# Shard agents must not replace this with ad-hoc xcodebuild invocations: the
# test runner in shard.toml points here.
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/share/mise/shims:$PATH"
# Tuist writes session state under ~/.local/state; keep everything inside the
# checkout so the project also verifies in sandboxed/CI runs.
export XDG_STATE_HOME="${XDG_STATE_HOME:-$PWD/.build/xdg-state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.build/xdg-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$PWD/.build/xdg-config}"
mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

DERIVED_DATA="$PWD/.build/DerivedData"
# The engine framework only ships arm64 slices. Override when a different
# simulator runtime is installed: DEVICE_MODEL="iPhone 16" ./scripts/verify.sh --test
DEVICE_MODEL="${DEVICE_MODEL:-iPhone 17}"

echo "==> tuist install"
tuist install --path .

echo "==> tuist generate"
tuist generate --path . --no-open

echo "==> build (deployment target 14.0)"
xcodebuild build \
    -workspace AmgiLite.xcworkspace \
    -scheme AmgiLite \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 \
    IPHONEOS_DEPLOYMENT_TARGET=14.0 \
    CODE_SIGNING_ALLOWED=NO

if [ "${1:-}" = "--test" ]; then
    echo "==> test (simulator: $DEVICE_MODEL)"
    xcodebuild test \
        -workspace AmgiLite.xcworkspace \
        -scheme AmgiLite \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$DEVICE_MODEL" \
        -derivedDataPath "$DERIVED_DATA" \
        ARCHS=arm64 \
        IPHONEOS_DEPLOYMENT_TARGET=14.0 \
        CODE_SIGNING_ALLOWED=NO
fi

echo "==> OK"
