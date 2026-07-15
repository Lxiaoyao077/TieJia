#!/system/bin/sh
# Build /data/adb/tricky_store/target.txt from all installed packages.
#
# Modes (set via --mode or /data/adb/tricky_store/target_mode):
#   auto       – user/OEM apps get no suffix; GMS/GSF/Vending get `!` (default)
#   force      – ALL packages get `!` suffix (hardware keybox for everything)
#   certchain  – ALL packages get `?` suffix (modified cert chain)
#
# Usage:
#   sh build_target_txt.sh [--mode auto|force|certchain] [output_path]
#
# The aswatcher inotify daemon auto-adds newly installed packages at runtime;
# this script produces the initial seed and the periodic Action-tap rebuild.

# POSIX-portable "last argument" extraction (${@: -1} is bash-only)
for last; do :; done
TGT="${last:-/data/adb/tricky_store/target.txt}"
case "$TGT" in
    --mode) TGT="/data/adb/tricky_store/target.txt" ;;
    /*) ;;
    *) TGT="/data/adb/tricky_store/target.txt" ;;
esac

# --- resolve mode: CLI arg > config file > default (auto)
MODE="auto"
CFG_MODE="/data/adb/tricky_store/target_mode"
# Consume --mode <val> in one pass: peek at arg after --mode, set MODE, skip val
has_explicit_mode=0
next_is_mode=0
for arg in "$@"; do
    [ "$next_is_mode" = 1 ] && { MODE="$arg"; next_is_mode=0; continue; }
    case "$arg" in
        --mode) next_is_mode=1; has_explicit_mode=1 ;;
    esac
done
# Strip CR from persisted config (handles Windows-line-ending edits via adb)
if [ "$has_explicit_mode" -eq 0 ] && [ -f "$CFG_MODE" ]; then
    MODE=$(tr -d '\r' < "$CFG_MODE" 2>/dev/null)
    case "$MODE" in
        auto|force|certchain) ;;
        *) MODE="auto" ;;
    esac
fi

# Resolve suffix from mode
case "$MODE" in
    force)     SUFFIX="!" ;;
    certchain) SUFFIX="?" ;;
    *)         SUFFIX=""  ;;
esac

# Bail out early if pm is unreachable -- keep existing target.txt as-is.
pm list packages >/dev/null 2>&1 || exit 1

ALL=$(pm list packages 2>/dev/null | sed 's/^package://')

# OEM payment / wallet / store apps that ship pre-installed (so `-3` misses
# them) but legitimately call the Play Integrity API. Add only if actually
# present on this device.
OEM_LIST="
com.samsung.android.spay
com.samsung.android.samsungpay.gear
com.samsung.android.spaytui
com.samsung.android.app.spage
com.sec.android.app.samsungapps
com.huawei.wallet
com.huawei.android.hwpay
com.miui.securitycenter
com.xiaomi.market
com.oneplus.opbackup
com.oplus.wallet
com.google.android.apps.walletnfcrel
com.google.android.apps.nbu.paisa.user
com.oplus.deepthinker
com.heytap.speechassist
com.coloros.sceneservice
"

# GMS/GSF/Vending — in auto mode they always get `!` (hardware keybox needed
# for STRONG); in force/certchain mode they get the same suffix as everything else.
FORCED_LIST="
com.android.vending
com.google.android.gms
com.google.android.gsf
"

is_installed() { printf '%s\n' "$ALL" | grep -Fxq "$1"; }

{
    # User installs (`-3`). Filter the forced names defensively in case a
    # weird ROM ever surfaces them through `-3`.
    pm list packages -3 2>/dev/null \
        | sed 's/^package://' \
        | grep -Fxv -e com.android.vending \
                    -e com.google.android.gms \
                    -e com.google.android.gsf

    for p in $OEM_LIST; do
        is_installed "$p" && printf '%s\n' "$p"
    done

    for p in $FORCED_LIST; do
        if is_installed "$p"; then
            if [ -n "$SUFFIX" ] && [ "$MODE" != "auto" ]; then
                printf '%s%s\n' "$p" "$SUFFIX"
            else
                printf '%s!\n' "$p"
            fi
        fi
    done
} | while read -r pkg; do
    [ -z "$pkg" ] && continue
    # In force/certchain mode, append suffix to every non-forced package
    case "$pkg" in
        *[?!]) printf '%s\n' "$pkg" ;;
        *)
            if [ "$MODE" = "force" ] || [ "$MODE" = "certchain" ]; then
                printf '%s%s\n' "$pkg" "$SUFFIX"
            else
                printf '%s\n' "$pkg"
            fi
            ;;
    esac
done | sort -u > "${TGT}.tmp" && mv -f "${TGT}.tmp" "$TGT"

# Persist mode choice so WebUI reads it back
mkdir -p /data/adb/tricky_store 2>/dev/null
printf '%s\n' "$MODE" > "$CFG_MODE" 2>/dev/null
