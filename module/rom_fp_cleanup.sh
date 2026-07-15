#!/system/bin/sh
# ROM fingerprint scrubber — removes detectable custom-ROM traces from system
# properties. Runs at boot (service.sh) and on [Action] button press.
# Based on Specter's rom_fingerprint.sh, adapted for AlwaysStrong.

set -e
MODDIR="${0%/*}"
. "$MODDIR/common_func.sh"

# Gate: user can disable via /data/adb/tricky_store/no_rom_fp_cleanup
[ -f /data/adb/tricky_store/no_rom_fp_cleanup ] && exit 0

cleaned=0

# --- 1. ROM keyword scan (50+ custom-ROM identifiers) ---
# Single resetprop dump, then iterate patterns against the cached output
# (was: one dump per pattern = 50+ redundant syscalls).
# Props that Phase 2 handles surgically (build fingerprint/display/desc/
# increment/ro.product.vendor.name) are skipped here to avoid accidental
# deletion of critical attestation fields.
rom_patterns="lineage crDroid PixelExperience PixelOS EvolutionX ArrowOS HavocOS ResurrectionRemix AICP AOSiP AOSPA Bootleggers CarbonROM ColtOS DotOS DirtyUnicorns DerpFest ExtendedUI FluidOS FusionOS GenesisOS GZOSP HalogenOS IonOS LegionOS LiquidRemix LLuviaOS Mokee MSM-Xtended NitrogenOS NusantaraOS OctaviOS OmniROM ParanoidAndroid POSP ProjectSakura RevengeOS RisingOS ShapeShiftOS SlimRoms SpiceOS StagOS SuperiorOS SyberiaOS TequilaOS TheAndroidProject titanium ValidusOS ViperOS XOSP ZenithOS ZephyrusOS crDroidProject"

protected_props="ro.build.fingerprint ro.build.display.id ro.build.description ro.build.version.incremental ro.product.vendor.name vendor.camera.aux.packagelist persist.vendor.camera.privapp.list"

all_props=$(resetprop 2>/dev/null)

for pattern in $rom_patterns; do
    matches=$(echo "$all_props" | grep -i "$pattern" | cut -d'[' -f2 | cut -d']' -f1 || true)
    for prop in $matches; do
        [ -z "$prop" ] && continue
        case " $protected_props " in *" $prop "*) continue ;; esac
        resetprop --delete "$prop" 2>/dev/null || true
        cleaned=$((cleaned + 1))
    done
done
unset pattern matches prop rom_patterns all_props protected_props

# --- 2. Prefix strip: aosp_ / lineage_ from build fingerprints ---
# Some ROMs leave "aosp_generic-" or "lineage_razor-" in build props.
# Strip these prefixes so they look like stock AOSP builds.
for build_prop in ro.build.fingerprint ro.build.display.id \
                  ro.build.description ro.build.version.incremental \
                  ro.product.vendor.name; do
    val=$(resetprop "$build_prop" 2>/dev/null || echo "")
    [ -z "$val" ] && continue
    new_val="$val"
    for prefix in aosp_ lineage_; do
        case "$new_val" in
            "$prefix"*) new_val=${new_val#"$prefix"} ;;
        esac
    done
    [ "$new_val" != "$val" ] && resetprop -n "$build_prop" "$new_val" && cleaned=$((cleaned + 1))
done
unset build_prop val new_val prefix

# --- 3. PIF spoof prop residue cleanup ---
# (Phases 3/4 removed — service.sh LineageOS scrub handles camera
# packagelist + lineage_health surgically, no duplication needed.)
# Modules like PIF/TSupport leave pihook/pixelprops/spoof/entryhooks
# props in the runtime property space. Clean them here so they don't
# linger after the module is removed or disabled.
spoof_props=$(resetprop 2>/dev/null | grep -iE "pihook|pixelprops|spoof|entryhooks" | cut -d'[' -f2 | cut -d']' -f1 || true)
for prop in $spoof_props; do
    [ -z "$prop" ] && continue
    resetprop --delete "$prop" 2>/dev/null || true
    cleaned=$((cleaned + 1))
done
unset prop spoof_props

# --- Summary ---
if [ "$cleaned" -gt 0 ]; then
    log_save "RomFPClean" "scrubbed $cleaned ROM fingerprint(s)"
fi
unset cleaned
