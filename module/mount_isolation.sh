#!/system/bin/sh
# mount_isolation.sh — mount namespace isolation for GMS + Play Store
#
# Enters the GMS process mount namespace via nsenter and bind-mounts
# a minimal tmpfs over /data/adb/tricky_store so detection apps that
# scan /proc/<gms_pid>/mountinfo only see an empty directory with a
# sanitized target.txt — not our full module config (keybox, pif.prop, etc.).
#
# This is a best-effort countermeasure: on devices where SELinux blocks
# nsenter or mount --bind inside a foreign namespace, the script degrades
# to a monitor-only mode (log + skip, no crash).

MODDIR="${MODPATH:-$(dirname "$0")}"
CFG=/data/adb/tricky_store
LOG_FILE="$MODDIR/mount_isolation.log"
CLEAN_DIR=/data/local/tmp/.as_mount_clean

log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# GMS processes we want to isolate
TARGET_PROCESSES="com.google.android.gms.unstable com.android.vending com.google.android.gms"

isolate_process() {
  local proc_name="$1"
  local pid
  pid=$(pidof "$proc_name" 2>/dev/null | awk '{print $1}')
  [ -z "$pid" ] && return 1

  # Already isolated? Check marker from GMS' own root view
  local marker="/proc/$pid/root/data/local/tmp/.as_mount_clean/.isolated"
  [ -f "$marker" ] 2>/dev/null && return 0

  local ns_mnt="/proc/$pid/ns/mnt"
  [ ! -e "$ns_mnt" ] && return 1

  # Build a clean tmpfs with minimal content, then bind-mount it over
  # /data/adb/tricky_store inside the GMS process's mount namespace.
  # The tmpfs hides keybox.xml, pif.prop, and all other config files
  # from detection apps scanning GMS mountinfo.
  # If SELinux blocks any step, the entire command fails silently and
  # we skip this PID (next cycle will retry with the same PID since
  # the marker won't be written).
  nsenter -m -t "$pid" -- /system/bin/sh -c "
    rm -rf "$CLEAN_DIR" 2>/dev/null
    mkdir -p "$CLEAN_DIR" 2>/dev/null || exit 1
    mount -t tmpfs tmpfs "$CLEAN_DIR" 2>/dev/null || exit 1
    printf '%s' 'com.google.android.gms
io.github.vvb2060.keyattestation
io.github.vvb2060.mahoshojo' > "\$CLEAN_DIR/target.txt"
    mount --bind "$CLEAN_DIR" "$CFG" 2>/dev/null || exit 1
    touch "$CLEAN_DIR/.isolated" 2>/dev/null
  " 2>/dev/null

  if [ $? -eq 0 ]; then
    log "isolated $proc_name (pid=$pid) OK"
    return 0
  else
    # SELinux or nsenter failure — log and skip. No fallback because
    # there's no safe degraded mode for mount isolation.
    log "isolate $proc_name FAILED (SELinux/nsenter — skipping)"
    return 1
  fi
}

# --- daemon loop ---
# Re-scan every 30s because GMS unstable process can be killed/restarted.
# Each new instance gets isolated on the next cycle.
log "mount isolation daemon started"
while true; do
  for target in $TARGET_PROCESSES; do
    isolate_process "$target" 2>/dev/null
  done
  sleep 30
done
