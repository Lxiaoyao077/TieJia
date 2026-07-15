#!/system/bin/sh
# boot_hash.sh — zero-rejection boot hash priority chain for TieJia
#
# Generates a reliable device identity hash for TEE key derivation.
# Priority chain (first non-zero, non-trivial hash wins):
#   1. TEE hardware-derived hash (if TEESimulator/daemon provides one)
#   2. Partition hash composite (vbmeta + boot + dtbo)
#   3. ro.boot.serialno + ro.serialno composite (device-unique)
#   4. /data/adb/.boot_hash_fallback (persisted random, survives reboots)
#
# Invariant: NEVER writes all-zero hash. The daemon rejects zero
# hashes to prevent key derivation from identical material on every device.
#
# Exit 0: hash written to boot_hash.bin
# Exit 1: all sources exhausted (should not happen with fallback)

CONFIG_DIR=/data/adb/tricky_store
OUT="$CONFIG_DIR/boot_hash.bin"
SHA256="sha256sum"
for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
  [ -x "$bb" ] && SHA256="$bb sha256sum" && break
done

log() { echo "boot_hash: $*"; }
is_zero() { [ -z "$1" ] || echo "$1" | grep -qE '^0+$'; }

# Generate output if hash is non-trivial (not empty, not all zeros)
emit_if_valid() {
  local src="$1" hash="$2"
  if [ -n "$hash" ] && ! is_zero "$hash"; then
    printf '%s' "$hash" > "$OUT"
    chmod 600 "$OUT"
    log "generated from $src: ${hash:0:16}..."
    return 0
  fi
  return 1
}

# --- Level 1: TEE-derived hash ---
# If the TEE simulator / daemon already produced a boot hash, use it.
# The file is written by the daemon during its init sequence.
if [ -s "$CONFIG_DIR/.tee_boot_hash" ]; then
  TEE_HASH=$(tr -d '\n' < "$CONFIG_DIR/.tee_boot_hash" 2>/dev/null)
  emit_if_valid "TEE" "$TEE_HASH" && exit 0
fi

# --- Level 2: Partition hash composite ---
# Hash vbmeta (or vbmeta_a), boot (or boot_a), and dtbo (or dtbo_a).
# This is a strong device fingerprint — changing any of these partitions
# (OTA, custom ROM flash) changes the hash, which is desirable because
# the keybox auth state should reset after a system update.
COMPOSITE=""
for part in \
  /dev/block/by-name/vbmeta /dev/block/by-name/vbmeta_a \
  /dev/block/by-name/boot /dev/block/by-name/boot_a \
  /dev/block/by-name/dtbo /dev/block/by-name/dtbo_a \
  /dev/block/bootdevice/by-name/vbmeta /dev/block/bootdevice/by-name/vbmeta_a; do
  if [ -r "$part" ]; then
    H=$(dd if="$part" bs=4096 count=16 2>/dev/null | $SHA256 2>/dev/null | awk '{print tolower($1)}')
    [ -n "$H" ] && COMPOSITE="${COMPOSITE}${H:0:8}"
    [ ${#COMPOSITE} -ge 64 ] && break
  fi
done

if [ -n "$COMPOSITE" ] && [ ${#COMPOSITE} -ge 16 ]; then
  FINAL=$(printf '%s' "$COMPOSITE" | $SHA256 | awk '{print tolower($1)}')
  emit_if_valid "partitions" "$FINAL" && exit 0
fi

# --- Level 3: Serial number composite ---
# Fall back to device serial numbers. Less unique than partition hashes
# but still provides per-device entropy.
SERIAL=""
for prop in ro.boot.serialno ro.serialno ro.boot.hardware.serial; do
  V=$(getprop "$prop" 2>/dev/null)
  [ -n "$V" ] && SERIAL="${SERIAL}${V}"
done
if [ -n "$SERIAL" ]; then
  FINAL=$(printf '%s' "$SERIAL" | $SHA256 | awk '{print tolower($1)}')
  emit_if_valid "serialno" "$FINAL" && exit 0
fi

# --- Level 4: Persisted fallback ---
# Generate once, persist across reboots. Not ideal (survives factory reset
# if module is reinstalled), but better than a zero hash which would cause
# identical key derivation on every device.
FALLBACK="$CONFIG_DIR/.boot_hash_fallback"
if [ -s "$FALLBACK" ]; then
  FALLBACK_HASH=$(tr -d '\n' < "$FALLBACK" 2>/dev/null)
  emit_if_valid "fallback" "$FALLBACK_HASH" && exit 0
fi

# Generate a new random fallback if none exists
RANDOM_HASH=$(head -c 32 /dev/urandom 2>/dev/null | $SHA256 | awk '{print tolower($1)}')
if [ -n "$RANDOM_HASH" ]; then
  printf '%s' "$RANDOM_HASH" > "$FALLBACK"
  chmod 600 "$FALLBACK"
  emit_if_valid "fallback(generated)" "$RANDOM_HASH" && exit 0
fi

log "FATAL: all hash sources exhausted"
exit 1
