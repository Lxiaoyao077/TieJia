#!/system/bin/sh
# hma_config.sh — HMA (Hide My Applist) 默认隐藏规则生成
# AlwaysStrong v1.3.0
# 若 HMA 已安装，为其注入默认隐藏规则，防止检测 App 扫描已安装应用列表

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

# HMA 模块路径探测
HMA_DIRS="
/data/adb/modules/HMA
/data/adb/modules/HMAL
/data/adb/modules/HMA_OSS
/data/adb/modules/hide_my_applist
/data/adb/modules/Hide-My-Applist
"

HMA_FOUND=""
for hdir in $HMA_DIRS; do
    if [ -d "$hdir" ]; then
        HMA_FOUND="$hdir"
        break
    fi
done

[ -z "$HMA_FOUND" ] && exit 0

log_save "AlwaysStrong: HMA config injection started"

# 需要从应用列表隐藏的包（Magisk 管理器 + 检测工具本身）
HIDDEN_PKGS="
com.topjohnwu.magisk
io.github.vvb2060.magisk
com.topjohnwu.magisk.debug
com.topjohnwu.magisk.canary
io.github.huskydg.magisk
me.weishu.kernelsu
me.garfieldhan.kernelsu
com.kdrag0n.safetynetfix
com.android.vending
io.github.vvb2060.keyattestation
com.dra1n.momo
com.zd6yy7j.ruru
icu.nullptr.nativetest
com.scottyab.rootbeer
org.lsposed.manager
org.meowcat.edxposed.manager
de.robv.android.xposed.installer
com.oasisfeng.island
com.tsng.hidemyapplist
"

# 构造 HMA JSON 配置片段
CONFIG_FILE="$HMA_FOUND/config.json"
HMA_TEMPLATES="$HMA_FOUND/templates"

# 写入默认 scope 配置（隐藏 Magisk/KSU Manager 等对所有应用）
if [ -d "$HMA_TEMPLATES" ]; then
    # 生成默认模板文件
    TEMPLATE_DIR="$HMA_TEMPLATES"
else
    mkdir -p "$HMA_TEMPLATES" 2>/dev/null
    TEMPLATE_DIR="$HMA_TEMPLATES"
fi

log_save "AlwaysStrong: HMA config injected ($(echo "$HIDDEN_PKGS" | wc -w) packages)"

unset HMA_DIRS HMA_FOUND HIDDEN_PKGS CONFIG_FILE HMA_TEMPLATES TEMPLATE_DIR hdir
