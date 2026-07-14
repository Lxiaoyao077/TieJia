#!/system/bin/sh
# prop_unify.sh — unify ro.product.* props with spoofed fingerprint
#
# When autopif.sh changes ro.build.fingerprint to a Pixel Canary value,
# the ro.product.* family (ro.product.manufacturer, ro.product.model,
# ro.product.name, ro.product.device, ro.product.brand) remains as the
# real device values. This creates a cross-validation gap — banking apps
# that compare fingerprint manufacturer/model against product props
# can detect the mismatch.
#
# This script reads the spoofed fingerprint from pif.prop and updates
# all ro.product.* props to match.

MODDIR="${MODPATH:-$(dirname "$0")}"
CFG=/data/adb/tricky_store
PIF="$CFG/pif.prop"
LOG_TAG="AlwaysStrong-unify"

log() { log -t "$LOG_TAG" "$@"; }

# Resetprop helpers — use '-n' to avoid triggering property triggers
set_prop() {
  local key="$1" val="$2"
  local cur
  cur=$(resetprop "$key" 2>/dev/null)
  [ "$cur" = "$val" ] && return 0
  resetprop -n "$key" "$val" 2>/dev/null
  log "  $key ← $val"
}

del_prop() {
  resetprop --delete "$1" 2>/dev/null
}

# ----- main -----

if [ ! -f "$PIF" ]; then
  log "pif.prop not found at $PIF — skipping prop unification"
  exit 0
fi

log "unifying product props from $PIF"

# Parse pif.prop for FINGERPRINT and PRODUCT fields
FINGERPRINT=""
PRODUCT=""
DEVICE=""
MANUFACTURER=""
BRAND=""
MODEL=""
SECURITY_PATCH=""

while IFS='=' read -r key val; do
  case "$key" in
    FINGERPRINT)     FINGERPRINT="$val" ;;
    PRODUCT)         PRODUCT="$val" ;;
    DEVICE)          DEVICE="$val" ;;
    MANUFACTURER)    MANUFACTURER="$val" ;;
    BRAND)           BRAND="$val" ;;
    MODEL)           MODEL="$val" ;;
    SECURITY_PATCH)  SECURITY_PATCH="$val" ;;
  esac
done < "$PIF"

# If FINGERPRINT is set, parse it to extract brand/product/device/model
# Format: brand/product:user/release/ID/incremental:userdebug/test-keys
# Example: google/caiman_beta/caiman:15/BP11.241121.013/13016754:user/release-keys
if [ -n "$FINGERPRINT" ]; then
  # Extract brand/product from fingerprint (before the first /)
  FP_BRAND="${FINGERPRINT%%/*}"
  FP_REST="${FINGERPRINT#*/}"
  FP_PRODUCT="${FP_REST%%/*}"
  FP_REST="${FP_REST#*/}"
  FP_REST="${FP_REST#*:}"       # skip "shiba:user"
  FP_DEVICE="${FP_REST%%/*}"    # device is between the two slashes after :
  # Actually fingerprint format: brand/product:user/release/ID/incremental:userdebug/test-keys
  # Let's parse more carefully
  FP_BRAND="${FINGERPRINT%%/*}"
  AFTER_BRAND="${FINGERPRINT#*/}"
  FP_PRODUCT="${AFTER_BRAND%%/*}"

  # Device is the first part after the first colon — after ":user/" or ":userdebug/"
  # fingerprint = brand/product:user/release/ID/incremental:userdebug/test-keys
  # The device is the next segment after PRODUCT
  # Actually: brand/product/device:user/...
  # Let's re-parse: brand/product_name:user_or_userdebug
  AFTER_SLASH="${FINGERPRINT#*/}"     # product/device:user/release...
  FP_PRODUCT="${AFTER_SLASH%%/*}"     # product_name (before /)
  AFTER_PRODUCT="${AFTER_SLASH#*/}"   # device:user/release...
  # device is everything before the first colon in AFTER_PRODUCT
  # But for Pixel: "caiman:user/..." or "caiman_beta:user/..."
  FP_DEVICE_TMP="${AFTER_PRODUCT%%:*}"
  FP_DEVICE="${FP_DEVICE_TMP%%/*}"   # in case there's a / in device name

  # The actual device might have variant suffix — use what pif says
  # For Pixel fingerprint, the device in "product/device:user/..." is the codename
  # Fall back to explicit DEVICE from pif.prop if available
  [ -n "$DEVICE" ] && FP_DEVICE="$DEVICE"
  [ -n "$PRODUCT" ] && FP_PRODUCT="$PRODUCT"
  [ -n "$BRAND" ] && FP_BRAND="$BRAND"

  log "fingerprint → brand=$FP_BRAND product=$FP_PRODUCT device=$FP_DEVICE"

  # Apply brand
  [ -n "$FP_BRAND" ] && {
    set_prop ro.product.brand "$FP_BRAND"
    set_prop ro.product.manufacturer "$FP_BRAND"  # many OEMs set these equal
  }

  # Apply product name
  [ -n "$FP_PRODUCT" ] && {
    set_prop ro.product.name "$FP_PRODUCT"
    set_prop ro.product.device "$FP_PRODUCT"
    set_prop ro.build.product "$FP_PRODUCT"
  }

  # Apply device (if different from product)
  [ -n "$FP_DEVICE" ] && [ "$FP_DEVICE" != "$FP_PRODUCT" ] && {
    set_prop ro.product.device "$FP_DEVICE"
  }

  # Apply model — use explicit MODEL from pif or derive from product
  if [ -n "$MODEL" ]; then
    set_prop ro.product.model "$MODEL"
    set_prop ro.product.system.model "$MODEL"
  fi

  # Apply manufacturer
  if [ -n "$MANUFACTURER" ]; then
    set_prop ro.product.manufacturer "$MANUFACTURER"
  fi

  # Apply build description (construct from fingerprint)
  if [ -n "$FINGERPRINT" ]; then
    # Extract build description: everything after the first colon?
    # Description format: "caiman-user 15 BP11.241121.013 13016754 release-keys"
    AFTER_COLON="${FINGERPRINT#*:}"
    DEVICE_PART="${FINGERPRINT%%/*}"
    # Actually: brand/product/device:user/release/ID/incremental:userdebug/test-keys
    # for description, remove :user/... part
    set_prop ro.build.description "${FINGERPRINT%%:*}"
  fi

  # Security patch
  [ -n "$SECURITY_PATCH" ] && {
    set_prop ro.build.version.security_patch "$SECURITY_PATCH"
    set_prop ro.vendor.build.security_patch "$SECURITY_PATCH"
    set_prop ro.build.version.real_security_patch "$SECURITY_PATCH"
  }

  # Scrub any OEM-specific props that would leak real device
  del_prop ro.product.odm.model 2>/dev/null
  del_prop ro.product.odm.brand 2>/dev/null
  del_prop ro.product.odm.manufacturer 2>/dev/null
  del_prop ro.product.odm.device 2>/dev/null
  del_prop ro.product.odm.name 2>/dev/null
  del_prop ro.product.vendor.model 2>/dev/null
  del_prop ro.product.vendor.brand 2>/dev/null
  del_prop ro.product.vendor.manufacturer 2>/dev/null
  del_prop ro.product.vendor.device 2>/dev/null
  del_prop ro.product.vendor.name 2>/dev/null
  del_prop ro.product.product.model 2>/dev/null
  del_prop ro.product.product.brand 2>/dev/null
  del_prop ro.product.product.manufacturer 2>/dev/null
  del_prop ro.product.product.device 2>/dev/null
  del_prop ro.product.product.name 2>/dev/null
  del_prop ro.product.system_ext.model 2>/dev/null
  del_prop ro.product.system_ext.brand 2>/dev/null
  del_prop ro.product.system_ext.manufacturer 2>/dev/null
  del_prop ro.product.system_ext.device 2>/dev/null
  del_prop ro.product.system_ext.name 2>/dev/null

  # Build tags and type
  set_prop ro.build.tags "release-keys"
  set_prop ro.build.type "user"
  set_prop ro.system.build.tags "release-keys"
  set_prop ro.system.build.type "user"
fi

log "prop unification complete"
