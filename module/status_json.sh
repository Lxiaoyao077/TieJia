#!/system/bin/sh
# Generate status.json for WebUI preload.
# Called by service.sh (hourly) and action.sh (on tap).
# Output: /data/adb/tricky_store/status.json + copy to module webroot.

MODDIR="${0%/*}"
[ -z "$MODDIR" ] && MODDIR="$PWD"
cd "$MODDIR" 2>/dev/null

# Source shared helpers (is_valid_keybox etc.)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

init_config
OUT="$CFG/status.json"
WEBUI="$MODDIR/webroot/status.json"

# --- helpers ---
flag_on()    { config_get_bool "$1" && echo true || echo false; }
flag_present() { [ -f "$1" ] && echo true || echo false; }
kb_source() {
    local nm=""
    [ -f "$CFG/.custom_keybox_name" ] && nm=$(cat "$CFG/.custom_keybox_name" 2>/dev/null)
    if [ -z "$nm" ]; then
        local meta="$CFG/.last_meta_name"
        [ -f "$meta" ] && nm=$(cat "$meta" 2>/dev/null)
    fi
    [ -z "$nm" ] && nm="keybox.xml"
    printf '%s' "$nm"
}

# --- version ---
VER=$(grep -m1 '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-)
[ -z "$VER" ] && VER="?"

# --- description prefix (🟢/🔴/🟡) ---
DESC=$(grep -m1 '^description=' "$MODDIR/module.prop" 2>/dev/null | sed -e 's/^description=//' | awk '{print $1}')
[ -z "$DESC" ] && DESC=""

# --- keybox ---
KB_SIZE=0
KB_SAFE=false
if [ -s "$CFG/keybox.xml" ]; then
    KB_SIZE=$(wc -c < "$CFG/keybox.xml" 2>/dev/null)
    is_valid_keybox "$CFG/keybox.xml" && KB_SAFE=true
fi
KB_SRC=$(kb_source)

# --- fingerprint ---
FP=""
for p in "$CFG/custom.pif.prop" "$CFG/pif.prop"; do
    [ -s "$p" ] && FP=$(grep -m1 '^FINGERPRINT=' "$p" 2>/dev/null | cut -d= -f2-) && break
done
[ -z "$FP" ] && FP=""

# --- security patch ---
SP=""
for p in "$CFG/custom.pif.prop" "$CFG/pif.prop"; do
    [ -s "$p" ] && SP=$(grep -m1 '^SECURITY_PATCH=' "$p" 2>/dev/null | cut -d= -f2-) && break
done
[ -z "$SP" ] && SP=""

# --- TEE ---
TEE=""
[ -f "$CFG/tee_status" ] && TEE=$(cat "$CFG/tee_status" 2>/dev/null)
case "$TEE" in normal|broken) ;; *) TEE="" ;; esac

TEE_TIER=""
[ -f "$CFG/tee_tier" ] && TEE_TIER=$(cat "$CFG/tee_tier" 2>/dev/null)

# --- target count ---
TGT_N=$(grep -cvE '^[[:space:]]*$' "$CFG/target.txt" 2>/dev/null)
case "$TGT_N" in ''|*[!0-9]*) TGT_N=0 ;; esac

# --- interval (minutes) ---
INT_SEC=$(config_get fp_interval 3600)
case "$INT_SEC" in ''|*[!0-9]*) INT_SEC=3600 ;; esac
INT_MIN=$((INT_SEC / 60))
[ "$INT_MIN" -lt 1 ] && INT_MIN=60

# --- build vars ---
# Escape for JSON: \ " and control chars
json_esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r//g' -e 's/$/\\n/' -e '$ s/\\n$//' -e 's/\x01/\\u0001/g'; }

cat > "$OUT" <<JSONEOF
{
  "version": "$(json_esc "$VER")",
  "description": "$(json_esc "$DESC")",
  "keybox": {
    "installed": $KB_SAFE,
    "size": $KB_SIZE,
    "source": "$(json_esc "$KB_SRC")",
    "custom": $(flag_present "$CFG/custom_keybox")
  },
  "fingerprint": "$(json_esc "$FP")",
  "security_patch": "$(json_esc "$SP")",
  "tee": "$(json_esc "$TEE")",
  "tee_tier": "$(json_esc "$TEE_TIER")",
  "target_count": $TGT_N,
  "interval_min": $INT_MIN,
  "toggles": {
    "auto_fp": $(flag_on fp_auto),
    "auto_keybox": $(flag_on kb_auto),
    "indicator": $(flag_on indicator_auto),
    "rom_spoof_block": $(flag_on rom_cleanup_auto),
    "custom_keybox": $(flag_present "$CFG/custom_keybox")
  }
}
JSONEOF

chmod 644 "$OUT" 2>/dev/null
cp -f "$OUT" "$WEBUI" 2>/dev/null
chmod 644 "$WEBUI" 2>/dev/null
