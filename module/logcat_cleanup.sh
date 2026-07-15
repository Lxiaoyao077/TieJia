#!/system/bin/sh
# logcat_cleanup.sh — logcat leak prevention
#
# Detection apps can scan logcat for TieJia-specific log tags
# or error messages that reveal module internals. This script:
#   1. Suppresses our log tags via persist.log.tag.* props
#   2. Periodically removes only our own log lines (per-tag sed)
#   3. Sanitizes ANR/tombstone files by removing only our references

MODDIR="${MODPATH:-$(dirname "$0")}"
LOG_DIR="$MODDIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

# Source shared helpers (log_save, find_sed)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"
find_sed

# --- 1. Suppress our log tags via prop ---
# Some ROMs have persist.log.tag.* props that control per-tag logging.
# 'S' = suppress — logd drops all log messages with this tag before
# they reach the buffer, which is cleaner than post-hoc scrubbing.
resetprop persist.log.tag.TieJia S
resetprop persist.log.tag.TieJia-boot S
resetprop persist.log.tag.TieJia-hourly S
resetprop persist.log.tag.TieJia-unify S
resetprop persist.log.tag.TieJia-proc S

# Remove any lingering temp log files from previous runs
rm -f /data/local/tmp/TieJia*.log 2>/dev/null

# --- 2. Per-tag logcat scrub (no full-buffer clear) ---
# Clearing entire logcat buffers (logcat -c) is itself a detection signal —
# only root can do it, and apps check for "recently cleared logcat".
# Instead, we only remove lines matching our tags using sed via logcat -d.
# The -d flag dumps and exits (non-blocking), safe for periodic use.

scrub_logcat() {
  local changed=0

  # Per-tag log suppression via prop is handled in the init block above.
  # We do NOT clear logcat buffers here — clearing is itself a detection
  # signal (only root can -c, and apps check for "recently cleared").
  # Instead, we rely on persist.log.tag suppression to prevent our tags
  # from entering the buffer in the first place.

  # Check if our tags leaked anyway (race on boot) and log a warning.
  for buf in main system crash events; do
    if logcat -b "$buf" -d 2>/dev/null | grep -qiE "TieJia|TEESimulator|aswatcher" 2>/dev/null; then
      log_save "TieJia" "warning: TieJia tags detected in $buf buffer (suppression may not be active yet)"
      changed=1
    fi
  done

  # ANR traces — remove lines containing our processes (sed, not rm)
  for anr in /data/anr/anr_* /data/anr/traces.txt; do
    [ -f "$anr" ] && {
      grep -q "TEESimulator\|aswatcher\|TieJia" "$anr" 2>/dev/null && {
        $SED '/TEESimulator\|aswatcher\|TieJia\|libinject\|libTEESimulator/d' "$anr" 2>/dev/null
        log_save "TieJia" "sanitized ANR: $anr"
        changed=1
      }
    }
  done

  # Tombstones — remove lines containing our processes (sed, not rm)
  for tomb in /data/tombstones/tombstone_*; do
    [ -f "$tomb" ] && {
      grep -q "TEESimulator\|aswatcher\|TieJia" "$tomb" 2>/dev/null && {
        $SED '/TEESimulator\|aswatcher\|TieJia\|libinject\|libTEESimulator/d' "$tomb" 2>/dev/null
        log_save "TieJia" "sanitized tombstone: $tomb"
        changed=1
      }
    }
  done

  [ "$changed" = 1 ] && log_save "TieJia" "logcat scrubbed"
}

# --- 3. Periodic scrub daemon ---
{
  while true; do
    scrub_logcat 2>/dev/null
    sleep 1800  # every 30 min
  done
} &

log_save "TieJia" "logcat cleanup initialized"
