#!/system/bin/sh
# AlwaysStrong action button.
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

CONFIG_DIR=/data/adb/tricky_store
LINE="========================="
VER=$(grep -m1 '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2-)

row() { echo "    $1   $2"; }

# --- ABI + fetchers (via common_func.sh) ---
resolve_asfetch "$MODPATH"
resolve_bb
    return 1
}

# --- Header ---
echo ""
echo "  $LINE"
row "🛡️" "AlwaysStrong  ${VER}"
echo "  $LINE"
echo ""
row "⏳" "初始化中..."
sleep 3

# --- Step 1: Target list ---
# build_target_txt reads persisted mode from CONFIG_DIR/target_mode,
# applies suffix accordingly (auto/force/certchain).
if [ -x "$MODPATH/build_target_txt.sh" ]; then
    TGT_MODE=$(tr -d '\r' < "$CONFIG_DIR/target_mode" 2>/dev/null)
    case "$TGT_MODE" in
        auto|force|certchain) ;;
        *) TGT_MODE="auto" ;;
    esac
    sh "$MODPATH/build_target_txt.sh" --mode "$TGT_MODE" "$CONFIG_DIR/target.txt" >/dev/null 2>&1
fi
TGT_N=$(grep -cvE '^[[:space:]]*$' "$CONFIG_DIR/target.txt" 2>/dev/null)
row "🎯" "${TGT_N:-0} 个应用 > 目标列表"
sleep 1

# --- Step 2: Keybox ---
# Custom-keybox mode (WebUI toggle): user supplied their own keybox, skip fetch.
if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    if [ -s "$CONFIG_DIR/keybox.xml" ] && head -c 4096 "$CONFIG_DIR/keybox.xml" | grep -q "Keybox"; then
        row "🔑" "自定义密钥 — 跳过获取"
        row "ℹ️" "在网页界面中关闭以自动获取"
    else
        row "⚠️" "未设置自定义密钥"
    fi
elif [ -x "$MODPATH/keybox_fetch.sh" ]; then
    if [ -s "$CONFIG_DIR/keybox.xml" ] && head -c 4096 "$CONFIG_DIR/keybox.xml" | grep -q "Keybox"; then
        sh "$MODPATH/keybox_fetch.sh" >/dev/null 2>&1 &
        row "🔑" "密钥正常"
    else
        sh "$MODPATH/keybox_fetch.sh" >/dev/null 2>&1 &
        row "⌛" "下载密钥中..."
        i=0
        while [ $i -lt 10 ]; do
            [ -s "$CONFIG_DIR/keybox.xml" ] && break
            sleep 1; i=$((i+1))
        done
        if [ -s "$CONFIG_DIR/keybox.xml" ] && head -c 4096 "$CONFIG_DIR/keybox.xml" | grep -q "Keybox"; then
            row "🔑" "密钥已更新"
        else
            row "⚠️" "密钥缺失"
        fi
    fi
else
    row "⚠️" "密钥获取不可用"
fi
sleep 1

# --- Step 3: Fingerprint ---
# PIF's zygisk reads custom.pif.prop from the module dir. autopif4 fetches a
# fresh Pixel fingerprint AND runs migrate.sh to produce that file, so it's the
# primary. If it stalls/fails we fall back to our native crawl (which now also
# migrates -> custom.pif.prop), then to shipped static props (also migrated).
# Every path ends with a valid custom.pif.prop; Step 4 enforces the STRONG spoof
# settings. A failed primary is shown once as "trying with fallback".
FP_OK=0
FP_SRC=""

# apply_pif SRC.prop — migrate a minimal pif.prop into the custom.pif.prop PIF
# reads (module dir), using the same tool autopif4 does.
apply_pif() {
    [ -f "$MODPATH/migrate.sh" ] || return 1
    cp -f "$1" "$MODPATH/pif.prop" 2>/dev/null
    rm -f "$MODPATH/custom.pif.prop" "$MODPATH/custom.pif.json" 2>/dev/null
    sh "$MODPATH/migrate.sh" -i -a "$MODPATH/pif.prop" >/dev/null 2>&1
    [ -s "$MODPATH/custom.pif.prop" ]
}

# 1. native crawl (PRIMARY) — fetches the same Google servers as autopif4 but
#    fast (~10s), and self-migrates -> custom.pif.prop. autopif4's own crawl
#    hangs ~45-90s on some devices (its factory-image HEAD stalls), so it's the
#    fallback now. Gate on the EXIT CODE (0 only when a fresh custom.pif.prop
#    was actually produced) — a stale one must not count as success.
if [ -x "$MODPATH/pif_native_fetch.sh" ]; then
    if command -v timeout >/dev/null 2>&1; then
        timeout 25 sh "$MODPATH/pif_native_fetch.sh" >"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
    else
        sh "$MODPATH/pif_native_fetch.sh" >"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
    fi
    [ "$FP_OK" = 1 ] && FP_SRC="native"
fi

if [ "$FP_OK" = 0 ]; then
    row "🔄" "尝试备用方案..."
    sleep 1

    # 2. autopif4 (FALLBACK) — upstream-maintained parser; self-migrates too.
    #    Bounded so its stalling crawl can't freeze the Action.
    if [ -f "$MODPATH/autopif4.sh" ]; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 40 sh "$MODPATH/autopif4.sh" -s -m >>"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
        else
            sh "$MODPATH/autopif4.sh" -s -m >>"$CONFIG_DIR/autopif.log" 2>&1 && FP_OK=1
        fi
        [ "$FP_OK" = 1 ] && FP_SRC="pif"
    fi

    # 3. shipped static props (alternate 2 each tap) — migrated so PIF reads them.
    if [ "$FP_OK" = 0 ]; then
        IDX_FILE="$CONFIG_DIR/.fp_idx"
        IDX=$(cat "$IDX_FILE" 2>/dev/null)
        if [ "$IDX" = "2" ]; then IDX=1; else IDX=2; fi
        echo "$IDX" > "$IDX_FILE" 2>/dev/null

        FB="$MODPATH/pif_fallback_${IDX}.prop"
        if [ -s "$FB" ] && grep -q "FINGERPRINT=" "$FB" && apply_pif "$FB"; then
            cp -f "$FB" "$CONFIG_DIR/pif.prop" 2>/dev/null
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
for pid in $(pidof com.google.android.gms.unstable 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
for pid in $(pidof com.android.vending 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
am force-stop com.android.vending >/dev/null 2>&1

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
                chmod 644 "$T" 2>/dev/null
                pm install -r "$T" >/dev/null 2>&1
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
