#===========================================================================
# TieJia v2.0.0 — Shared helper library (common_func.sh)
#===========================================================================
# Merged from PlayIntegrityFix v4.7-inject-s (download/download_fail/sleep_pause)
# and TieJia enhancements.
# v2.0.0 adds: init_config, require_root, config_get/set, log helpers.

# === Global constants ===
export TIEJIA_CONFIG_DIR=/data/adb/tricky_store
export TIEJIA_VERSION=2.1.4
export TIEJIA_VERSION_CODE=214

# === PIF spoof settings (single source of truth) ===
# Default set applied to every pif.prop (custom or shipped) before
# Zygisk per-process injection. Tuned for minimum detection surface:
# spoofProvider/Signature/VendingSdk off (high false-positive risk),
# spoofBuild/Props/VendingFinger on (required for DEVICE verdict).
export SPOOF_SETTINGS="spoofProvider=0 spoofVendingFinger=1 spoofBuild=1 spoofProps=1 spoofSignature=0 spoofVendingSdk=0"

# === Portable lowercase (busybox awk lacks tolower) ===
# lowercase <string> — echoes lowercase version using tr.
# Falls back to sed if tr -dc causes issues on toybox.
lowercase() {
  local _s="$1"
  if echo A | tr 'A-Z' 'a-z' >/dev/null 2>&1; then
    echo "$_s" | tr 'A-Z' 'a-z'
  else
    echo "$_s" | sed 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/'
  fi
}

# === ABI detection ===
# detect_abi — sets global ABI_DIR (arm64-v8a / armeabi-v7a / x86_64 / x86) and
# ABI_BIN_DIR=$MODDIR/bin/$ABI_DIR. Returns 0 on ARM, 1 on others.
detect_abi() {
  case "$(uname -m)" in
    aarch64)       ABI_DIR=arm64-v8a ;;
    armv7*|armv8l) ABI_DIR=armeabi-v7a ;;
    x86_64)        ABI_DIR=x86_64 ;;
    i?86)          ABI_DIR=x86 ;;
    *)             ABI_DIR="" ;;
  esac
  ABI_BIN_DIR="${MODDIR:-$MODPATH}/bin/$ABI_DIR"
  case "$ABI_DIR" in arm64-v8a|armeabi-v7a) return 0 ;; *) return 1 ;; esac
}

# === Unified busybox finder ===
# find_busybox — sets global BB to the first working busybox path.
# Searches: busybox-ndk > magisk > ksu > apatch.
find_busybox() {
  [ -n "${BB:-}" ] && return 0
  for _p in /data/adb/modules/busybox-ndk/system/*/busybox \
            /data/adb/magisk/busybox /data/adb/ksu/bin/busybox \
            /data/adb/ap/bin/busybox; do
    [ -f "$_p" ] && BB="$_p" && return 0
  done
  return 1
}

# === Unified URL fetcher ===
# fetch_url <output_file> <url> [referer] [timeout_sec]
# Tries engines in priority: asfetch → curl → wget → busybox wget.
# Respects http_proxy/ALL_PROXY env vars. Returns 0 on success.
fetch_url() {
  _fo="$1"; _fu="$2"; _fref="${3:-}"; _fto="${4:-15}"
  rm -f "$_fo"

  # asfetch (native TLS, no proxy) — skip if proxy is active
  if [ -z "${http_proxy:-}${ALL_PROXY:-}" ] && [ -n "${ABI_DIR:-}" ] \
     && [ -x "${ABI_BIN_DIR:-}/asfetch" ]; then
    if [ -n "$_fref" ]; then
      "${ABI_BIN_DIR}/asfetch" -T "$_fto" -H "Referer: $_fref" -o "$_fo" "$_fu" 2>/dev/null
    else
      "${ABI_BIN_DIR}/asfetch" -T "$_fto" -o "$_fo" "$_fu" 2>/dev/null
    fi
    [ -s "$_fo" ] && return 0
  fi

  # curl
  if command -v curl >/dev/null 2>&1; then
    rm -f "$_fo"
    if [ -n "$_fref" ]; then
      curl -fsSL --max-time "$_fto" -e "$_fref" -o "$_fo" "$_fu" 2>/dev/null
    else
      curl -fsSL --max-time "$_fto" -o "$_fo" "$_fu" 2>/dev/null
    fi
    [ -s "$_fo" ] && return 0
  fi

  # system wget
  if command -v wget >/dev/null 2>&1; then
    rm -f "$_fo"
    if [ -n "$_fref" ]; then
      wget -q -T "$_fto" --header "Referer: $_fref" -O "$_fo" "$_fu" 2>/dev/null
    else
      wget -q -T "$_fto" -O "$_fo" "$_fu" 2>/dev/null
    fi
    [ -s "$_fo" ] && return 0
  fi

  # busybox wget
  if find_busybox; then
    rm -f "$_fo"
    if [ -n "$_fref" ]; then
      "$BB" wget -q -T "$_fto" --header "Referer: $_fref" --no-check-certificate -O "$_fo" "$_fu" 2>/dev/null
    else
      "$BB" wget -q -T "$_fto" --no-check-certificate -O "$_fo" "$_fu" 2>/dev/null
    fi
    [ -s "$_fo" ] && return 0
  fi
  return 1
}

# === Portable trailing newline guard ===
# ensure_trailing_newline <file> — appends \n if missing. No od dependency.
ensure_trailing_newline() {
  local _f="$1"
  [ -s "$_f" ] || return 0
  # Read last byte: if not 0x0a, append newline
  local _last
  _last=$(tail -c1 "$_f" 2>/dev/null | tr '\n' 'X')
  [ "$_last" != "X" ] && printf '\n' >> "$_f"
}

# delprop_if_exist <prop name>
delprop_if_exist() {
    local NAME="$1"
    [ -n "$(resetprop "$NAME")" ] && resetprop --delete "$NAME"
}

RESETPROP="resetprop -n"
[ -f /data/adb/magisk/util_functions.sh ] && [ "$(grep MAGISK_VER_CODE /data/adb/magisk/util_functions.sh | cut -d= -f2)" -lt 27003 ] && RESETPROP=resetprop_hexpatch

# resetprop_hexpatch [-f|--force] <prop name> <new value>
resetprop_hexpatch() {
    case "$1" in
        -f|--force) local FORCE=1; shift;;
    esac

    local NAME="$1"
    local NEWVALUE="$2"
    local CURVALUE
    CURVALUE="$(resetprop "$NAME")"

    [ ! "$NEWVALUE" -o ! "$CURVALUE" ] && return 1
    [ "$NEWVALUE" = "$CURVALUE" -a ! "$FORCE" ] && return 2

    local NEWLEN=${#NEWVALUE}
    if [ -f /dev/__properties__ ]; then
        local PROPFILE=/dev/__properties__
    else
        local PROPFILE="/dev/__properties__/$(resetprop -Z "$NAME")"
    fi
    [ ! -f "$PROPFILE" ] && return 3
    local NAMEOFFSET
    NAMEOFFSET=$(echo $(strings -t d "$PROPFILE" | grep "$NAME") | cut -d\  -f1)

    local NEWHEX="$(printf '%02x' "$NEWLEN")$(printf "$NEWVALUE" | od -A n -t x1 -v | tr -d ' \n')$(printf "%$((92-NEWLEN))s" | sed 's/ /00/g')"

    printf "Patch '$NAME' to '$NEWVALUE' in '$PROPFILE' @ 0x%08x -> \n[0000??$NEWHEX]\n" $((NAMEOFFSET-96))

    echo -ne "\x00\x00" \
        | dd obs=1 count=2 seek=$((NAMEOFFSET-96)) conv=notrunc of="$PROPFILE"
    echo -ne "$(printf "$NEWHEX" | sed -e 's/.\{2\}/&\\x/g' -e 's/^/\\x/' -e 's/\\x$//')" \
        | dd obs=1 count=93 seek=$((NAMEOFFSET-93)) conv=notrunc of="$PROPFILE"
}

# resetprop_if_diff <prop name> <expected value>
resetprop_if_diff() {
    local NAME="$1"
    local EXPECTED="$2"
    local CURRENT
    CURRENT="$(resetprop "$NAME")"
    [ -z "$CURRENT" ] || [ "$CURRENT" = "$EXPECTED" ] || $RESETPROP "$NAME" "$EXPECTED"
}

# resetprop_if_match <prop name> <value match string> <new value>
resetprop_if_match() {
    local NAME="$1"
    local CONTAINS="$2"
    local VALUE="$3"
    [[ "$(resetprop "$NAME")" = *"$CONTAINS"* ]] && $RESETPROP "$NAME" "$VALUE"
}

# stub for boot-time
if [ "$(getprop sys.boot_completed)" != "1" ]; then
    ui_print() { return; }
fi

# --- TieJia: load_proxy ---
# Reads config/proxy.conf and exports http_proxy / https_proxy env vars.
# Call this before any network fetch if you need proxy support.
load_proxy() {
    local cf="${MODDIR:-$MODPATH}/config/proxy.conf"
    [ -f "$cf" ] || return 1
    local host port auth
    host=$(grep -E '^PROXY_HOST=' "$cf" 2>/dev/null | cut -d= -f2-)
    port=$(grep -E '^PROXY_PORT=' "$cf" 2>/dev/null | cut -d= -f2-)
    auth=$(grep -E '^PROXY_AUTH=' "$cf" 2>/dev/null | cut -d= -f2-)
    [ -z "$host" ] || [ -z "$port" ] && return 1
    if [ -n "$auth" ]; then
        export http_proxy="http://${auth}@${host}:${port}"
        export https_proxy="http://${auth}@${host}:${port}"
    else
        export http_proxy="http://${host}:${port}"
        export https_proxy="http://${host}:${port}"
    fi
    return 0
}

# --- PIF: sleep_pause / download_fail / download (from v4.7-inject-s) ---
sleep_pause() {
    # APatch and KernelSU needs this
    # but not KSU_NEXT, MMRL
    if [ -z "$MMRL" ] && [ -z "$KSU_NEXT" ] && { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; }; then
        sleep 5
    fi
}

download_fail() {
    dl_domain=$(echo "$1" | awk -F[/:] '{print $4}')
    # Clean up on download fail
    rm -rf "$TEMPDIR"
    ping -c 1 -W 20 "$dl_domain" > /dev/null 2>&1 || {
        echo "[!] Unable to connect to $dl_domain, please check your internet connection and try again"
        sleep_pause
        exit 1
    }
    conflict_module=$(ls /data/adb/modules | grep busybox)
    for i in $conflict_module; do
        echo "[!] Please remove $i and try again."
    done
    echo "[!] download failed!"
    echo "[x] bailing out!"
    sleep_pause
    exit 1
}

download() { load_proxy; busybox wget -T 10 --no-check-certificate -qO - "$1" > "$2" || download_fail "$1"; }
if command -v curl > /dev/null 2>&1; then
    download() { load_proxy; curl --connect-timeout 10 -s "$1" > "$2" || download_fail "$1"; }
fi

# --- TieJia: find_tool ---
# find_tool <cmd> <subcmd> <test_expr>
# Searches for a CLI tool (command or busybox subcommand).
#   $1 — command name (e.g. "base64" / "sha256sum")
#   $2 — busybox subcommand (same as $1 when cmd==subcmd)
#   $3 — test expression piped to the tool (e.g. "echo dGVzdA==")
# Prints the full invocation prefix (e.g. "base64 -d" or "/data/adb/magisk/busybox sha256sum")
# Returns 0 on success, 1 if not found.
find_tool() {
    local cmd="$1" sub="$2" test_expr="${3:-}"
    # System tool
    if [ -n "$test_expr" ]; then
        if printf '%s' "$test_expr" | $cmd >/dev/null 2>&1; then
            printf '%s' "$cmd"; return 0
        fi
    elif command -v "$cmd" >/dev/null 2>&1; then
        printf '%s' "$cmd"; return 0
    fi
    # Busybox fallback
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ]; then
            if [ -n "$test_expr" ]; then
                if printf '%s' "$test_expr" | "$bb" $sub >/dev/null 2>&1; then
                    printf '%s %s' "$bb" "$sub"; return 0
                fi
            else
                printf '%s %s' "$bb" "$sub"; return 0
            fi
        fi
    done
    return 1
}

# --- TieJia: find_sed (portable sed -i) ---
# Resolves a sed binary with reliable -i support.
# toybox sed (AOSP default) lacks -i; busybox sed always supports it.
# Sets global $SED to e.g. "sed -i" or "/data/adb/magisk/busybox sed -i".
find_sed() {
  SED="sed -i"
  for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    if [ -x "$bb" ]; then SED="$bb sed -i"; return 0; fi
  done
  return 1
}

# --- TieJia: verify_proc_name (PID reuse guard) ---
# verify_proc_name <pid> <proc_name_pattern>
# Returns 0 if /proc/<pid>/cmdline contains <proc_name_pattern>, 1 otherwise.
# Prevents acting on stale PIDs where a different process reused the same PID
# after the original process died. kill -0 on PID N may succeed for a freshly
# spawned unrelated process, leading to killing/writing the wrong target.
verify_proc_name() {
    local pid="$1" pat="$2"
    [ -z "$pid" ] || [ -z "$pat" ] && return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    [ -z "$cmdline" ] && return 1
    case "$cmdline" in
        *"$pat"*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- TieJia: verify_proc_name ---
#--- TieJia: is_valid_keybox ---
# is_valid_keybox <path> — returns 0 if file looks like a valid keybox XML
is_valid_keybox() {
    local kbf="${1:-/data/adb/tricky_store/keybox.xml}"
    [ -s "$kbf" ] || return 1
    head -c 4096 "$kbf" 2>/dev/null | grep -qi -e 'Keybox' -e 'AndroidAttestation'
}

# --- TieJia: log_save ---
# Private log fallback: persist.log.tag.* may suppress logd output,
# so we tee to $MODDIR/logs/module.log with restricted permissions.
# Usage: log_save <tag> <message...>
log_save() {
  local tag="$1"; shift
  local msg="$*"
  local logf="${MODDIR:-$MODPATH}/logs/module.log"
  local ts

  mkdir -p "${MODDIR:-$MODPATH}/logs" 2>/dev/null

  ts=$(date '+%m-%d %H:%M:%S' 2>/dev/null)
  (
    umask 077
    echo "[$ts] $msg" >> "$logf" 2>/dev/null
    # Rotate only when > 300 lines to avoid per-call overhead
    if [ "$(wc -l < "$logf" 2>/dev/null)" -gt 300 ]; then
      tail -n 200 "$logf" > "$logf.tmp" 2>/dev/null && mv -f "$logf.tmp" "$logf" 2>/dev/null
    fi
  )
  # Also send to logd (may be suppressed)
  echo "$msg" | log -t "$tag" 2>/dev/null
}

#===========================================================================
# TieJia v2.0.0 — Phase E: Shared library convergence
#===========================================================================

# --- init_config ---
# Unifies CONFIG_DIR across all scripts. Must be called after MODDIR/MODPATH
# is available. Sets: CONFIG_DIR, CONFIG_FILE (the unified config).
init_config() {
  export CONFIG_DIR="${TIEJIA_CONFIG_DIR:-/data/adb/tricky_store}"
  export CONFIG_FILE="$CONFIG_DIR/config"
  export CFG="$CONFIG_DIR"  # backward-compat shorthand
  mkdir -p "$CONFIG_DIR" 2>/dev/null
}

# --- require_root ---
# Bail with error if not running as root.
require_root() {
  [ "$(id -u)" = "0" ] && return 0
  echo "TieJia: root required" >&2
  exit 1
}

# --- ensure_dir ---
# Create directory (and parents) if missing.
ensure_dir() { [ -d "$1" ] || mkdir -p "$1" 2>/dev/null; }

#===========================================================================
# TieJia v2.1.0 — device.conf helpers (single source of truth)
#===========================================================================

# device_get <key> — read a value from $CONFIG_DIR/device.conf
device_get() {
    local key="$1"
    grep -E "^${key}=" "$CONFIG_DIR/device.conf" 2>/dev/null | tail -1 | cut -d= -f2-
}

# set_prop <key> <value> — idempotent resetprop -n (no property trigger)
set_prop() {
    local key="$1" val="$2" cur
    cur=$(resetprop "$key" 2>/dev/null || true)
    [ "$cur" = "$val" ] && return 0
    resetprop -n "$key" "$val" 2>/dev/null
}

# del_prop <key> — delete a property if it exists
del_prop() {
    resetprop --delete "$1" 2>/dev/null || true
}

# sed_inplace <sed_expression> <file> — portable in-place sed
# Falls back to grep -v + mv when toybox sed lacks -i support.
sed_inplace() {
    local expr="$1" file="$2"
    if [ -n "${SED:-}" ]; then
        $SED "$expr" "$file" 2>/dev/null && return 0
    fi
    # toybox sed fallback: extract key, remove old line, append new
    local k
    k=$(echo "$expr" | sed 's|s/\^\([^=]*\)=.*|\1|' 2>/dev/null)
    [ -z "$k" ] && return 1
    grep -vE "^${k}=" "$file" > "${file}.tmp" 2>/dev/null
    printf '%s\n' "$(echo "$expr" | sed 's|s/\^\([^=]*\)=\(.*\)/|\1=\2|' 2>/dev/null)" >> "${file}.tmp"
    mv -f "${file}.tmp" "$file" 2>/dev/null
}

# --- version_from_module_prop ---
# Reads versionCode from $MODDIR/module.prop or $1. Echoes it, returns 0.
version_from_module_prop() {
  local mp="${1:-${MODDIR:-$MODPATH}/module.prop}"
  [ -f "$mp" ] || return 1
  grep -E '^versionCode=' "$mp" | cut -d= -f2
}

#===========================================================================
# TieJia v2.0.0 — Phase B: Unified config system
#===========================================================================
# Replaces scattered flag files with a single key=value config at CONFIG_FILE.
# Keyspace: fp_auto, fp_interval, kb_auto, kb_interval,
#           daemon_mount_iso, daemon_proc_obf, daemon_prop_unify,
#           daemon_boot_hash, daemon_rom_cleanup, daemon_boot_state,
#           security_dmesg, security_se, log_level

# Default config values (applied when key is absent).
CONFIG_DEFAULTS="\
fp_auto=1
fp_interval=3600
kb_auto=1
kb_interval=3600
daemon_mount_iso=1
daemon_proc_obf=1
daemon_prop_unify=1
daemon_vbmeta_spoof=1
daemon_hot_reload=1
prop_mode=zygisk_only
daemon_boot_hash=1
daemon_rom_cleanup=1
daemon_boot_state=1
daemon_oem_unlock_hide=1
security_dmesg=1
security_se=1
log_level=info
"

# config_get <key> [default]
# Reads a single key from CONFIG_FILE. Falls back to $2, then CONFIG_DEFAULTS,
# then empty string.
config_get() {
  local key="$1" def="${2:-}"
  local cf="${CONFIG_FILE:-${TIEJIA_CONFIG_DIR:-/data/adb/tricky_store}/config}"
  local val

  if [ -f "$cf" ]; then
    val=$(grep -E "^${key}=" "$cf" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -n "$val" ] && { echo "$val"; return 0; }
  fi

  # Try caller-supplied default
  [ -n "$def" ] && { echo "$def"; return 0; }

  # Try global defaults
  val=$(echo "$CONFIG_DEFAULTS" | grep -E "^${key}=" | cut -d= -f2-)
  [ -n "$val" ] && { echo "$val"; return 0; }

  return 1
}

# config_get_bool <key> — returns 0 if truthy (1/true/yes/on), 1 otherwise.
config_get_bool() {
  local val
  val=$(config_get "$@")
  case "$val" in
    1|true|yes|on|TRUE|YES|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# config_set <key> <value>
# Writes key=value to CONFIG_FILE, atomically (via temp file + mv).
config_set() {
  local key="$1" val="$2"
  local cf="${CONFIG_FILE:-${TIEJIA_CONFIG_DIR:-/data/adb/tricky_store}/config}"
  ensure_dir "$(dirname "$cf")"

  if [ -f "$cf" ] && grep -qE "^${key}=" "$cf" 2>/dev/null; then
    # Replace existing key. Prefer busybox sed (reliable -i); fall back to
    # stock sed -i with grep -v + mv for toybox compatibility.
    local _sed="${SED:-sed -i}"
    $_sed "s|^${key}=.*|${key}=${val}|" "$cf" 2>/dev/null || {
      # Busybox sed fallback
      grep -vE "^${key}=" "$cf" > "${cf}.tmp" 2>/dev/null
      echo "${key}=${val}" >> "${cf}.tmp"
      mv -f "${cf}.tmp" "$cf"
    }
  else
    echo "${key}=${val}" >> "$cf"
  fi
}

# config_migrate — convert old flag files to unified config.
# Idempotent: skips keys that already exist in CONFIG_FILE.
config_migrate() {
  local cf="${CONFIG_FILE:-${TIEJIA_CONFIG_DIR:-/data/adb/tricky_store}/config}"

  # fp_auto: absence of no_auto_fp means enabled
  if ! grep -qE '^fp_auto=' "$cf" 2>/dev/null; then
    if [ -f "$CONFIG_DIR/no_auto_fp" ]; then
      echo "fp_auto=0" >> "$cf"
    else
      echo "fp_auto=1" >> "$cf"
    fi
  fi

  # kb_auto: absence of no_auto_keybox means enabled
  if ! grep -qE '^kb_auto=' "$cf" 2>/dev/null; then
    if [ -f "$CONFIG_DIR/no_auto_keybox" ]; then
      echo "kb_auto=0" >> "$cf"
    else
      echo "kb_auto=1" >> "$cf"
    fi
  fi

  # fp_interval / kb_interval: migrate from hourly_interval_sec
  if [ -f "$CONFIG_DIR/hourly_interval_sec" ]; then
    local iv
    iv=$(cat "$CONFIG_DIR/hourly_interval_sec" 2>/dev/null)
    grep -qE '^fp_interval=' "$cf" 2>/dev/null || echo "fp_interval=${iv:-3600}" >> "$cf"
    grep -qE '^kb_interval=' "$cf" 2>/dev/null || echo "kb_interval=${iv:-3600}" >> "$cf"
  fi

  # Fill remaining defaults for any keys still absent
  local k v
  echo "$CONFIG_DEFAULTS" | while IFS='=' read -r k v; do
    [ -z "$k" ] && continue
    grep -qE "^${k}=" "$cf" 2>/dev/null || echo "${k}=${v}" >> "$cf"
  done
}

#===========================================================================
# TieJia v2.0.0 — Structured logging (replaces ad-hoc echo)
#===========================================================================
# Usage: tj_log <level> <msg>
# Levels: DEBUG INFO WARN ERROR (uppercase convention for logcat)
TJ_LOG_LEVEL="${TJ_LOG_LEVEL:-2}"  # 0=DEBUG 1=INFO 2=WARN 3=ERROR

tj_debug() { [ "$TJ_LOG_LEVEL" -le 0 ] && echo "[TieJia:D] $*" >&2; return 0; }
tj_info()  { [ "$TJ_LOG_LEVEL" -le 1 ] && echo "[TieJia:I] $*" >&2; return 0; }
tj_warn()  { [ "$TJ_LOG_LEVEL" -le 2 ] && echo "[TieJia:W] $*" >&2; return 0; }
tj_error() { echo "[TieJia:E] $*" >&2; return 0; }
