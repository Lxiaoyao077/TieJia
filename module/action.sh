#!/system/bin/sh
# TieJia action button.
# Shows each step progressively with status feedback.

case "$0" in
    */*) MODPATH=$(cd "${0%/*}" 2>/dev/null && pwd) ;;
    *)   MODPATH="$PWD" ;;
esac
[ -z "$MODPATH" ] && MODPATH="$PWD"
cd "$MODPATH" 2>/dev/null

set +o standalone 2>/dev/null
unset ASH_STANDALONE

# Source shared helpers (find_sed, log_save, find_tool, resetprop_*)
[ -f "$MODPATH/common_func.sh" ] && . "$MODPATH/common_func.sh"
find_sed

init_config
LINE="========================="
VER=$(grep -m1 '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2-)

row() { echo "    $1   $2"; }

# --- ABI + fetchers ---
case "$(uname -m)" in
    aarch64)        ABI=arm64-v8a ;;
    armv7*|armv8l)  ABI=armeabi-v7a ;;
    *)              ABI="" ;;
esac
ASFETCH=""
[ -n "$ABI" ] && [ -x "$MODPATH/bin/$ABI/asfetch" ] && ASFETCH="$MODPATH/bin/$ABI/asfetch"
BB=""
for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox; do
    [ -x "$bb" ] && BB="$bb" && break
done

# Proxy support: honor http_proxy / ALL_PROXY env vars (set by user or VPN apps).
# In GFW environments this is essential for GitHub downloads.
_pxy_env() {
    local _e=""
    [ -n "$http_proxy" ] && _e="http_proxy=$http_proxy $_e"
    [ -n "$ALL_PROXY" ] && _e="ALL_PROXY=$ALL_PROXY $_e"
    echo "$_e"
}

# asfetch first (connects IPv4-first, works on IPv6-only-DNS networks); fall
# through to busybox wget / curl if it ever fails on a host.
dl_out() {
    if [ -n "$ASFETCH" ]; then eval "$(_pxy_env)" $ASFETCH -T 20 "$1" 2>/dev/null && return 0; fi
    if [ -n "$BB" ]; then eval "$(_pxy_env)" $BB wget -q -T 20 -O - "$1" 2>/dev/null && return 0; fi
    if command -v curl >/dev/null 2>&1; then eval "$(_pxy_env)" curl -fsSL --max-time 20 "$1" 2>/dev/null && return 0; fi
    if command -v wget >/dev/null 2>&1; then eval "$(_pxy_env)" wget -q -T 20 -O - "$1" 2>/dev/null && return 0; fi
    return 1
}
dl_to() {
    if [ -n "$ASFETCH" ]; then rm -f "$1"; eval "$(_pxy_env)" $ASFETCH -T 60 -o "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    if [ -n "$BB" ]; then rm -f "$1"; eval "$(_pxy_env)" $BB wget -q -T 60 -O "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    if command -v curl >/dev/null 2>&1; then rm -f "$1"; eval "$(_pxy_env)" curl -fsSL --max-time 60 -o "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    if command -v wget >/dev/null 2>&1; then rm -f "$1"; eval "$(_pxy_env)" wget -q -T 60 -O "$1" "$2" 2>/dev/null; [ -s "$1" ] && return 0; fi
    return 1
}

# --- Header ---
echo ""
echo "  $LINE"
row "🛡️" "TieJia  ${VER}"
echo "  $LINE"
echo ""
row "⏳" "初始化中..."
sleep 3

# --- Step 1: Target list ---
# Interactive menu: Vol+/Vol- to choose mode, Power to confirm.
# Three modes: auto (default, GMS only with !), certchain (?), force (!)
if [ -x "$MODPATH/build_target_txt.sh" ]; then
    TGT_MODE=$(tr -d '\r' < "$CONFIG_DIR/target_mode" 2>/dev/null)
    case "$TGT_MODE" in
        auto|force|certchain) ;;
        *) TGT_MODE="auto" ;;
    esac

    # Map current mode to menu index
    case "$TGT_MODE" in
        auto)      _idx=0 ;;
        certchain) _idx=1 ;;
        force)     _idx=2 ;;
    esac

    echo ""
    echo "    音量 +/- 切换  |  电源键确认  |  8s 超时使用当前"
    echo "    ─────────────────────────────────"

    _render_menu() {
        printf "\033[3A\r" 2>/dev/null
        [ 0 -eq $_idx ] && echo "    ▶ 自动      默认, 仅 GMS 加 !" || echo "      自动      默认, 仅 GMS 加 !"
        [ 1 -eq $_idx ] && echo "    ▶ 生成证书链  全部 app 加 ?"     || echo "      生成证书链  全部 app 加 ?"
        [ 2 -eq $_idx ] && echo "    ▶ 修改证书链  全部 app 加 !"     || echo "      修改证书链  全部 app 加 !"
    }

    _render_menu

    _wait=0; _done=0
    # Verify getevent is accessible; skip menu if denied (some kernels block it)
    if [ -e /dev/input/event0 ] && getevent -lc 1 /dev/input/event0 >/dev/null 2>&1; then
        while [ $_wait -lt 80 ]; do
            _evt=$(getevent -lc 1 2>/dev/null)
            if echo "$_evt" | grep -q "KEY_VOLUMEUP"; then
                _idx=$(( (_idx + 1) % 3 ))
                _render_menu
            elif echo "$_evt" | grep -q "KEY_VOLUMEDOWN"; then
                _idx=$(( (_idx - 1 + 3) % 3 ))
                _render_menu
            elif echo "$_evt" | grep -q "KEY_POWER"; then
                _done=1; break
            fi
            sleep 0.1; _wait=$((_wait + 1))
        done
    else
        _wait=80  # force timeout, use current mode
    fi
    echo ""

    # Resolve selection
    case $_idx in
        0) TGT_MODE="auto" ;;
        1) TGT_MODE="certchain" ;;
        2) TGT_MODE="force" ;;
    esac
    # Persist for build_target_txt and next run
    echo "$TGT_MODE" > "$CONFIG_DIR/target_mode" 2>/dev/null
    row "🎯" "已选择: $TGT_MODE"
    sh "$MODPATH/build_target_txt.sh" --mode "$TGT_MODE" "$CONFIG_DIR/target.txt" >/dev/null 2>&1
fi
TGT_N=$(grep -cvE '^[[:space:]]*$' "$CONFIG_DIR/target.txt" 2>/dev/null)
row "🎯" "${TGT_N:-0} 个应用 > 目标列表"
sleep 1

# --- Step 2: Keybox ---
# Custom-keybox mode (WebUI toggle): user supplied their own keybox, skip fetch.
if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    if [ -s "$CONFIG_DIR/keybox.xml" ] && is_valid_keybox "$CONFIG_DIR/keybox.xml"; then
        row "🔑" "自定义密钥 — 跳过获取"
        row "ℹ️" "在网页界面中关闭以自动获取"
    else
        row "⚠️" "未设置自定义密钥"
    fi
elif [ -x "$MODPATH/keybox_fetch.sh" ]; then
    # Volume key source selector:
    #   Vol+ → yurikey   Vol- → upstream   timeout (8s) → auto
    echo ""
    echo "    音量+ → Yurikey"
    echo "    音量- → KOWX712"
    echo "    8s 无操作 → 自动"
    printf "    等待按键..."
    echo ""

    KB_SRC="auto"
    _wait=0
    while [ $_wait -lt 80 ]; do
        _evt=$(getevent -lc 1 2>/dev/null)
        if echo "$_evt" | grep -q "KEY_VOLUMEUP"; then
            KB_SRC="yurikey"; break
        elif echo "$_evt" | grep -q "KEY_VOLUMEDOWN"; then
            KB_SRC="upstream"; break
        fi
        sleep 0.1; _wait=$((_wait + 1))
        # visual feedback: dot every 1s (10 ticks)
        [ $((_wait % 10)) -eq 0 ] && printf "." 2>/dev/null
    done
    echo ""

    row "⌛" "下载密钥中 (${KB_SRC})..."
    sh "$MODPATH/keybox_fetch.sh" "$KB_SRC" >/dev/null 2>&1
    _krc=$?

    if [ $_krc -eq 0 ]; then
        row "✅" "密钥已更新"
    elif [ $_krc -eq 2 ]; then
        row "🔑" "密钥正常 (无需更新)"
    else
        row "⚠️" "密钥获取失败 — 使用现有密钥"
    fi
else
    row "⚠️" "密钥获取不可用"
fi
sleep 1

# --- Step 3: Fingerprint ---
# Three-tier fallback: native crawl (pif_native_fetch.sh, 15s timeout) →
# pif_native_fetch selective mode (10s timeout) → shipped static fingerprints.
# Guarantees a fingerprint even with no network at all.
FP_OK=0
FP_SRC=""

# Primary: native crawl, bounded to 15s total.
if [ -x "$MODPATH/pif_native_fetch.sh" ]; then
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 sh "$MODPATH/pif_native_fetch.sh" >"$CONFIG_DIR/autopif.log" 2>&1
    else
        sh "$MODPATH/pif_native_fetch.sh" >"$CONFIG_DIR/autopif.log" 2>&1
    fi
    if [ -s "$CONFIG_DIR/pif.prop" ] && grep -q "FINGERPRINT=" "$CONFIG_DIR/pif.prop"; then
        FP_OK=1; FP_SRC="native"
    fi
fi

if [ "$FP_OK" = 0 ]; then
    row "🔄" "尝试备用方案..."
    sleep 1

    # Fallback A: pif_native_fetch selective mode — bounded to 10s.
    if [ -x "$MODPATH/pif_native_fetch.sh" ]; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 10 sh "$MODPATH/pif_native_fetch.sh" -s -m >>"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
        else
            sh "$MODPATH/pif_native_fetch.sh" -s -m >>"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
        fi
        [ "$FP_OK" = 1 ] && FP_SRC="pif"
    fi

    # Fallback B: shipped static fingerprints (alternate between 2 each tap).
    if [ "$FP_OK" = 0 ]; then
        IDX_FILE="$CONFIG_DIR/.fp_idx"
        IDX=$(cat "$IDX_FILE" 2>/dev/null)
        if [ "$IDX" = "2" ]; then IDX=1; else IDX=2; fi
        echo "$IDX" > "$IDX_FILE" 2>/dev/null

        FB="$MODPATH/pif_fallback_${IDX}.prop"
        if [ -s "$FB" ] && grep -q "FINGERPRINT=" "$FB"; then
            cp -f "$FB" "$CONFIG_DIR/pif.prop"
            FP_OK=1; FP_SRC="local"
        fi
    fi
fi

case "$FP_SRC" in
    pif|native) row "🌐" "指纹正常" ;;
    local)      row "🌐" "指纹正常 (本地)" ;;
    *)          row "⚠️" "指纹获取失败" ;;
esac
sleep 1

# --- Step 4: Spoof settings + security patch ---
for f in "$MODPATH/custom.pif.prop" "$MODPATH/pif.prop" \
         "$CONFIG_DIR/custom.pif.prop" "$CONFIG_DIR/pif.prop"; do
    [ -f "$f" ] || continue
    for kv in spoofProvider=0 spoofVendingFinger=1 spoofBuild=1 \
              spoofProps=1 spoofSignature=0 spoofVendingSdk=0; do
        k="${kv%=*}"; v="${kv#*=}"
        if grep -qE "^${k}=" "$f"; then
            $SED "s|^${k}=.*|${k}=${v}|" "$f"
        else
            echo "${k}=${v}" >> "$f"
        fi
    done
done

PATCH=""
[ -f "$MODPATH/sync_patch.sh" ] && PATCH=$(sh "$MODPATH/sync_patch.sh" boot 2>/dev/null)

pick_pif() {
    for f in "$CONFIG_DIR/custom.pif.prop" "$MODPATH/custom.pif.prop" \
             "$CONFIG_DIR/pif.prop" "$MODPATH/pif.prop"; do
        [ -s "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}
PIF=$(pick_pif)
if [ -n "$PIF" ]; then
    MD=$(grep -m1 '^MODEL=' "$PIF" 2>/dev/null | cut -d= -f2-)
    [ -z "$PATCH" ] && PATCH=$(grep -m1 '^SECURITY_PATCH=' "$PIF" 2>/dev/null | cut -d= -f2-)
fi

row "🗓️" "${PATCH:-unknown}"
sleep 1

# --- Step 5: Device ---
row "📱" "${MD:-unknown}"
sleep 1

# --- Restart PI + status ---
killall -9 com.google.android.gms.unstable 2>/dev/null
killall -9 com.android.vending 2>/dev/null
am force-stop com.android.vending >/dev/null 2>&1 &

if [ -x "$MODPATH/status_fetch.sh" ]; then
    MODPATH="$MODPATH" sh "$MODPATH/status_fetch.sh" manual >/dev/null 2>&1
fi
# Refresh WebUI preload JSON so toggles/states render instantly on next open.
if [ -x "$MODPATH/status_json.sh" ]; then
    sh "$MODPATH/status_json.sh" >/dev/null 2>&1
fi

# --- WebUI: Magisk only (background, silent) ---
if [ -d /data/adb/magisk ] && [ "$KSU" != "true" ] && [ "$APATCH" != "true" ]; then
    PKG=io.github.a13e300.ksuwebui
    [ -n "$(find "$MODPATH/.webui_busy" -mmin +5 2>/dev/null)" ] && rm -f "$MODPATH/.webui_busy" 2>/dev/null
    if ! pm path "$PKG" >/dev/null 2>&1 && [ ! -f "$MODPATH/.webui_busy" ]; then
        : > "$MODPATH/.webui_busy"
        {
            T=/data/local/tmp/.aswebui.apk
            API="https://api.github.com/repos/KOWX712/KsuWebUIStandalone/releases/latest"
            FB="https://github.com/KOWX712/KsuWebUIStandalone/releases/download/v1.0/KsuWebUI-1.0-48-release.apk"
            URL=$(dl_out "$API" 2>/dev/null | grep -o 'https://[^"]*\.apk' | head -1)
            [ -z "$URL" ] && URL="$FB"
            if dl_to "$T" "$URL" && [ -s "$T" ]; then
                # basic APK integrity: must start with PK zip magic and be > 10KB
                if head -c2 "$T" 2>/dev/null | grep -q 'PK' && [ "$(wc -c < "$T")" -gt 10240 ]; then
                    chmod 644 "$T" 2>/dev/null
                    pm install -r "$T" >/dev/null 2>&1
                fi
            fi
            rm -f "$T" "$MODPATH/.webui_busy" 2>/dev/null
        } &
    fi
fi

# --- Done ---
echo "  $LINE"
row "✅" "完成"
echo "  $LINE"
echo ""
echo "  $LINE"
echo ""

if { [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; } \
   && [ "$KSU_NEXT" != "true" ] && [ "$WKSU" != "true" ] && [ "$MMRL" != "true" ]; then
    sleep 2
fi
