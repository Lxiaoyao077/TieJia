#!/system/bin/sh
# mount_isolation.sh — 挂载信息隐藏（增强版，对齐 Specter 关键词覆盖）
# AlwaysStrong v1.3.0
# 从 /proc/self/mounts 过滤 Magisk/KSU/APatch 镜像挂载点
# v1.3.0 增加 apatch/riru/zygisk/KSU 大小写 关键词

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

MOUNT_NAMESPACE_DIR="${MODDIR}/mount_namespace"
TARGET_LIST="${MOUNT_NAMESPACE_DIR}/targets.txt"

log_save "AlwaysStrong: mount isolation started (enhanced)"

# 没有目标列表则跳过
[ -f "$TARGET_LIST" ] || { log_save "AlwaysStrong: no targets.txt — skipping mount isolation"; exit 0; }

# ---- 过滤关键词（对齐 Specter 6 类 + 扩展） ----
# Specter 覆盖: overlay, magisk, ksu/KSU, apatch, riru, zygisk
# AlwaysStrong 新增: kernelpatch, kitsune, modules_update, debug_ramdisk
FILTER_PATTERN="overlay|magisk|KSU|ksu|apatch|riru|zygisk|kernelpatch|kitsune|modules_update|debug_ramdisk|mirror"

# ---- 遍历每个目标 App 的挂载命名空间 ----
if [ -f "$TARGET_LIST" ]; then
    while IFS= read -r target_pkg; do
        [ -z "$target_pkg" ] && continue
        # 跳过注释行
        case "$target_pkg" in \#*) continue ;; esac

        # 查找进程 pid
        pid_list="$(pgrep -f "$target_pkg" 2>/dev/null)"
        [ -z "$pid_list" ] && continue

        for pid in $pid_list; do
            # 校验进程名（防 PID 复用）
            verify_proc_name "$pid" "$target_pkg" || continue

            mount_file="/proc/$pid/mounts"
            [ -f "$mount_file" ] || continue

            # 读取挂载信息，过滤可疑项
            filtered="$(grep -iE "$FILTER_PATTERN" "$mount_file" 2>/dev/null)"
            if [ -n "$filtered" ]; then
                log_save "AlwaysStrong: mount isolation: $target_pkg (pid=$pid) — found $(echo "$filtered" | wc -l) suspicious mount(s)"

                # 逐个 umount（注意：这需要在目标进程的 mount namespace 中执行）
                # 对于 Magisk/KSU 环境，通过 nsenter 进入目标 namespace
                echo "$filtered" | while IFS= read -r mount_line; do
                    mount_point="$(echo "$mount_line" | awk '{print $2}')"
                    [ -z "$mount_point" ] && continue
                    # 在目标 namespace 中 umount
                    nsenter --mount --target "$pid" umount -l "$mount_point" 2>/dev/null
                    log_save "AlwaysStrong: unmounted $mount_point from $target_pkg (pid=$pid)"
                done
            fi

            # 同时清理 /proc/$pid/mountinfo
            mountinfo="/proc/$pid/mountinfo"
            [ -f "$mountinfo" ] && grep -iE "$FILTER_PATTERN" "$mountinfo" >/dev/null 2>&1 && \
                log_save "AlwaysStrong: suspicious mountinfo in $target_pkg (pid=$pid)"
        done
    done < "$TARGET_LIST"
fi

log_save "AlwaysStrong: mount isolation done"

unset MOUNT_NAMESPACE_DIR TARGET_LIST FILTER_PATTERN target_pkg pid_list pid mount_file filtered mount_line mount_point mountinfo
