# shellcheck disable=SC2034
SKIPUNZIP=1
MIN_SDK=29
init_config

# Extract common_func.sh early so verify_proc_name is available for the
# kill loop below. We re-extract it later with the rest of the scripts.
install_file "common_func.sh" "$TMPDIR"
. "$TMPDIR/common_func.sh"

if [ "$BOOTMODE" != true ]; then
  abort "install from a root manager, not recovery"
fi
if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "please update KernelSU + manager first"
fi

# ARM-only — x86/x86_64 are emulator-only and not supported.
case "$ARCH" in
  arm64) ABI_DIR="arm64-v8a" ;;
  arm)   ABI_DIR="armeabi-v7a" ;;
  *)     abort "unsupported arch: $ARCH (ARM only)" ;;
esac

[ "$API" -lt "$MIN_SDK" ] && abort "needs Android 10+ (SDK $MIN_SDK)"

VERSION=$(grep_prop version "${TMPDIR}/module.prop")
install_file() { unzip -qqjo "$ZIPFILE" "$1" -d "$2" || abort "extract failed: $1"; }

ui_print "TieJia $VERSION"
ui_print "by @evokerr  -  t.me/keyboxstrong"
ui_print ""

# stop anything that might be holding our lib files (upgrade-in-place)
for proc in TEESimulator supervisor daemon ta-enhanced; do
  for pid in $(pidof "$proc" 2>/dev/null); do
    verify_proc_name "$pid" "$proc" && kill -9 "$pid" 2>/dev/null
  done
done
pkill -9 -f TEESimulator 2>/dev/null || true

# --- Zygisk implementation detection (Specter-style) ----------------------
ZYGISK_IMPL="none"
ZYGISK_DETAIL=""
if [ -d /data/adb/modules/zygisksu ]; then
  ZYGISK_IMPL="Zygisk Next"
  ZYGISK_DETAIL="(built-in Zygisk)"
elif grep -q "ro.dalvik.vm.native.bridge=zygisk" /data/adb/modules/*/service.sh 2>/dev/null; then
  ZYGISK_IMPL="ReZygisk"
  ZYGISK_DETAIL="(standalone)"
elif [ -d /data/adb/modules/zygisk_shamiko ] || [ -d /data/adb/modules/riru_edxposed ]; then
  ZYGISK_IMPL="Magisk built-in"
  ZYGISK_DETAIL=""
elif [ "$KSU" = true ]; then
  # KSU with built-in Zygisk support (v1.0+)
  if [ -f /data/adb/ksud/ksud ] && /data/adb/ksud/ksud module list 2>/dev/null | grep -q "zygisksu"; then
    ZYGISK_IMPL="KSU Zygisk Next"
    ZYGISK_DETAIL="(KSU native)"
  else
    ZYGISK_IMPL="none"
    ZYGISK_DETAIL="(Zygisk-less KSU — PIF won't work)"
  fi
fi
ui_print ""
ui_print "Zygisk: $ZYGISK_IMPL $ZYGISK_DETAIL"
ui_print ""

# --- conflict cleanup (19 known modules) ---------------------------------
CONFLICTS=0
for c in \
  playintegrityfix playintegrityfork play_integrity_fix \
  playcurl playcurlNEXT \
  tricky_store_v2 TrickyStore \
  tee_simulator TEESimulator TEESimulator-RS \
  safetynet-fix Universal_SafetyNet_Fix \
  MagiskHidePropsConf \
  TA_utl tricky_addon TA_enhanced tsupport-advance \
  Yurikey \
  pif_strong pif_force ; do
  cp_dir="/data/adb/modules/$c"
  if [ -d "$cp_dir" ] && [ "$(basename "$cp_dir")" != "$(basename "$MODPATH")" ]; then
    CONFLICTS=$((CONFLICTS+1))
    [ -f "$cp_dir/uninstall.sh" ] && sh "$cp_dir/uninstall.sh" 2>/dev/null || true
    touch "$cp_dir/disable" "$cp_dir/remove"
    rm -rf "$cp_dir" 2>/dev/null
  fi
  [ -d "/data/adb/modules_update/$c" ] && rm -rf "/data/adb/modules_update/$c" 2>/dev/null
done
if [ $CONFLICTS -eq 0 ]; then
  ui_print "no conflicting modules"
else
  ui_print "removed $CONFLICTS conflicting module(s)"
fi

# --- extract our scripts + configs ---------------------------------------
for f in module.prop service.sh post-fs-data.sh action.sh \
         uninstall.sh common_func.sh sepolicy.rule \
         keybox_fetch.sh keybox_rotate.sh build_target_txt.sh status_fetch.sh description.txt \
         rom_spoof_block.sh conflict_scan.sh sync_patch.sh \
         boot_hash.sh target_cleanup.sh \
         security_patch.sh \
         daemon ; do
  install_file "$f" "$MODPATH"
done

# --- TEESim binaries ------------------------------------------------------
install_file "lib/$ABI_DIR/libTEESimulator.so" "$MODPATH"
install_file "lib/$ABI_DIR/libinject.so"       "$MODPATH"
install_file "lib/$ABI_DIR/libsupervisor.so"   "$MODPATH"
HAS_CERTGEN=0
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "lib/$ABI_DIR/libcertgen.so"; then
  install_file "lib/$ABI_DIR/libcertgen.so" "$MODPATH"
  HAS_CERTGEN=1
fi
mv "$MODPATH/libinject.so"     "$MODPATH/inject"
mv "$MODPATH/libsupervisor.so" "$MODPATH/supervisor"
install_file "tee_classes.dex" "$MODPATH"
if [ $HAS_CERTGEN -eq 1 ]; then
  ui_print "TEESim installed ($ABI_DIR, native certgen)"
else
  ui_print "TEESim installed ($ABI_DIR)"
fi

# --- PIF zygisk (arm only) -----------------------------------------------
mkdir -p "$MODPATH/zygisk"
ZN=0
for z in arm64-v8a armeabi-v7a; do
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "zygisk/$z.so"; then
    unzip -qqjo "$ZIPFILE" "zygisk/$z.so" -d "$MODPATH/zygisk" 2>/dev/null
    ZN=$((ZN+1))
  fi
done
install_file "classes.dex" "$MODPATH"
ui_print "PIF zygisk installed ($ZN ABIs)"

# --- aswatcher native binary (inotify target.txt + Xposed exclude + conflict)
mkdir -p "$MODPATH/bin/$ABI_DIR"
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "bin/$ABI_DIR/aswatcher"; then
  install_file "bin/$ABI_DIR/aswatcher" "$MODPATH/bin/$ABI_DIR"
  chmod 755 "$MODPATH/bin/$ABI_DIR/aswatcher"
else
  ui_print "warning: no aswatcher binary for $ABI_DIR"
fi
# --- asfetch native binary (TLS fetcher for keybox/status) ---------
if [ "$ABI_DIR" = "arm64-v8a" ] || [ "$ABI_DIR" = "armeabi-v7a" ]; then
  if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "bin/$ABI_DIR/asfetch"; then
    install_file "bin/$ABI_DIR/asfetch" "$MODPATH/bin/$ABI_DIR"
    chmod 755 "$MODPATH/bin/$ABI_DIR/asfetch"
  fi
fi

chmod 755 "$MODPATH/daemon" "$MODPATH/supervisor" "$MODPATH/inject" \
          "$MODPATH"/*.sh 2>/dev/null

# --- WebUI (KSU / APatch / MMRL) — single self-contained index.html
mkdir -p "$MODPATH/webroot"
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "webroot/index.html"; then
  install_file "webroot/index.html" "$MODPATH/webroot"
  chmod 644 "$MODPATH/webroot/index.html"
  if [ "$KSU" = true ] || [ "$APATCH" = true ]; then
    ui_print "WebUI ready (open it from your manager)"
  else
    ui_print "WebUI: app downloads + installs on first Action tap"
  fi
else
  ui_print "warning: WebUI index.html missing from package"
fi

# --- /data/adb/tricky_store config ----------------------------------------
mkdir -p "$CONFIG_DIR"

# Tell PIF zygisk NOT to auto-generate pif.prop (handled by pif_native_fetch.sh)
touch /data/adb/pif_script_only 2>/dev/null

if [ -f "$CONFIG_DIR/keybox.xml" ]; then
  ui_print "keybox kept ($(wc -c < "$CONFIG_DIR/keybox.xml") bytes)"
else
  install_file "keybox.xml" "$CONFIG_DIR"
  ui_print "default keybox installed (replace for STRONG)"
fi

[ -f "$CONFIG_DIR/target.txt" ] || install_file "target.txt" "$CONFIG_DIR"

# /dev/urandom — non-blocking, plenty for the 32-byte hbk seed.
if [ ! -f "$CONFIG_DIR/hbk" ]; then
  head -c 32 /dev/urandom > "$CONFIG_DIR/hbk"
  chmod 600 "$CONFIG_DIR/hbk"
fi
rm -f "$CONFIG_DIR/tee_status.txt" "$CONFIG_DIR/tee_status" 2>/dev/null

# --- status_json.sh + conflicts.txt (Specter-style) -----------------------
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "status_json.sh"; then
  install_file "status_json.sh" "$MODPATH"
  chmod 755 "$MODPATH/status_json.sh"
fi
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "config/conflicts.txt"; then
  mkdir -p "$CONFIG_DIR/config"
  install_file "config/conflicts.txt" "$CONFIG_DIR/config"
fi

ui_print ""
ui_print "installed. reboot, then tap [Action] to refresh."
ui_print ""
