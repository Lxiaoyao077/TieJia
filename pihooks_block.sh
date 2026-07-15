#!/system/bin/sh
# pihooks_block.sh — ROM 内置 PI Spoof 引擎检测与禁用
# AlwaysStrong v1.3.0
# 检测并禁 ROM 自带的 PropImitationHooks / PixelPropsUtils / CertifiedPropsOverlay
# 避免与 AlwaysStrong 的 PI 伪装产生属性覆写竞争

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_save "AlwaysStrong: PIHooks detection started"

PIHOOKS_DETECTED=false

# =============================================
# 检测 1: PropImitationHooks (PixelOS / PA / Afterlife 等 ROM)
# =============================================
PIHOOKS_PROPS="
ro.aospa.version
net.pixelos.version
ro.afterlife.version
ro.pixys.version
ro.candy.version
ro.cipher.version
ro.elixir.version
ro.everest.version
ro.evolution.version
ro.hentai.version
ro.infinity.version
ro.octavi.version
ro.palladium.version
ro.pe.version
ro.proton.version
ro.stag.version
ro.syberia.version
ro.tequila.version
ro.xtended.version
ro.spark.version
ro.crdroid.version
ro.lineage.version
"

for prop in $PIHOOKS_PROPS; do
    val="$(getprop "$prop" 2>/dev/null)"
    if [ -n "$val" ]; then
        PIHOOKS_DETECTED=true
        log_save "AlwaysStrong: detected PIHooks via $prop=$val"
    fi
done

# 检测 gms_certified_props.json（PIHooks 的通用标记文件）
if [ -f /data/system/gms_certified_props.json ]; then
    PIHOOKS_DETECTED=true
    log_save "AlwaysStrong: detected PIHooks via gms_certified_props.json"
fi

# =============================================
# 检测 2: PixelPropsUtils (常见于类原生 ROM)
# =============================================
# PixelPropsUtils 通过 framework 注入，特征是在 build.prop 中存在
# ro.product.brand=google 但 ro.build.fingerprint 却是第三方 ROM
if getprop ro.product.brand 2>/dev/null | grep -qi "google"; then
    fp="$(getprop ro.build.fingerprint 2>/dev/null)"
    if ! echo "$fp" | grep -qi "google"; then
        PIHOOKS_DETECTED=true
        log_save "AlwaysStrong: suspected PixelPropsUtils (brand=google but FP mismatch)"
    fi
fi

# =============================================
# 检测 3: CertifiedPropsOverlay (LineageOS 等)
# =============================================
if [ -f /product/etc/sysconfig/certifiedPropsOverlay.xml ] || \
   [ -f /system/product/etc/sysconfig/certifiedPropsOverlay.xml ] || \
   [ -f /system/etc/sysconfig/certifiedPropsOverlay.xml ]; then
    PIHOOKS_DETECTED=true
    log_save "AlwaysStrong: detected CertifiedPropsOverlay"
fi

# =============================================
# 禁用操作
# =============================================
if $PIHOOKS_DETECTED; then

    # PropImitationHooks 禁用方式：写入空 persist 标记（PIF 标准协议）
    # PIHooks 源码会检查这两个属性，存在即跳过 spoof
    resetprop persist.sys.pihooks.first_api_level "" 2>/dev/null || true
    resetprop persist.sys.pihooks.security_patch "" 2>/dev/null || true
    log_save "AlwaysStrong: disabled PIHooks via persist markers"

    # CertifiedPropsOverlay 禁用方式
    # 创建空白覆盖文件可阻止其加载（部分 ROM 支持）
    OVERLAY_PATHS="
    /product/etc/sysconfig/certifiedPropsOverlay.xml
    /system/product/etc/sysconfig/certifiedPropsOverlay.xml
    /system/etc/sysconfig/certifiedPropsOverlay.xml
    "
    for overlay in $OVERLAY_PATHS; do
        if [ -f "$overlay" ]; then
            # 重命名而非删除（删除可能导致 ROM OTA 校验失败）
            mv "$overlay" "${overlay}.pihooks_blocked" 2>/dev/null
            log_save "AlwaysStrong: blocked CertProp overlay $overlay"
        fi
    done

    # 清除可能已写入的冲突属性
    resetprop -n ro.product.brand "" 2>/dev/null || true
    resetprop -n ro.product.manufacturer "" 2>/dev/null || true
    resetprop -n ro.product.model "" 2>/dev/null || true
    resetprop -n ro.product.name "" 2>/dev/null || true
    resetprop -n ro.product.device "" 2>/dev/null || true

    log_save "AlwaysStrong: PIHooks blocked ($(getprop persist.sys.pihooks.first_api_level 2>/dev/null))"
else
    log_save "AlwaysStrong: no PIHooks detected — skipping"
fi

log_save "AlwaysStrong: PIHooks detection done"

unset PIHOOKS_DETECTED PIHOOKS_PROPS OVERLAY_PATHS prop val fp overlay
