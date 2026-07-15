#!/system/bin/sh
# conflict_scan.sh — 增强冲突检测（Specter 风格 3 级系统 + toggle.val）
# AlwaysStrong v1.3.0
# 检测与 AlwaysStrong 冲突的模块，按 aggressive/moderate/passive 分级处理
# toggle.val 为单一真相源，用户可通过文件覆盖自动判断

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

TOGGLE_FILE="$MODDIR/toggle.val"
CONFLICTS_FILE="$MODDIR/conflicts.txt"

log_save "AlwaysStrong: enhanced conflict scan started"

# =============================================
# 冲突模块定义（分级）
# =============================================
# aggressive: 直接冲突，必须禁用
# moderate : 部分冲突，建议禁用
# passive  : 可共存，不加干预
# =============================================

CONFLICT_MODULES="
/data/adb/modules/playintegrityfix:aggressive:PIF
/data/adb/modules/PlayIntegrityFix:aggressive:PIF
/data/adb/modules/playintegrityfork:aggressive:PIF
/data/adb/modules/safetynet-fix:moderate:USNF
/data/adb/modules/safetynet-fix-v2:moderate:USNF
/data/adb/modules/universal-safetynet-fix:moderate:USNF
/data/adb/modules/MagiskHidePropsConf:moderate:MHPC
/data/adb/modules/xposed:passive:Xposed
/data/adb/modules/riru:passive:Riru
/data/adb/modules/trickystore:passive:TrickyStore
/data/adb/modules/TrickyStore:passive:TrickyStore
"

# =============================================
# toggle.val 解析（单一真相源）
# =============================================
# 格式: id=keep|aggressive|moderate|passive
# 示例: PIF=aggressive  表示强制 aggressive 处理 PIF
# 示例: PIF=keep        表示不处理（用户手动管理）
# =============================================

parse_toggle() {
    local id="$1"
    local default="$2"
    [ ! -f "$TOGGLE_FILE" ] && echo "$default" && return
    local val
    val="$(grep "^${id}=" "$TOGGLE_FILE" 2>/dev/null | cut -d= -f2)"
    [ -n "$val" ] && echo "$val" || echo "$default"
}

# =============================================
# _feature_should_run() — 统一运行入口
# =============================================
_feature_should_run() {
    local feature="$1"
    local toggle_val
    toggle_val="$(grep "^${feature}=" "$TOGGLE_FILE" 2>/dev/null | cut -d= -f2)"
    if [ "$toggle_val" = "disabled" ]; then
        return 1
    fi
    return 0
}

# =============================================
# 冲突检测主逻辑
# =============================================
aggressive_disabled=0
moderate_warned=0
passive_found=0

while IFS=: read -r mod_path level mod_id; do
    [ -z "$mod_path" ] && continue
    [ -d "$mod_path" ] || continue
    [ -f "$mod_path/disable" ] && continue  # 已禁用则跳过
    [ -f "$mod_path/remove" ] && continue   # 标记待删除则跳过

    # 读 toggle 覆盖
    final_level="$(parse_toggle "$mod_id" "$level")"
    [ "$final_level" = "keep" ] && continue

    case "$final_level" in
        aggressive)
            # 创建 disable 标记文件，禁止模块加载
            touch "$mod_path/disable" 2>/dev/null
            log_save "AlwaysStrong: [AGGRESSIVE] disabled $mod_id ($mod_path)"
            aggressive_disabled=$((aggressive_disabled + 1))

            # 如果是 PIF 类模块，同时移除其 props 覆盖
            case "$mod_id" in
                PIF|USNF)
                    resetprop -n ro.product.model "" 2>/dev/null || true
                    resetprop -n ro.product.brand "" 2>/dev/null || true
                    resetprop -n ro.product.name "" 2>/dev/null || true
                    resetprop -n ro.product.device "" 2>/dev/null || true
                    resetprop -n ro.product.manufacturer "" 2>/dev/null || true
                    resetprop -n ro.build.fingerprint "" 2>/dev/null || true
                    ;;
            esac
            ;;
        moderate)
            log_save "AlwaysStrong: [MODERATE] conflict with $mod_id — consider disabling"
            moderate_warned=$((moderate_warned + 1))
            ;;
        passive)
            log_save "AlwaysStrong: [PASSIVE] coexisting with $mod_id"
            passive_found=$((passive_found + 1))
            ;;
    esac
done <<-HEREDOC
$CONFLICT_MODULES
HEREDOC

# =============================================
# 写入冲突报告
# =============================================
{
    echo "# AlwaysStrong conflict report — $(date)"
    echo "# aggressive_disabled=$aggressive_disabled moderate_warned=$moderate_warned passive=$passive_found"
    echo "# toggle.val overrides:"
    [ -f "$TOGGLE_FILE" ] && cat "$TOGGLE_FILE" || echo "# (no overrides)"
} > "$CONFLICTS_FILE"

# =============================================
# 初始化默认 toggle.val（如果不存在）
# =============================================
if [ ! -f "$TOGGLE_FILE" ]; then
    {
        echo "# AlwaysStrong feature toggles"
        echo "# Format: feature_name=enabled|disabled"
        echo "# Delete this file and reboot to restore defaults"
        echo "rom_fingerprint=enabled"
        echo "detect_cleanup=enabled"
        echo "lsposed_cleanup=enabled"
        echo "adb_harden=enabled"
        echo "pihooks_block=enabled"
        echo "gms_kill=enabled"
        echo "conflict_scan=enabled"
        echo "keybox_rotate=enabled"
        echo "tmp_harden=enabled"
        echo "target_cleanup=enabled"
        echo "boot_hash=enabled"
    } > "$TOGGLE_FILE"
    log_save "AlwaysStrong: created default toggle.val"
fi

log_save "AlwaysStrong: conflict scan done (disabled=$aggressive_disabled warned=$moderate_warned found=$passive_found)"

unset CONFLICT_MODULES TOGGLE_FILE CONFLICTS_FILE
unset aggressive_disabled moderate_warned passive_found mod_path level mod_id final_level
