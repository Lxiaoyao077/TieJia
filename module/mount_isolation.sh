#!/system/bin/sh
# mount_isolation.sh — mount namespace isolation for GMS + target apps
#
# Enters each target process's mount namespace via nsenter and bind-mounts
# a minimal tmpfs over /data/adb/tricky_store so detection apps that
# scan /proc/<pid>/mountinfo only see an empty directory with a sanitized
# target.txt — not our full module config (keybox, pif.prop, etc.).
#
# Two-layer isolation:
#   Layer 1: GMS (Play Services / Play Store / GSF) — always isolated,
#            since GMS is the primary attestation pipeline.
#   Layer 2: Target apps (from /data/adb/tricky_store/target.txt) —
#            isolated on a best-effort basis. Each target app gets its
#            own namespace bind so it can't see /data/adb/tricky_store.
#
# This is a best-effort countermeasure: on devices where SELinux blocks
# nsenter or mount --bind inside a foreign namespace, the script degrades
# to a monitor-only mode (log + skip, no crash).

MODDIR="${MODPATH:-$(dirname "$0")}"
init_config
LOG_FILE="$MODDIR/mount_isolation.log"
CLEAN_DIR=/data/local/tmp/.as_mount_clean

# Source common helpers (verify_proc_name)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# GMS processes we always isolate
GMS_PROCS="com.google.android.gms.unstable com.android.vending com.google.android.gms com.google.android.gsf"

isolate_process() {
  local proc_name="$1"
  local pid
  pid=$(pidof "$proc_name" 2>/dev/null | awk '{print $1}')
  [ -z "$pid" ] && return 1

  # PID reuse guard
  verify_proc_name "$pid" "$proc_name" || return 1

  # Already isolated?
  local marker="/proc/$pid/root/data/local/tmp/.as_mount_clean/.isolated"
  [ -f "$marker" ] 2>/dev/null && return 0

  local ns_mnt="/proc/$pid/ns/mnt"
  [ ! -e "$ns_mnt" ] && return 1

  nsenter -m -t "$pid" -- /system/bin/sh -c "
    rm -rf '$CLEAN_DIR' 2>/dev/null
    mkdir -p '$CLEAN_DIR' 2>/dev/null || exit 1
    mount -t tmpfs tmpfs '$CLEAN_DIR' 2>/dev/null || exit 1
    _salt=\$(date +%s%N 2>/dev/null | sha256sum 2>/dev/null | cut -c1-8 || echo \$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' '))
    printf '%s\n' com.google.android.gms io.github.vvb2060.keyattestation io.github.vvb2060.mahoshojo > '$CLEAN_DIR/target.txt'
    printf '# %s\n' \"\$_salt\" >> '$CLEAN_DIR/target.txt'
    mount --bind '$CLEAN_DIR' '$CFG' 2>/dev/null || exit 1
    touch '$CLEAN_DIR/.isolated' 2>/dev/null
  " 2>/dev/null

  if [ $? -eq 0 ]; then
    log "isolated $proc_name pid=$pid OK"
    return 0
  else
    log "isolate $proc_name FAILED - SELinux/nsenter skipping"
    return 1
  fi
}

# Read target.txt and extract app package names (skip comments/blanks)
read_targets() {
  local t="$CFG/target.txt"
  [ -f "$t" ] || return 1
  grep -vE '^[[:space:]]*($|#|!)' "$t" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^android$'
}

# --- daemon loop ---
log "mount isolation daemon started: GMS + target apps"
_cycle=0
# Populate targets on first iteration so first 2min is not empty
_targets=$(read_targets 2>/dev/null)
while true; do
  # Layer 1: GMS processes — always
  for proc in $GMS_PROCS; do
    isolate_process "$proc" 2>/dev/null
  done

  # Layer 2: Target apps from target.txt — refresh every 4 cycles (2 min)
  _cycle=$(( (_cycle + 1) % 4 ))
  if [ "$_cycle" -eq 0 ]; then
    _targets=$(read_targets 2>/dev/null)
  fi
  for app in $_targets; do
    [ -z "$app" ] && continue
    isolate_process "$app" 2>/dev/null
  done

  sleep 30
done
