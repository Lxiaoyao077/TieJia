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

# If FINGERPRINT is set, parse it to extract brand/product/device
# Format: brand/product/device:user/release_version/id/incremental:userdebug/test-keys
# Example: google/caiman_beta/caiman:15/BP11.241121.013/13016754:user/release-keys
if [ -n "$FINGERPRINT" ]; then
  # Parse: brand / product / device:tag ...
  FP_BRAND="${FINGERPRINT%%/*}"
  AFTER_BRAND="${FINGERPRINT#*/}"      # product/device:user/...
  FP_PRODUCT="${AFTER_BRAND%%/*}"       # product (caiman_beta)
  AFTER_PRODUCT="${AFTER_BRAND#*/}"     # device:user/...
  FP_DEVICE_TMP="${AFTER_PRODUCT%%:*}"  # device (caiman or caiman_beta depending on format)
  FP_DEVICE="${FP_DEVICE_TMP%%/*}"      # strip any trailing / if present

  # Build type from fingerprint (user/userdebug/eng)
  FP_BUILD_TYPE="user"
  case "$FINGERPRINT" in
    *:userdebug/*) FP_BUILD_TYPE="userdebug" ;;
    *:eng/*)       FP_BUILD_TYPE="eng" ;;
  esac

  # If pif.prop has explicit overrides, use those
  [ -n "$DEVICE" ] && FP_DEVICE="$DEVICE"
  [ -n "$PRODUCT" ] && FP_PRODUCT="$PRODUCT"
  [ -n "$BRAND" ] && FP_BRAND="$BRAND"

  log "fingerprint → brand=$FP_BRAND product=$FP_PRODUCT device=$FP_DEVICE"

  # Apply manufacturer (from pif.prop's MANUFACTURER or fingerprint brand)
  # Do this before brand/product so manufacturer is never set to lowercase brand.
  if [ -n "$MANUFACTURER" ]; then
    set_prop ro.product.manufacturer "$MANUFACTURER"
  elif [ -n "$FP_BRAND" ]; then
    set_prop ro.product.manufacturer "$FP_BRAND"
  fi

  # Apply brand
  [ -n "$FP_BRAND" ] && {
    set_prop ro.product.brand "$FP_BRAND"
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

  # Apply build description — construct from fingerprint fields
  # Format: "product-build_type release_version id incremental build_tags"
  # Derived from: brand/product/device:build_type/release/id/incremental:userdebug/tags
  if [ -n "$FINGERPRINT" ]; then
    # Extract fields: after "device:build_type/" we have "release/id/incremental:userdebug/tags"
    AFTER_COLON="${FINGERPRINT#*:}"                              # build_type/release/id/incremental:userdebug/tags
    FP_BT="${AFTER_COLON%%/*}"                                    # build_type (user/userdebug)
    AFTER_TYPE="${AFTER_COLON#*/}"                                # release/id/incremental:userdebug/tags
    FP_RELEASE="${AFTER_TYPE%%/*}"                                # release (e.g. 15)
    AFTER_RELEASE="${AFTER_TYPE#*/}"                              # id/incremental:userdebug/tags
    FP_ID="${AFTER_RELEASE%%/*}"                                  # id (e.g. BP11.241121.013)
    AFTER_ID="${AFTER_RELEASE#*/}"                                # incremental:userdebug/tags
    FP_INCREMENTAL="${AFTER_ID%%:*}"                              # incremental (e.g. 13016754)
    REMAINDER="${AFTER_ID#*:}"                                    # userdebug/tags
    FP_TAGS="${REMAINDER#*/}"                                     # tags (release-keys)
    [ "$FP_TAGS" = "$REMAINDER" ] && FP_TAGS="${REMAINDER##*:}"  # fallback

    BUILD_DESC="${FP_PRODUCT}-${FP_BT} ${FP_RELEASE} ${FP_ID} ${FP_INCREMENTAL} ${FP_TAGS}"
    set_prop ro.build.description "$BUILD_DESC"
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

  # Build tags and type — use fingerprint-derived values
  set_prop ro.build.tags "${FP_TAGS:-release-keys}"
  set_prop ro.build.type "${FP_BUILD_TYPE:-user}"
  set_prop ro.system.build.tags "${FP_TAGS:-release-keys}"
  set_prop ro.system.build.type "${FP_BUILD_TYPE:-user}"
fi

log "prop unification complete"
