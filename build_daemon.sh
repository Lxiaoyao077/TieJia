#!/bin/bash
# build_daemon.sh — Cross-compile daemon_manager for all Android ABIs
# Requires: Android NDK (set ANDROID_NDK env var or edit path below)
# Output: module/bin/{arm64-v8a,armeabi-v7a,x86_64,x86}/daemon_manager

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/src/daemon_manager.c"
OUT_DIR="$SCRIPT_DIR/module/bin"

NDK="${ANDROID_NDK:-$HOME/Android/Sdk/ndk/26.3.11579264}"
CLANG_HOST="linux-x86_64"

if [ ! -x "$NDK/toolchains/llvm/prebuilt/$CLANG_HOST/bin/clang" ]; then
    echo "ERROR: NDK not found at $NDK"
    echo "Set ANDROID_NDK or edit this script."
    exit 1
fi

CC="$NDK/toolchains/llvm/prebuilt/$CLANG_HOST/bin"

declare -A ABIS=(
    ["arm64-v8a"]="aarch64-linux-android21"
    ["armeabi-v7a"]="armv7a-linux-androideabi21"
    ["x86_64"]="x86_64-linux-android21"
    ["x86"]="i686-linux-android21"
)

CFLAGS="-static -Os -flto -fdata-sections -ffunction-sections -Wl,--gc-sections -Wl,-s"

echo "Building daemon_manager for all ABIs..."
echo "Source: $SRC"
echo "NDK:    $NDK"

for abi in "${!ABIS[@]}"; do
    target="${ABIS[$abi]}"
    out="$OUT_DIR/$abi/daemon_manager"
    mkdir -p "$(dirname "$out")"

    echo "  $abi -> $out"
    "$CC/${target}-clang" $CFLAGS -o "$out" "$SRC"
done

echo ""
echo "Done. Binaries:"
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
    f="$OUT_DIR/$abi/daemon_manager"
    if [ -f "$f" ]; then
        printf "  %-12s  %s  %s\n" "$abi" "$(file "$f" | cut -d: -f2-)" "$(ls -lh "$f" | awk '{print $5}')"
    fi
done
