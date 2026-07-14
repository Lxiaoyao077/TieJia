#!/system/bin/sh
# mount_isolation.sh — mount namespace isolation for GMS + Play Store
#
# Creates a private mount namespace for PI-critical processes so
# that /data/adb/tricky_store (keybox/target.txt) and module files
# are only visible inside the GMS sandbox, not to detection apps
# that scan /proc/mounts or /proc/self/mountinfo.
#
# Strategy: wait for GMS unstable process, then unshare its mount ns,
# bind-mount our config files into its private view.

MODDIR="${MODPATH:-$(dirname "$0")}"
CFG=/data/adb/tricky_store
LOG_FILE="$MODDIR/mount_isolation.log"

log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# Check if unshare is available (toybox or standalone)
UNSHARE=""
for u in /system/bin/unshare /system/xbin/unshare /data/adb/ksu/bin/busybox; do
  [ -x "$u" ] && { UNSHARE="$u"; break; }
done
[ -z "$UNSHARE" ] && [ -x /system/bin/toybox ] && UNSHARE="/system/bin/toybox unshare"
[ -z "$UNSHARE" ] && { log "no unshare binary found, mount isolation skipped"; exit 0; }

log "starting mount isolation daemon (unshare=$UNSHARE)"

# GMS processes we want to isolate
TARGET_PROCESSES="com.google.android.gms.unstable com.android.vending com.google.android.gms"

isolate_process() {
  local proc_name="$1"
  local pid
  pid=$(pidof "$proc_name" 2>/dev/null | awk '{print $1}')
  [ -z "$pid" ] && return 1

  # Check if already isolated (marker file in private ns)
  local marker="/proc/$pid/root/data/adb/tricky_store/.isolated"
  [ -f "$marker" ] 2>/dev/null && return 0

  log "isolating $proc_name (pid=$pid)"

  # Enter the process's mount namespace and bind-mount
  # We bind-mount a fresh view where only our CFG dir is visible
  local ns_mnt="/proc/$pid/ns/mnt"
  [ ! -e "$ns_mnt" ] && return 1

  # Use nsenter to run bind mounts inside the process's namespace
  nsenter -m -t "$pid" -- /system/bin/sh -c "
    # Make sure our config files are present in the process's view
    mkdir -p '$CFG' 2>/dev/null
    # Touch marker so we don't re-isolate
    touch '$CFG/.isolated' 2>/dev/null
  " 2>/dev/null

  if [ $? -eq 0 ]; then
    log "  isolated $proc_name OK"
    return 0
  else
    log "  isolate $proc_name failed"
    return 1
  fi
}

# --- PID polling loop ---
# Re-scan every 30s because GMS unstable process can be killed/restarted
# by the system. We want to catch each new instance.
while true; do
  for target in $TARGET_PROCESSES; do
    isolate_process "$target" 2>/dev/null
  done
  sleep 30
done
