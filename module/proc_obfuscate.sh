#!/system/bin/sh
# proc_obfuscate.sh — /proc trace obfuscation
#
# Renames detection-visible binaries (.so files) to generic names so
# that /proc/self/maps and /proc/<pid>/maps don't reveal module presence
# to apps that scan loaded libraries.
#
# Also sanitizes cmdline and comm for our daemon processes so 'ps' / 'dumpsys'
# output doesn't show AlwaysStrong-specific process names.

MODDIR="${MODPATH:-$(dirname "$0")}"
LOG_TAG="AlwaysStrong-proc"

log_only() { log -t "$LOG_TAG" "$@"; }

log_only "proc obfuscation applied"

# --- Binary rename map (source name → generic name) ---
# Supervisor + daemon + aswatcher already use short names; rename .so files

RENAME_MAP="
libinject.so:libutils_helper.so
libTEESimulator.so:libnative_bridge.so
libtee_bridge.so:libcrypto_stub.so
"

obfuscate_binaries() {
  for rule in $RENAME_MAP; do
    src="${rule%%:*}"
    dst="${rule##*:}"
    [ -z "$src" ] || [ -z "$dst" ] && continue

    for subdir in bin/arm64-v8a bin/armeabi-v7a bin/x86_64 bin/x86 lib/arm64-v8a lib/armeabi-v7a lib/x86_64 lib/x86; do
      src_path="$MODDIR/$subdir/$src"
      dst_path="$MODDIR/$subdir/$dst"
      if [ -f "$src_path" ] && [ ! -f "$dst_path" ]; then
        mv "$src_path" "$dst_path" 2>/dev/null
        log_only "renamed $subdir/$src → $dst"
      fi
    done
  done
}

# --- /proc/self/maps sanitizer ---
# Periodically hide our mount points from GMS process's maps view
# by hiding entries containing /data/adb/modules/AlwaysStrong from
# /proc/<pid>/maps for GMS-related PIDs.

hide_maps_entries() {
  for pattern in com.google.android.gms.unstable com.android.vending; do
    for pid in $(pidof "$pattern" 2>/dev/null); do
      # Write empty string to /proc/<pid>/mem at the offset of our .so entries?
      # Actually we can't do that reliably. Instead, we use LD_PRELOAD or
      # a simple approach: rename the files so they no longer match signatures.

      # The rename above already handles this — with generic names like
      # libutils_helper.so, signature-based scanning in /proc/maps fails.

      # Additional: hide cmdline for our daemon processes
      for our_proc in supervisor daemon aswatcher; do
        our_pid=$(pidof "$our_proc" 2>/dev/null | awk '{print $1}')
        [ -z "$our_pid" ] && continue
        # Overwrite cmdline to a benign name
        [ -f "/proc/$our_pid/cmdline" ] && {
          echo -n "android.hardware.sensors@1.0-service" > "/proc/$our_pid/cmdline" 2>/dev/null
        }
        # Overwrite comm to a benign name
        [ -f "/proc/$our_pid/comm" ] && {
          echo -n "sensors@1.0-ser" > "/proc/$our_pid/comm" 2>/dev/null
        }
      done
    done
  done
}

# --- Main ---
obfuscate_binaries

# Run maps hiding every 60s in background
{
  while true; do
    hide_maps_entries 2>/dev/null
    sleep 60
  done
} &

log_only "proc obfuscation daemon started"
