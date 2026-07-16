#!/system/bin/sh
# prop_unify.sh — unify ro.product.* props with spoofed fingerprint — TieJia v2.1.0
#
# Reads device identity from device.conf (single source of truth) and applies
# all ro.product.* / ro.build.* props consistently. Also syncs to pif.prop
# so the PIF Zygisk module stays in sync.

SELF_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
. "$SELF_DIR/common_func.sh"
init_config

DEVICE_CONF="$CONFIG_DIR/device.conf"
PIF_PROP="$CONFIG_DIR/pif.prop"
LOG_TAG="TieJia-unify"

log() { log -t "$LOG_TAG" "$@"; }

# Shared helpers: device_get, set_prop, del_prop now provided by common_func.sh
# (loaded via ". $SELF_DIR/common_func.sh" above)

# Override set_prop with logging variant (this script writes verbose logs)
set_prop() {
    local key="$1" val="$2" cur
    cur=$(resetprop "$key" 2>/dev/null || true)
    [ "$cur" = "$val" ] && return 0
    resetprop -n "$key" "$val" 2>/dev/null
    log "  $key ← $val"
}

# ----- main -----

if [ ! -f "$DEVICE_CONF" ]; then
  log "device.conf not found at $DEVICE_CONF — skipping prop unification"
  exit 0
fi

log "unifying product props from $DEVICE_CONF"

# Read all fields from device.conf
MANUFACTURER=$(device_get MANUFACTURER)
BRAND=$(device_get BRAND)
MODEL=$(device_get MODEL)
DEVICE=$(device_get DEVICE)
PRODUCT=$(device_get PRODUCT)
FINGERPRINT=$(device_get FINGERPRINT)
SECURITY_PATCH=$(device_get SECURITY_PATCH)
BUILD_TYPE=$(device_get BUILD_TYPE)
BUILD_TAGS=$(device_get BUILD_TAGS)
BUILD_DESC=$(device_get BUILD_DESCRIPTION)

# Fall back to parsing fingerprint if individual fields are missing
if [ -z "$BRAND" ] || [ -z "$PRODUCT" ] || [ -z "$DEVICE" ]; then
  if [ -n "$FINGERPRINT" ] && echo "$FINGERPRINT" | grep -qE '^[^/]+/[^/]+/[^/:]+:'; then
    BRAND="${FINGERPRINT%%/*}"
    AFTER_BRAND="${FINGERPRINT#*/}"
    PRODUCT="${AFTER_BRAND%%/*}"
    AFTER_PRODUCT="${AFTER_BRAND#*/}"
    DEVICE_TMP="${AFTER_PRODUCT%%:*}"
    DEVICE="${DEVICE_TMP%%/*}"
    [ -z "$MANUFACTURER" ] && MANUFACTURER="$BRAND"
  fi
fi

[ -z "$BUILD_TYPE" ] && BUILD_TYPE="user"
[ -z "$BUILD_TAGS" ] && BUILD_TAGS="release-keys"

if [ -z "$BRAND" ] || [ -z "$PRODUCT" ] || [ -z "$DEVICE" ]; then
  log "insufficient device info — brand='$BRAND' product='$PRODUCT' device='$DEVICE'"
  exit 0
fi

log "device → brand=$BRAND product=$PRODUCT device=$DEVICE model=$MODEL"

# Apply manufacturer
[ -n "$MANUFACTURER" ] && set_prop ro.product.manufacturer "$MANUFACTURER"

# Apply brand
[ -n "$BRAND" ] && set_prop ro.product.brand "$BRAND"

# Apply product name
[ -n "$PRODUCT" ] && {
  set_prop ro.product.name "$PRODUCT"
  set_prop ro.product.device "$PRODUCT"
  set_prop ro.build.product "$PRODUCT"
}

# Apply device (if different from product)
[ -n "$DEVICE" ] && [ "$DEVICE" != "$PRODUCT" ] && {
  set_prop ro.product.device "$DEVICE"
}

# Apply model
if [ -n "$MODEL" ]; then
  set_prop ro.product.model "$MODEL"
  set_prop ro.product.system.model "$MODEL"
fi

# Apply build description
if [ -n "$BUILD_DESC" ]; then
  set_prop ro.build.description "$BUILD_DESC"
fi

# Security patch
[ -n "$SECURITY_PATCH" ] && {
  set_prop ro.build.version.security_patch "$SECURITY_PATCH"
  set_prop ro.vendor.build.security_patch "$SECURITY_PATCH"
  set_prop ro.build.version.real_security_patch "$SECURITY_PATCH"
}

# Scrub OEM-specific props
for _pfx in odm vendor product system_ext; do
  for _prop in model brand manufacturer device name; do
    del_prop "ro.product.${_pfx}.${_prop}" 2>/dev/null
  done
done

# Build tags / type
set_prop ro.build.tags "$BUILD_TAGS"
set_prop ro.build.type "$BUILD_TYPE"
set_prop ro.system.build.tags "$BUILD_TAGS"
set_prop ro.system.build.type "$BUILD_TYPE"

# Sync to pif.prop for PIF Zygisk module
if [ -d "$(dirname "$PIF_PROP")" ]; then
  {
    echo "FINGERPRINT=${FINGERPRINT}"
    [ -n "$MANUFACTURER" ]    && echo "MANUFACTURER=${MANUFACTURER}"
    [ -n "$MODEL" ]           && echo "MODEL=${MODEL}"
    [ -n "$SECURITY_PATCH" ]  && echo "SECURITY_PATCH=${SECURITY_PATCH}"
    echo "PRODUCT=${PRODUCT}"
    echo "DEVICE=${DEVICE}"
    echo "BRAND=${BRAND}"
    echo "spoofBuild=true"
    echo "spoofProps=true"
    echo "spoofProvider=false"
    echo "spoofSignature=false"
    echo "spoofVendingBuild=true"
    echo "spoofVendingSdk=false"
    echo "DEBUG=false"
  } > "$PIF_PROP"
fi

log "prop unification complete"
