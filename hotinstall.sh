#!/system/bin/sh
# hotinstall.sh — KSU hot-install helper for TieJia
#
# Reduces the need for a full reboot after updating the module.
# Copies new files into the live module directory and restarts
# the daemon + supervisor without a reboot.
#
# Usage (from module zip after flash):
#   sh /data/adb/modules/tricky_store/hotinstall.sh /path/to/new/files
#
# The caller should have already placed the updated files in the
# MODPATH before invoking this script.

MODDIR="${0%/*}"
OLD_MODDIR="${MODDIR}"

# Source common helpers (verify_proc_name)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

# ----- helpers -----
log() { log -t "TieJia-hot" "$@"; }
die() { log "ERROR: $1"; exit 1; }

# Only works on KSU
[ "$KSU" != "true" ] && [ "$KSU" != true ] && die "hot install only supported on KernelSU"

MODNAME=$(grep_prop name "${MODDIR}/module.prop" 2>/dev/null)
MODNAME="${MODNAME:-tricky_store}"
log "hot-installing $MODNAME"

# 1. Kill running processes so files aren't locked
for proc in TEESimulator supervisor daemon aswatcher ta-enhanced; do
  for pid in $(pidof "$proc" 2>/dev/null); do
    verify_proc_name "$pid" "$proc" && kill -9 "$pid" 2>/dev/null
  done
done
pkill -9 -f TEESimulator 2>/dev/null || true
sleep 1

# 2. Files that should be hot-copied (avoiding overwrites of user config)
#    Everything under MODDIR except: keybox, config, .bootstrapped, .conflict_state
SKIP_PATTERNS="keybox.xml|target.txt|hbk|.bootstrapped|.conflict_state|custom_keybox|tee_status"

if [ -d "${MODDIR}" ]; then
  log "copying updated module files..."
  for f in "${MODDIR}"/*.sh "${MODDIR}"/*.prop "${MODDIR}"/daemon \
           "${MODDIR}"/supervisor "${MODDIR}"/inject "${MODDIR}"/sepolicy.rule \
           "${MODDIR}"/webroot "${MODDIR}"/bin "${MODDIR}"/zygisk \
           "${MODDIR}"/classes.dex "${MODDIR}"/tee_classes.dex \
           "${MODDIR}"/lib*; do
    [ ! -e "$f" ] && continue
    # use simple name check — config files live under CFG=/data/adb/tricky_store
    # not under MODDIR, so MODDIR copies are safe (they're just fresh scripts/bins)
    cp -rf "$f" "${MODDIR}/" 2>/dev/null
  done
fi

# 3. Refresh selinux contexts
restorecon -RF "${MODDIR}" 2>/dev/null

# 4. Restart daemon
log "restarting supervisor + daemon..."
(
  sleep 2
  "${MODDIR}/supervisor" "${MODDIR}/daemon" "${MODDIR}" &
  log "daemon restarted"

  # restart aswatcher if available
  case "$(uname -m)" in
    aarch64) AS_ABI=arm64-v8a ;;
    *)       AS_ABI="" ;;
  esac
  AS_BIN="${MODDIR}/bin/${AS_ABI}/aswatcher"
  [ -x "$AS_BIN" ] && { sleep 2; "$AS_BIN" & log "aswatcher restarted"; }
)&

# 5. Bump KSU module update mark so the manager sees it
touch "${MODDIR}/update" 2>/dev/null

log "hot install complete — no reboot needed"
exit 0
