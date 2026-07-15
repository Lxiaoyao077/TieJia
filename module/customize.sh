# shellcheck disable=SC2034
SKIPUNZIP=1
MIN_SDK=29
CONFIG_DIR=/data/adb/tricky_store

if [ "$BOOTMODE" != true ]; then
  abort "请在 Root 管理器（Magisk/KSU/APatch）中安装，不要在 Recovery 中安装"
fi
if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "请先更新 KernelSU 及其管理器"
fi

# ARM-only — x86/x86_64 are emulator-only and not supported.
case "$ARCH" in
  arm64) ABI_DIR="arm64-v8a" ;;
  arm)   ABI_DIR="armeabi-v7a" ;;
  *)     abort "不支持的架构: $ARCH（仅支持 ARM）" ;;
esac

[ "$API" -lt "$MIN_SDK" ] && abort "需要 Android 10 及以上 (SDK $MIN_SDK)"

VERSION=$(grep_prop version "${TMPDIR}/module.prop")
install_file() { unzip -qqjo "$ZIPFILE" "$1" -d "$2" || abort "文件提取失败: $1"; }

ui_print "AlwaysStrong $VERSION"
ui_print "by @evokerr  -  t.me/keyboxstrong"
ui_print ""

# stop anything that might be holding our lib files (upgrade-in-place)
for proc in TEESimulator supervisor daemon ta-enhanced; do
  for pid in $(pidof "$proc" 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
done
for pid in $(pidof TEESimulator 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done

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
  ui_print "无冲突模块"
else
  ui_print "已移除 $CONFLICTS 个冲突模块"
fi

# --- extract our scripts + configs ---------------------------------------
for f in module.prop service.sh post-fs-data.sh action.sh \
         uninstall.sh common_func.sh sepolicy.rule \
         keybox_fetch.sh build_target_txt.sh status_fetch.sh description.txt \
         rom_spoof_block.sh conflict_scan.sh sync_patch.sh \
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
  ui_print "TEESim 已安装 ($ABI_DIR，原生证书生成)"
else
  ui_print "TEESim 已安装 ($ABI_DIR)"
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
ui_print "PIF Zygisk 已安装（$ZN 个 ABI）"

# --- aswatcher native binary (inotify target.txt + Xposed exclude + conflict)
mkdir -p "$MODPATH/bin/$ABI_DIR"
if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "bin/$ABI_DIR/aswatcher"; then
  install_file "bin/$ABI_DIR/aswatcher" "$MODPATH/bin/$ABI_DIR"
  chmod 755 "$MODPATH/bin/$ABI_DIR/aswatcher"
else
  ui_print "警告：缺少 aswatcher 守护进程 ($ABI_DIR)"
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
    ui_print "WebUI 就绪（从管理器打开）"
  else
    ui_print "WebUI：首次点击 [Action] 将自动下载安装"
  fi
else
  ui_print "警告：安装包缺少 WebUI 页面文件"
fi

# --- /data/adb/tricky_store config ----------------------------------------
mkdir -p "$CONFIG_DIR"

# Tell PIF zygisk NOT to auto-generate pif.prop (handled by pif_native_fetch.sh)
touch /data/adb/pif_script_only 2>/dev/null

if [ -f "$CONFIG_DIR/keybox.xml" ]; then
  ui_print "已保留密钥文件 ($(wc -c < "$CONFIG_DIR/keybox.xml") 字节)"
else
  install_file "keybox.xml" "$CONFIG_DIR"
  ui_print "已安装默认密钥（替换真实密钥可获得 STRONG 认证）"
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
ui_print "安装完成。重启后点击 [Action] 按钮刷新。"
ui_print ""
