#!/system/bin/sh
# proc_obfuscate.sh — /proc trace obfuscation
#
# Sanitizes cmdline and comm for our daemon processes so 'ps' / 'dumpsys'
# output doesn't show TieJia-specific process names.
#
# NOTE: .so file renaming was removed (v1.1.1+). Renaming libinject.so or
# libTEESimulator.so breaks Zygisk injection and TEE simulator loading
# because the dynamic linker loads libraries by their original names.

MODDIR="${MODPATH:-$(dirname "$0")}"
LOG_TAG="TieJia-proc"

# Source common helpers (verify_proc_name)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_only() { log -t "$LOG_TAG" "$@"; }

# --- Process name obfuscation ---
# Overwrite cmdline + comm for our daemons so they appear as
# harmless system services in process listings.

obfuscate_cmdline() {
  BENIGN_CMDLINE="android.hardware.sensors@1.0-service"
  BENIGN_COMM="sensors@1.0-ser"

  for our_proc in supervisor daemon aswatcher; do
    for our_pid in $(pidof "$our_proc" 2>/dev/null); do
      [ -z "$our_pid" ] && continue
      # PID reuse guard: ensure /proc/pid/cmdline still names us
      verify_proc_name "$our_pid" "$our_proc" || continue
      [ -f "/proc/$our_pid/cmdline" ] && {
        echo -n "$BENIGN_CMDLINE" > "/proc/$our_pid/cmdline" 2>/dev/null
      }
      [ -f "/proc/$our_pid/comm" ] && {
        echo -n "$BENIGN_COMM" > "/proc/$our_pid/comm" 2>/dev/null
      }
    done
  done
}

# --- Main ---
log_only "proc obfuscation daemon started"

# Run cmdline obfuscation every 60s in background
{
  while true; do
    obfuscate_cmdline 2>/dev/null
    sleep 60
  done
} &
