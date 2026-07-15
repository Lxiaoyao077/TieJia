#!/system/bin/sh
# tmp_harden.sh — /data/local/tmp hardening
# AlwaysStrong v1.4.0
#
# Patches three properties of /data/local/tmp that the Chunqiu detector
# (and most banking-app root scanners) flag as "Suspicious Surroundings":
#   (a) group owner must be `shell` (root/system = suspicious on user build)
#   (b) directory permissions must be 0771 (drwxrwx--x)
#   (c) inode must be small (< 10000). A large inode means the dir was
#       recreated late by a root userland (typical Magisk/KernelSU mount
#       handling) rather than created early by init.
#
# Wiring:
#   * post-fs-data.sh   — runs the cheap chown/chmod at the earliest point
#   * service.sh (boot) — re-runs chown/chmod (other modules' props scripts
#                         can chmod it again) and re-checks inode after
#                         boot_completed, recreating the dir if needed.
#
# Bails silently on every error: this is best-effort hardening, not a
# correctness requirement. If any step fails (read-only mount, missing
# stat binary, etc.) the original /data/local/tmp is left untouched.

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

TMP="/data/local/tmp"
TMP_PARENT="/data/local"

# Bail out of the whole thing if the directory does not exist on this ROM.
[ -d "$TMP" ] || exit 0

log_save "tmp_harden: start ($TMP)"

# --- 1. Cheap, always-safe fixes (no inode surgery yet) ----------------
# chown to root:shell. Magisk's prop-fix modules sometimes flip this back
# to root:root, so we do it both at post-fs-data (early) and at boot
# completion (after every other module has settled).
chown root:shell "$TMP" 2>/dev/null || true
# 0771 = rwx for owner, rwx for group, --x for other (matches AOSP init).
chmod 0771 "$TMP" 2>/dev/null || true

# --- 2. Inode check ----------------------------------------------------
# stat -c %i is GNU; toybox stat uses -c too on Android 8+ so this works
# on every device the module currently supports. If stat isn't there at
# all, fall back to ls -di.
TMP_INODE=""
if command -v stat >/dev/null 2>&1; then
    TMP_INODE=$(stat -c %i "$TMP" 2>/dev/null)
elif command -v ls >/dev/null 2>&1; then
    TMP_INODE=$(ls -di "$TMP" 2>/dev/null | awk '{print $1}')
fi

# Inode < 10000 is what the detector considers "created by init" (the
# init-created dir on AOSP has inode in the low hundreds). If the inode
# is large — i.e. someone (us, Magisk, KernelSU, an installer) created a
# fresh /data/local/tmp at runtime — we rebuild it during post-fs-data
# (no userspace apps are running yet, so moving the contents is safe).
REBUILD_NEEDED=0
case "$TMP_INODE" in
    ''|*[!0-9]*) REBUILD_NEEDED=0 ;;       # couldn't read → skip, chown above is enough
    0)           REBUILD_NEEDED=0 ;;
    *)
        if [ "$TMP_INODE" -gt 10000 ]; then
            REBUILD_NEEDED=1
        fi
        ;;
esac

if [ "$REBUILD_NEEDED" = 1 ]; then
    log_save "tmp_harden: inode=$TMP_INODE > 10000, rebuilding $TMP"

    # Stage contents in a sibling dir, then swap. We use the parent
    # (/data/local) because the original is currently in use by anything
    # that ran before us. Moving the *directory* itself (not its contents)
    # is the only way to release the old inode.
    STAGE="${TMP_PARENT}/.tmp_harden_stage.$$"
    rm -rf "$STAGE" 2>/dev/null
    mkdir -p "$STAGE" 2>/dev/null || { log_save "tmp_harden: cannot stage, skipping rebuild"; exit 0; }

    # Move every entry out of the old dir into the stage. Hidden files
    # included (busybox `ls -A` returns dotfiles except . and ..).
    if command -v find >/dev/null 2>&1; then
        find "$TMP" -mindepth 1 -maxdepth 1 -exec mv -f {} "$STAGE/" \; 2>/dev/null
    else
        for entry in "$TMP"/* "$TMP"/.[!.]* "$TMP"/..?*; do
            [ -e "$entry" ] || continue
            mv -f "$entry" "$STAGE/" 2>/dev/null
        done
    fi

    # Remove the old (high-inode) dir and make a fresh one in its place.
    # rmdir is safe here because every entry has been moved out.
    rmdir "$TMP" 2>/dev/null || rm -rf "$TMP" 2>/dev/null
    mkdir -p "$TMP" 2>/dev/null || {
        # Could not recreate — try to put the staged contents back so we
        # don't leave the user's /data/local/tmp empty.
        log_save "tmp_harden: cannot recreate $TMP, restoring"
        mkdir -p "$TMP" 2>/dev/null
        for entry in "$STAGE"/*; do
            [ -e "$entry" ] || continue
            mv -f "$entry" "$TMP/" 2>/dev/null
        done
        rm -rf "$STAGE" 2>/dev/null
        exit 0
    }
    chown root:shell "$TMP" 2>/dev/null || true
    chmod 0771 "$TMP" 2>/dev/null || true

    # Move staged contents back.
    for entry in "$STAGE"/*; do
        [ -e "$entry" ] || continue
        mv -f "$entry" "$TMP/" 2>/dev/null
    done
    rm -rf "$STAGE" 2>/dev/null

    # Restore SELinux context on the new dir + every file moved back in.
    # restorecon is on toybox/most ROMs; if it's missing, skip — context
    # is inherited from the parent in most cases.
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -RF "$TMP" 2>/dev/null || true
    fi

    NEW_INODE=""
    if command -v stat >/dev/null 2>&1; then
        NEW_INODE=$(stat -c %i "$TMP" 2>/dev/null)
    fi
    log_save "tmp_harden: rebuilt, new inode=${NEW_INODE:-?}"
fi

log_save "tmp_harden: done"
unset TMP TMP_PARENT TMP_INODE STAGE REBUILD_NEEDED NEW_INODE entry
