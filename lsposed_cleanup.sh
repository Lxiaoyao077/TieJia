#!/system/bin/sh
# lsposed_cleanup.sh — LSPosed/Xposed 痕迹清理
# AlwaysStrong v1.3.0
# 已安装 LSPosed → 仅清缓存/泄露点，不触碰模块本体
# 未安装 LSPosed → 深度清理所有残留目录/属性

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_save "AlwaysStrong: LSPosed cleanup started"

# ---- 安全闸：检测 LSPosed 是否当前已安装 ----
LSPOSED_ACTIVE=false
LSPOSED_MODULES="
/data/adb/modules/zygisk_lsposed
/data/adb/modules/riru_lsposed
/data/adb/modules/LSPosed
/data/adb/modules/lsposed
"

for mod in $LSPOSED_MODULES; do
    if [ -d "$mod" ] && [ -f "$mod/module.prop" ]; then
        # 确认不是 disabled 状态（KSU/APatch 用 disable 文件标记）
        if [ ! -f "$mod/disable" ] && [ ! -f "$mod/remove" ]; then
            LSPOSED_ACTIVE=true
            break
        fi
    fi
done

# 额外检查：lspd 进程是否存活（二次确认）
if $LSPOSED_ACTIVE; then
    log_save "AlwaysStrong: LSPosed is active — safe mode (cache-only cleanup)"
else
    # 未通过模块目录检测，再通过 daemon 二次确认
    if [ -f /data/adb/lspd/daemon ] || pgrep -f lspd >/dev/null 2>&1; then
        LSPOSED_ACTIVE=true
        log_save "AlwaysStrong: LSPosed detected via daemon — safe mode"
    else
        log_save "AlwaysStrong: LSPosed not active — deep cleanup mode"
    fi
fi

# ============================================================
# 以下操作对已安装/未安装均安全
# ============================================================

# --- 1. XSharedPreferences 缓存（已知检测泄露点，无论是否安装都应清理）---
rm -rf /data/resource-cache/lspd_xml* 2>/dev/null
rm -rf /data/misc/lspd 2>/dev/null
rm -rf /data/misc/lsposed 2>/dev/null
rm -rf /data/misc/lspd_* 2>/dev/null
log_save "AlwaysStrong: cleaned XSharedPreferences cache"

# --- 2. 清理其他模块的残留目录（无 module.prop 的孤儿目录）---
STALE_MODULES="
/data/adb/modules/edxposed
/data/adb/modules/riru_edxposed
/data/adb/modules/taichi
/data/adb/modules/dreamland
"

for stale in $STALE_MODULES; do
    if [ -d "$stale" ] && [ ! -f "$stale/module.prop" ]; then
        rm -rf "$stale" 2>/dev/null
        log_save "AlwaysStrong: removed stale module $(basename "$stale")"
    fi
    if [ -d "$stale" ] && [ -f "$stale/remove" ]; then
        rm -rf "$stale" 2>/dev/null
        log_save "AlwaysStrong: removed marked-for-removal $(basename "$stale")"
    fi
done

# ============================================================
# 以下操作仅在未安装 LSPosed 时执行（深度清理）
# ============================================================
if ! $LSPOSED_ACTIVE; then

    # --- 3. 清理残留目录 ---
    LSPOSED_PATHS="
    /data/adb/lspd
    /data/adb/lsposed
    /data/adb/daemon/lspd
    "

    for path in $LSPOSED_PATHS; do
        if [ -d "$path" ]; then
            rm -rf "$path" 2>/dev/null
            log_save "AlwaysStrong: removed LSPosed dir $path"
        fi
    done

    # --- 4. 清理模块目录中已卸载的 LSPosed 残留 ---
    for mod_dir in /data/adb/modules/*lsposed* /data/adb/modules/*LSPosed* /data/adb/modules/*lspd*; do
        if [ -d "$mod_dir" ]; then
            rm -rf "$mod_dir" 2>/dev/null
            log_save "AlwaysStrong: removed LSPosed module $mod_dir"
        fi
    done

    # --- 5. 清理 service.d 中的孤儿脚本 ---
    for svc_script in /data/adb/service.d/*lsposed* /data/adb/service.d/*lspd* /data/adb/service.d/*xposed*; do
        if [ -f "$svc_script" ]; then
            rm -f "$svc_script" 2>/dev/null
            log_save "AlwaysStrong: removed service script $(basename "$svc_script")"
        fi
    done

    # --- 6. 清理 post-fs-data.d ---
    for pfs_script in /data/adb/post-fs-data.d/*lsposed* /data/adb/post-fs-data.d/*lspd* /data/adb/post-fs-data.d/*xposed*; do
        [ -f "$pfs_script" ] && rm -f "$pfs_script" 2>/dev/null
    done

    # --- 7. 清理 Xposed 桥接残留 ---
    XPOSED_BRIDGE="
    /system/framework/XposedBridge.jar
    /system/framework/lsposed.dex
    "
    for xpath in $XPOSED_BRIDGE; do
        [ -f "$xpath" ] && rm -f "$xpath" 2>/dev/null
    done

    # --- 8. 清理孤立属性 ---
    LSPOSED_PROPS="
    ro.lsposed.version
    ro.lsposed.enabled
    persist.lsposed.enabled
    ro.lsposed.api.version
    ro.lsposed.debug
    init.svc.lspd
    persist.lspd.status
    ro.xposed.version
    ro.xposed.enabled
    "

    for prop in $LSPOSED_PROPS; do
        current_val="$(getprop "$prop" 2>/dev/null)"
        if [ -n "$current_val" ]; then
            resetprop -d "$prop" 2>/dev/null || true
            log_save "AlwaysStrong: cleared prop $prop"
        fi
    done

else
    # ---- 已安装 LSPosed：仅做非破坏性清理 ----

    # 注意：不碰 /data/adb/lspd/cache（存编译后的 hook 字节码，删除会导致
    # LSPosed 重新编译，期间 hooks 短暂失效，属于功能破坏）

    # 仅清理旧日志（超过 7 天），不影响任何功能
    LSPD_LOG="/data/adb/lspd/log"
    if [ -d "$LSPD_LOG" ]; then
        find "$LSPD_LOG" -name "*.log" -mtime +7 -delete 2>/dev/null
    fi

    log_save "AlwaysStrong: safe mode — old logs only (LSPosed is active)"
fi

log_save "AlwaysStrong: LSPosed cleanup done"

unset LSPOSED_ACTIVE LSPOSED_MODULES LSPOSED_PATHS LSPOSED_PROPS STALE_MODULES XPOSED_BRIDGE
unset LSPD_CACHE LSPD_LOG mod mod_dir path stale svc_script pfs_script xpath prop current_val
