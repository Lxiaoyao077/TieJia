---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 64101255277264a7b73fb34a1faf8f26_b41540b2807111f1b7a1525400826444
    ReservedCode1: rbS1lX+9uxpWHbJcDGfhhVNUA6kpmTnOoVY2qwnkQphveEktkUjXUTaQeHspenx5xC+ixXZHExQxgPSZ3zmQcxRoWI7f+Q/tx9wtehWiqEVI6bkS8PdwFndzOXXiziLvXBgpzRzlsrfWCCIrjdHBJav/c6y6KrXI5pnF25fimMDGuX4iZbsv8vtRwvM=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 64101255277264a7b73fb34a1faf8f26_b41540b2807111f1b7a1525400826444
    ReservedCode2: rbS1lX+9uxpWHbJcDGfhhVNUA6kpmTnOoVY2qwnkQphveEktkUjXUTaQeHspenx5xC+ixXZHExQxgPSZ3zmQcxRoWI7f+Q/tx9wtehWiqEVI6bkS8PdwFndzOXXiziLvXBgpzRzlsrfWCCIrjdHBJav/c6y6KrXI5pnF25fimMDGuX4iZbsv8vtRwvM=
---

# TieJia Changelog

## v1.4.10 (2026-07-16) — 10-bug 安全健壮性热修复
- P0: autopif4.sh find_busybox() 无限递归栈溢出修复
- P1: sync_patch.sh sed -i 回退、target_cleanup.sh 黑名单正则转义、pif_native_fetch.sh fetch() 最小 16 字节校验、logcat_cleanup.sh SED 未定义兜底
- P2: autopif4.sh $RANDOM bashism、boot_hash.sh ${hash:0:16} bashism、autopif.sh(LEGACY) busybox 前置检查 + verify_proc_name 收紧、prop_unify.sh 指纹解析非空校验
- P3: service.sh PID 追踪 (.tiejia_bg_pids)，覆盖全部 12 个后台守护进程

## v1.4.8 (2026-07-16) — 全量审计修复
- P1(4): keybox_rotate.sh 缺 SED 定义、keybox_fetch/sync_patch awk tolower 不可移植、service.sh CONFIG_DIR 未定义、conflict_scan.sh IFS 分词错误
- P2(6): target_cleanup.sh od 不存在、boot_state_props.sh set -e 过早退出、sync_patch.sh awk tolower、action.sh 按键等待无反馈、autopif4.sh nc 不存在、prop_unify.sh 指纹校验弱
- P3: common_func.sh 新增 lowercase/fetch_url/find_busybox/detect_abi/ensure_trailing_newline + TIEJIA_CONFIG_DIR 全局常量
- P3: action.sh APK 下载加 PK 魔数校验、mount_isolation.sh target.txt 加随机盐、hourly 刷新并行化
- P3: autopif.sh 标记为遗留兜底
- 硬编码路径统一收敛到 TIEJIA_CONFIG_DIR

## v1.4.7 (2026-07-16) — Specter 借鉴功能 + KSU 云更新
- 实现 rom_fp_cleanup (Phase 3) + boot_state_props (bootmode 伪装 + persistent_properties 扫描)
- 27 脚本全量 9 问审计，修复 P1(4) + P2(8)
- GitHub Release v1.4.7 + update.json + changelog.md，versionCode 122→147
- Release 资产重命名：AlwaysStrong-*.zip → TieJia-*.zip
*（内容由AI生成，仅供参考）*
