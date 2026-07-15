#!/system/bin/sh
# proc_obfuscate.sh — /proc 信息伪装（增强版，对齐 Specter 16 关键词覆盖）
# AlwaysStrong v1.3.0
# 对目标 App 隐藏 /proc/pid/ 下的 maps/mounts/status/wchan 等 root 痕迹
# v1.3.0 扩展过滤列表对齐 Specter: 16 关键词 + 11 个模块路径模式

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

OBFUSCATE_DIR="${MODDIR}/proc_obfuscate"
TARGET_LIST="${OBFUSCATE_DIR}/targets.txt"

log_save "AlwaysStrong: proc obfuscation started (enhanced)"

[ -f "$TARGET_LIST" ] || { log_save "AlwaysStrong: no targets.txt — skipping proc obfuscation"; exit 0; }

# ---- maps 过滤关键词（对齐 Specter 16 类） ----
# Specter 列表: root lib, zygisk, riru, shamiko, kernelpatch, lspd, magisk,
#               kitsune, kpm, module path, libsu, libsqlite, libnative
# AlwaysStrong 扩展: 增加 edxposed, dreamland, taichi, xposed, suhide
MAPS_FILTER="libkpm|libkpti|libsu|libsqlite|libnative|zygisk|riru|shamiko|kernelpatch|lspd|magisk|kitsune|edxposed|dreamland|taichi|suhide|lib/arm64.*modules|lib/arm.*modules"

# ---- mounts/mountinfo 过滤关键词 ----
MOUNTS_FILTER="overlay|magisk|KSU|ksu|apatch|riru|zygisk|lspd|mirror|modules"

# ---- 状态文件伪造值 ----
TRACERPID_MASK="0"
WCHAN_MASK="ep_poll"

# ---- 模块路径模式（用于从 maps 行中滤除） ----
MODULE_PATH_PATTERNS="
/data/adb/modules/
/data/adb/ksu/
/data/adb/ap/
/sbin/.magisk/
/debug_ramdisk/
"

while IFS= read -r target_pkg; do
    [ -z "$target_pkg" ] && continue
    case "$target_pkg" in \#*) continue ;; esac

    pid_list="$(pgrep -f "$target_pkg" 2>/dev/null)"
    [ -z "$pid_list" ] && continue

    for pid in $pid_list; do
        verify_proc_name "$pid" "$target_pkg" || continue

        # ---- /proc/pid/maps ----
        maps_file="/proc/$pid/maps"
        if [ -f "$maps_file" ] && grep -qE "$MAPS_FILTER" "$maps_file" 2>/dev/null; then
            # 对目标进程隐藏 maps 中的敏感映射行
            # 通过 mount bind 一个过滤后的 maps 文件
            tmp_maps="${OBFUSCATE_DIR}/maps_${pid}"
            grep -vE "$MAPS_FILTER" "$maps_file" > "$tmp_maps" 2>/dev/null
            for pattern in $MODULE_PATH_PATTERNS; do
                [ -f "$tmp_maps" ] && grep -v "$pattern" "$tmp_maps" > "${tmp_maps}.tmp" 2>/dev/null && \
                    mv "${tmp_maps}.tmp" "$tmp_maps" 2>/dev/null
            done
            mount --bind "$tmp_maps" "$maps_file" 2>/dev/null
            log_save "AlwaysStrong: obfuscated maps for $target_pkg (pid=$pid)"
        fi

        # ---- /proc/pid/status (TracerPid) ----
        status_file="/proc/$pid/status"
        if [ -f "$status_file" ]; then
            current_tracer="$(grep "^TracerPid:" "$status_file" 2>/dev/null | awk '{print $2}')"
            if [ "$current_tracer" != "$TRACERPID_MASK" ] && [ "$current_tracer" != "0" ]; then
                tmp_status="${OBFUSCATE_DIR}/status_${pid}"
                sed "s/^TracerPid:[[:space:]]*[0-9]*/TracerPid:\t$TRACERPID_MASK/" "$status_file" > "$tmp_status" 2>/dev/null
                mount --bind "$tmp_status" "$status_file" 2>/dev/null
                log_save "AlwaysStrong: masked TracerPid for $target_pkg (pid=$pid)"
            fi
        fi

        # ---- /proc/pid/wchan ----
        wchan_file="/proc/$pid/wchan"
        if [ -f "$wchan_file" ]; then
            current_wchan="$(cat "$wchan_file" 2>/dev/null)"
            case "$current_wchan" in
                *supercall*|*kp_*|*kernelpatch*|*kpm*|*kpti*)
                    echo "$WCHAN_MASK" > "${OBFUSCATE_DIR}/wchan_${pid}" 2>/dev/null
                    mount --bind "${OBFUSCATE_DIR}/wchan_${pid}" "$wchan_file" 2>/dev/null
                    log_save "AlwaysStrong: masked wchan for $target_pkg (pid=$pid)"
                    ;;
            esac
        fi

        # ---- /proc/pid/mounts ----
        mounts_file="/proc/$pid/mounts"
        if [ -f "$mounts_file" ] && grep -qiE "$MOUNTS_FILTER" "$mounts_file" 2>/dev/null; then
            tmp_mounts="${OBFUSCATE_DIR}/mounts_${pid}"
            grep -ivE "$MOUNTS_FILTER" "$mounts_file" > "$tmp_mounts" 2>/dev/null
            mount --bind "$tmp_mounts" "$mounts_file" 2>/dev/null
            log_save "AlwaysStrong: obfuscated mounts for $target_pkg (pid=$pid)"
        fi

        # ---- /proc/pid/mountinfo ----
        mountinfo="/proc/$pid/mountinfo"
        if [ -f "$mountinfo" ] && grep -qiE "$MOUNTS_FILTER" "$mountinfo" 2>/dev/null; then
            tmp_info="${OBFUSCATE_DIR}/mountinfo_${pid}"
            grep -ivE "$MOUNTS_FILTER" "$mountinfo" > "$tmp_info" 2>/dev/null
            mount --bind "$tmp_info" "$mountinfo" 2>/dev/null
        fi

    done
done < "$TARGET_LIST"

log_save "AlwaysStrong: proc obfuscation done"

unset OBFUSCATE_DIR TARGET_LIST MAPS_FILTER MOUNTS_FILTER TRACERPID_MASK WCHAN_MASK MODULE_PATH_PATTERNS
unset target_pkg pid_list pid tmp_maps maps_file tmp_status status_file current_tracer
unset wchan_file current_wchan mounts_file tmp_mounts mountinfo tmp_info pattern
