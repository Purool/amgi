#!/bin/bash
# Rebuilds AnkiRustLib.xcframework for the Lite app (iOS 14, no watchOS slice).
#
# Monorepo-only helper: it compiles anki-bridge-rs + anki-upstream and copies the
# result into AmgiLite/Frameworks/, so the AmgiLite folder itself stays buildable
# after being moved out of the repository.
#
# Usage:  ./scripts/build-engine.sh [--sim-only]
set -euo pipefail

LITE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(dirname "$LITE_DIR")"
BRIDGE_DIR="$ROOT_DIR/anki-bridge-rs"
STAGE_DIR="$BRIDGE_DIR/target/xcframework-stage-ios14"
OUTPUT_DIR="$LITE_DIR/Frameworks/AnkiRustLib.xcframework"
HEADER="$BRIDGE_DIR/include/anki_bridge.h"

# The repo pins 1.92 in anki-upstream/rust-toolchain.toml; rustup may not have it
# installed. Allow any working stable toolchain to be selected explicitly.
CARGO="${CARGO:-$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin/cargo}"
# cargo must be able to spawn rustc from the same toolchain.
export PATH="$(dirname "$CARGO"):$PATH"

SIM_ONLY=0
[ "${1:-}" = "--sim-only" ] && SIM_ONLY=1

export PROTOC="${PROTOC:-$(which protoc 2>/dev/null || echo /opt/homebrew/bin/protoc)}"
export IPHONEOS_DEPLOYMENT_TARGET="14.0"

mkdir -p "$BRIDGE_DIR/target"
export DESCRIPTORS_BIN="$BRIDGE_DIR/target/anki_descriptors.bin"

# English-only i18n: ~6.8 MB of uncompressible translations the Lite app never
# shows. Idempotent — the submodule is pinned and `git submodule update` drops it.
PATCH="$ROOT_DIR/scripts/patches/anki-en-only.patch"
git -C "$ROOT_DIR/anki-upstream" apply --reverse --check "$PATCH" 2>/dev/null \
    || git -C "$ROOT_DIR/anki-upstream" apply "$PATCH"
export AMGI_EN_ONLY=1

# Dynamic framework, install name @rpath; -Wl,-x drops local symbols (~2 MB).
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-install_name,@rpath/AnkiRustLib.framework/AnkiRustLib -C link-arg=-Wl,-x"

echo "==> protoc: $PROTOC"
echo "==> cargo:  $CARGO ($("$CARGO" --version))"
echo "==> deployment target: iOS $IPHONEOS_DEPLOYMENT_TARGET"

if [ "$SIM_ONLY" -eq 0 ]; then
    echo "==> Building aarch64-apple-ios (device)..."
    "$CARGO" build --locked \
        --manifest-path "$BRIDGE_DIR/Cargo.toml" \
        --target aarch64-apple-ios \
        --release
fi

echo "==> Building aarch64-apple-ios-sim (simulator)..."
"$CARGO" build --locked \
    --manifest-path "$BRIDGE_DIR/Cargo.toml" \
    --target aarch64-apple-ios-sim \
    --release

make_framework() {
    local triple="$1" slice="$2" platform="$3" minos="$4"
    local dylib="$BRIDGE_DIR/target/$triple/release/libanki_bridge_ios.dylib"
    [ -f "$dylib" ] || { echo "ERROR: dylib not found at $dylib"; exit 1; }

    local fw="$STAGE_DIR/$slice/AnkiRustLib.framework"
    rm -rf "$fw"
    mkdir -p "$fw/Headers" "$fw/Modules"
    cp "$dylib" "$fw/AnkiRustLib"
    cp "$HEADER" "$fw/Headers/"

    cat > "$fw/Modules/module.modulemap" <<'MODULEMAP'
framework module AnkiRustLib {
    header "anki_bridge.h"
    export *
}
MODULEMAP

    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>AnkiRustLib</string>
    <key>CFBundleIdentifier</key><string>com.amgi.AnkiRustLib</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>AnkiRustLib</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
    <key>MinimumOSVersion</key><string>$minos</string>
</dict>
</plist>
PLIST

    echo "==> $slice: $(du -h "$fw/AnkiRustLib" | cut -f1)"
}

echo "==> Staging frameworks..."
rm -rf "$STAGE_DIR"
if [ "$SIM_ONLY" -eq 0 ]; then
    make_framework aarch64-apple-ios     ios-arm64           iPhoneOS        "$IPHONEOS_DEPLOYMENT_TARGET"
fi
make_framework aarch64-apple-ios-sim     ios-arm64-simulator iPhoneSimulator "$IPHONEOS_DEPLOYMENT_TARGET"

echo "==> Packaging XCFramework..."
mkdir -p "$(dirname "$OUTPUT_DIR")"
rm -rf "$OUTPUT_DIR"
if [ "$SIM_ONLY" -eq 0 ]; then
    xcodebuild -create-xcframework \
        -framework "$STAGE_DIR/ios-arm64/AnkiRustLib.framework" \
        -framework "$STAGE_DIR/ios-arm64-simulator/AnkiRustLib.framework" \
        -output "$OUTPUT_DIR"
else
    xcodebuild -create-xcframework \
        -framework "$STAGE_DIR/ios-arm64-simulator/AnkiRustLib.framework" \
        -output "$OUTPUT_DIR"
fi

# ld64 lays LC_SYMTAB's string pool out 8-byte aligned; xcodebuild repacks the
# binaries and breaks that alignment, so restore the cargo-produced dylibs.
restore_binary() {
    local triple="$1" slice="$2"
    local dylib="$BRIDGE_DIR/target/$triple/release/libanki_bridge_ios.dylib"
    local packaged="$OUTPUT_DIR/$slice/AnkiRustLib.framework/AnkiRustLib"
    [ -f "$packaged" ] || return 0
    cp "$dylib" "$packaged"
    local stroff
    stroff=$(otool -l "$packaged" | awk '/LC_SYMTAB/{f=1} f&&/stroff/{print $2; exit}')
    [ -n "$stroff" ] || { echo "ERROR: $slice: cannot parse LC_SYMTAB stroff"; exit 1; }
    if [ $((stroff % 8)) -ne 0 ]; then
        echo "ERROR: $slice: LC_SYMTAB string pool misaligned (stroff=$stroff)"; exit 1
    fi
    echo "==> $slice: stroff=$stroff (aligned)"
}

restore_binary aarch64-apple-ios     ios-arm64
restore_binary aarch64-apple-ios-sim ios-arm64-simulator

echo "==> Done: $OUTPUT_DIR"
du -sh "$OUTPUT_DIR"
