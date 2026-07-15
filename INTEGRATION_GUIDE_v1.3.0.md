# AlwaysStrong v1.2.0 → v1.3.0 隐藏增强集成指南

## 新增脚本（已在 output/ 目录生成）

| 文件 | 行数 | 用途 |
|------|------|------|
| `rom_fingerprint.sh` | 108 | ROM 指纹深度擦除（26 种 ROM 前缀） |
| `adb_harden.sh` | 82 | ADB / Recovery 残留清理 + SEAndroid 强制 |
| `detect_cleanup.sh` | 72 | 22 个检测 App 缓存 / 临时文件清理 |
| `lsposed_cleanup.sh` | 121 | LSPosed 痕迹清理（已安装仅清日志+缓存） |
| `hma_config.sh` | 59 | HMA 默认隐藏规则注入 |
| `pihooks_block.sh` | 107 | ROM 内置 PI Spoof 引擎检测与禁用 |
| `gms_kill.sh` | 77 | GMS/DroidGuard 强制停止 + Play 缓存清理 |
| `conflict_scan.sh` | 132 | 增强冲突检测（3 级系统 + toggle.val） |
| `mount_isolation.sh` | 75 | 挂载隐藏增强（对齐 Specter 关键词覆盖） |
| `proc_obfuscate.sh` | 116 | /proc 伪装增强（对齐 Specter 16 关键词） |

---

## 1. customize.sh 变更

在安装列表中新增以下脚本：

```bash
cp -f "$MODPATH/rom_fingerprint.sh"   "$MODPATH/rom_fingerprint.sh"   2>/dev/null
cp -f "$MODPATH/adb_harden.sh"        "$MODPATH/adb_harden.sh"        2>/dev/null
cp -f "$MODPATH/detect_cleanup.sh"    "$MODPATH/detect_cleanup.sh"    2>/dev/null
cp -f "$MODPATH/lsposed_cleanup.sh"   "$MODPATH/lsposed_cleanup.sh"   2>/dev/null
cp -f "$MODPATH/hma_config.sh"        "$MODPATH/hma_config.sh"        2>/dev/null
cp -f "$MODPATH/pihooks_block.sh"     "$MODPATH/pihooks_block.sh"     2>/dev/null
cp -f "$MODPATH/gms_kill.sh"          "$MODPATH/gms_kill.sh"          2>/dev/null
cp -f "$MODPATH/conflict_scan.sh"     "$MODPATH/conflict_scan.sh"     2>/dev/null

set_perm "$MODPATH/rom_fingerprint.sh"   0 0 0755
set_perm "$MODPATH/adb_harden.sh"        0 0 0755
set_perm "$MODPATH/detect_cleanup.sh"    0 0 0755
set_perm "$MODPATH/lsposed_cleanup.sh"   0 0 0755
set_perm "$MODPATH/hma_config.sh"        0 0 0755
set_perm "$MODPATH/pihooks_block.sh"     0 0 0755
set_perm "$MODPATH/gms_kill.sh"          0 0 0755
set_perm "$MODPATH/conflict_scan.sh"     0 0 0755
```

---

## 2. service.sh 变更

### 2.1 启动 pipeline（在 resetprop 块之后，按依赖顺序）

```bash
# ---- v1.3.0 隐藏增强 pipeline ----

# Step 1: 冲突检测（必须最先，可能禁用其他模块影响后续逻辑）
[ -f "$MODDIR/conflict_scan.sh" ] && "$MODDIR/conflict_scan.sh"

# Step 2: PIHooks 禁用（在 resetprop 之前阻止 ROM spoof 引擎篡改属性）
[ -f "$MODDIR/pihooks_block.sh" ] && "$MODDIR/pihooks_block.sh" &

# Step 3: ROM 指纹擦除（resetprop 集中管理）
[ -f "$MODDIR/rom_fingerprint.sh" ] && "$MODDIR/rom_fingerprint.sh" &

# Step 4: ADB 硬化
[ -f "$MODDIR/adb_harden.sh" ] && "$MODDIR/adb_harden.sh" &

# Step 5: LSPosed 清理
[ -f "$MODDIR/lsposed_cleanup.sh" ] && "$MODDIR/lsposed_cleanup.sh" &

# Step 6: HMA 配置
[ -f "$MODDIR/hma_config.sh" ] && "$MODDIR/hma_config.sh" &
```

### 2.2 action.sh 中 keybox 获取后立即执行 gms_kill

```bash
# 在 action.sh 的 keybox 获取/更新流程之后，插入：
#   拿到新 keybox → 立即杀 GMS，清缓存 PI 状态
if [ -f "$MODDIR/gms_kill.sh" ]; then
    log_save "AlwaysStrong: post-keybox — running gms_kill"
    "$MODDIR/gms_kill.sh"
fi
```

### 2.3 定时任务

```bash
# detect_cleanup.sh — 每 6 小时清理检测痕迹
(
    while true; do
        sleep 21600
        [ -f "$MODDIR/detect_cleanup.sh" ] && "$MODDIR/detect_cleanup.sh"
    done
) &
```

---

## 3. toggle.val 特性开关

`conflict_scan.sh` 首次运行自动生成 `/data/adb/modules/AlwaysStrong/toggle.val`：

```
rom_fingerprint=enabled
detect_cleanup=enabled
lsposed_cleanup=enabled
adb_harden=enabled
pihooks_block=enabled
gms_kill=enabled
conflict_scan=enabled
keybox_rotate=enabled
target_cleanup=enabled
boot_hash=enabled
```

用户将 `enabled` 改为 `disabled` 即可关闭对应功能，下次执行时跳过。

---

## 4. service.sh 可移除的重复代码

`rom_fingerprint.sh` 已覆盖以下 resetprop，可从 service.sh 中删除：

```bash
# 可移除（已在 rom_fingerprint.sh 中处理）
resetprop ro.debuggable 0
resetprop ro.secure 1
resetprop ro.adb.secure 1
resetprop ro.boot.verifiedbootstate green
resetprop ro.boot.flash.locked 1
```

---

## 5. mount_isolation.sh / proc_obfuscate.sh 增强点

| 脚本 | 原有关键词数 | v1.3.0 | 新增 |
|------|------------|--------|------|
| `mount_isolation.sh` | ~4 | 12 | apatch, riru, zygisk, KSU(大小写), kernelpatch, kitsune, modules_update, debug_ramdisk, mirror |
| `proc_obfuscate.sh` | ~8 | 16+11 | lspd, edxposed, dreamland, taichi, suhide, kpm, kpti, 模块路径模式 |

---

## 6. 版本号

```
version=v1.3.0
versionCode=130
```
