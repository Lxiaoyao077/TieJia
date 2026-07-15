#!/system/bin/sh
# Boot-state property hardening — scrubs persistent properties and bootmode
# that can leak Magisk/LSPosed/hyperceiler/luckytool traces across reboots.
# Based on Specter's boot_state_props.sh, adapted for TieJia.

set -e
MODDIR="${0%/*}"
. "$MODDIR/common_func.sh"

cleaned=0

# --- 1. Bootmode spoof ---
# Some apps read ro.boot.bootmode / vendor.boot.bootmode to detect
# "recovery" or "charger" modes as a heuristic for a tampered device.
# Force them all to "normal".
for bm in ro.boot.mode ro.bootmode ro.boot.bootmode \
          vendor.boot.mode vendor.boot.bootmode; do
    cur=$(resetprop "$bm" 2>/dev/null || true)
    [ -z "$cur" ] && continue
    [ "$cur" = "normal" ] && continue
    resetprop -n "$bm" "normal"
    cleaned=$((cleaned + 1))
done

# --- 2. Persistent property scan ---
# /data/property/persistent_properties survives factory reset on some
# devices. Apps that detect LSPosed, hyperceiler, luckytool write their
# markers here — delete them so a simple prop scan comes up clean.
# Scan both filename AND content (guarding against obfuscated file names).
PERSIST_DIR="/data/property/persistent_properties"
if [ -d "$PERSIST_DIR" ]; then
    DETECT_PATTERNS="lsposed\|hyperceiler\|luckytool\|riru\|edxposed\|taichi\|dreamland"
    for f in "$PERSIST_DIR"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        # Match by filename OR content (some props use innocent names)
        if echo "$name" | grep -qi "$DETECT_PATTERNS" \
           || grep -qi "$DETECT_PATTERNS" "$f" 2>/dev/null; then
            rm -f "$f" 2>/dev/null
            cleaned=$((cleaned + 1))
        fi
    done
fi

# --- Summary ---
if [ "$cleaned" -gt 0 ]; then
    log_save "BootState" "hardened $cleaned boot-state prop(s)"
fi
unset cleaned
