#!/system/bin/sh
# vbmeta_spoof.sh — comprehensive VBMeta property spoofing
# Reads device identity from device.conf and applies all vbmeta/boot-state
# properties consistently. Covers verified boot, flash lock, warranty,
# dm-verity, and boot hash fields across ro.boot.* and vendor.boot.*.

SELF_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
. "$SELF_DIR/common_func.sh"
init_config

DEVICE_CONF="$CONFIG_DIR/device.conf"
LOG_TAG="TieJia-vbmeta"

# --- config reader for device.conf ---
device_get() {
    local key="$1"
    grep -E "^${key}=" "$DEVICE_CONF" 2>/dev/null | tail -1 | cut -d= -f2-
}

# --- resetprop with -n (no trigger) ---
set_prop() {
    local key="$1" val="$2"
    local cur
    cur=$(resetprop "$key" 2>/dev/null || true)
    [ "$cur" = "$val" ] && return 0
    resetprop -n "$key" "$val" 2>/dev/null
}

del_prop() {
    resetprop --delete "$1" 2>/dev/null || true
}

# ============================================================
# 1. Verified boot state (green = locked/verified)
# ============================================================
VBS=$(device_get VERIFIED_BOOT_STATE)
[ -z "$VBS" ] && VBS="green"

set_prop ro.boot.verifiedbootstate           "$VBS"
set_prop ro.boot.vbmeta.device_state         "locked"
set_prop vendor.boot.verifiedbootstate       "$VBS"
set_prop vendor.boot.vbmeta.device_state     "locked"

# ============================================================
# 2. Flash lock / bootloader lock
# ============================================================
FL=$(device_get FLASH_LOCKED)
[ -z "$FL" ] && FL="1"

set_prop ro.boot.flash.locked                "$FL"
set_prop ro.boot.realme.lockstate            "$FL"
set_prop ro.secureboot.lockstate             "locked"

# ============================================================
# 3. Warranty bit
# ============================================================
set_prop ro.boot.warranty_bit                "0"
set_prop ro.warranty_bit                     "0"

# ============================================================
# 4. dm-verity mode
# ============================================================
VM=$(device_get VERITY_MODE)
[ -z "$VM" ] && VM="enforcing"

set_prop ro.boot.veritymode                  "$VM"
set_prop vendor.boot.veritymode              "$VM"

# ============================================================
# 5. VBMeta digest — compute from block device if missing
# ============================================================
VB_DIGEST=$(resetprop ro.boot.vbmeta.digest 2>/dev/null)
# Require a 64-char SHA-256 hex digest; reject empty, all-zero, or short strings
if [ -z "$VB_DIGEST" ] || [ ${#VB_DIGEST} -ne 64 ] || echo "$VB_DIGEST" | grep -qE '^0+$'; then
    for p in /dev/block/by-name/vbmeta /dev/block/by-name/vbmeta_a /dev/block/by-name/vbmeta_b \
             /dev/block/bootdevice/by-name/vbmeta \
             /dev/block/platform/*/by-name/vbmeta \
             /dev/block/by-name/vbmeta_system_a; do
        [ -e "$p" ] && VBMETA_BLK="$p" && break
    done
    if [ -n "$VBMETA_BLK" ]; then
        VB_DIGEST=$(dd if="$VBMETA_BLK" bs=4096 count=16 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1)
        [ -n "$VB_DIGEST" ] && set_prop ro.boot.vbmeta.digest "$VB_DIGEST"
    fi
fi

# ============================================================
# 6. VBMeta header fields (from device.conf)
# ============================================================
AVB=$(device_get AVB_VERSION)
[ -n "$AVB" ] && set_prop ro.boot.vbmeta.avb_version "$AVB"

VBSIZE=$(device_get VBMETA_SIZE)
[ -n "$VBSIZE" ] && set_prop ro.boot.vbmeta.size "$VBSIZE"

CS=$(device_get CRYPTO_STATE)
[ -n "$CS" ] && set_prop ro.crypto.state "$CS"

# ============================================================
# 7. OEM unlock
# sys.oem_unlock_allowed is gated by daemon_oem_unlock_hide config
# (default 1) — see service.sh for the TEE conflict rationale.
# ro.boot.oem_unlock_supported is harmless and always set.
# ============================================================
if config_get_bool "daemon_oem_unlock_hide" 1; then
    set_prop sys.oem_unlock_allowed           "0"
fi
set_prop ro.boot.oem_unlock_supported         "0"

# ============================================================
# 8. Secure / ADB concealment
# NOTE: Also set in service.sh Phase 1 (runs earlier). Kept here as
# defensive fallback for daemon-managed hot reload scenarios where
# Phase 1 has already completed.
# ============================================================
set_prop ro.secure                            "1"
set_prop ro.adb.secure                        "1"
set_prop service.adb.root                     "0"
set_prop ro.debuggable                        "0"
set_prop ro.force.debuggable                  "0"
set_prop init.svc.adbd                        "stopped"

# ============================================================
# 9. Build type / tags hardening
# NOTE: ro.build.type/ro.build.tags are written by prop_unify.sh
# (→ pif.prop → Zygisk per-process). Skipped here to avoid duplicate
# global resetprop and reduce "property modified" detection surface.
# ============================================================

# ============================================================
# 10. Generic vbmeta integrity markers
# ============================================================
set_prop ro.boot.vbmeta.invalidate_on_error   "yes"
set_prop ro.boot.avb_version                  "${AVB:-2.0}"

# ============================================================
# 12. Scrub leaked OEM props
# ============================================================
del_prop ro.boot.oem.verifiedbootstate
del_prop ro.boot.oem.veritymode

log_save "$LOG_TAG" "vbmeta spoof applied"
