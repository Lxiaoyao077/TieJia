#!/system/bin/sh
# Generate status.json for WebUI preload.
# Called by service.sh (hourly) and action.sh (on tap).
# Output: /data/adb/tricky_store/status.json + copy to module webroot.

MODDIR="${0%/*}"
[ -z "$MODDIR" ] && MODDIR="$PWD"
cd "$MODDIR" 2>/dev/null

CFG=/data/adb/tricky_store
OUT="$CFG/status.json"
WEBUI="$MODDIR/webroot/status.json"

# --- helpers ---
flag_on()  { [ ! -f "$1" ] && echo true || echo false; }
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
    head -c 4096 "$CFG/keybox.xml" 2>/dev/null | grep -qi -e Keybox -e AndroidAttestation && KB_SAFE=true
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
INT_SEC=$(cat "$CFG/hourly_interval_sec" 2>/dev/null)
case "$INT_SEC" in ''|*[!0-9]*) INT_SEC=3600 ;; esac
INT_MIN=$((INT_SEC / 60))
[ "$INT_MIN" -lt 1 ] && INT_MIN=60

# --- build vars ---
# Escape for JSON: \ " and control chars
json_esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\x01/\\u0001/g'; }

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
    "auto_fp": $(flag_on "$CFG/no_auto_fp"),
    "auto_keybox": $(flag_on "$CFG/no_auto_keybox"),
    "indicator": $(flag_on "$CFG/no_auto_indicator"),
    "rom_spoof_block": $(flag_on "$CFG/no_rom_spoof_block"),
    "custom_keybox": $(flag_present "$CFG/custom_keybox")
  }
}
JSONEOF

chmod 644 "$OUT" 2>/dev/null
cp -f "$OUT" "$WEBUI" 2>/dev/null
chmod 644 "$WEBUI" 2>/dev/null
