#!/system/bin/sh
# rom_fingerprint.sh — ROM 指纹深度擦除
# AlwaysStrong v1.3.0
# 清除第三方 ROM 的定制属性前缀和版本标记，伪装为官方 OEM 构建

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_save "AlwaysStrong: ROM fingerprint scrubbing started"

# 1. 核心构建类型修正
resetprop ro.build.type user 2>/dev/null || true
resetprop ro.build.tags release-keys 2>/dev/null || true
resetprop ro.build.selinux 1 2>/dev/null || true
resetprop ro.build.characteristics default 2>/dev/null || true

# 2. 第三方 ROM 前缀属性清理（15 种常见 ROM）
CUSTOM_ROM_PREFIXES="
ro.lineage
ro.aosp
ro.crdroid
ro.evolution
ro.arrow
ro.derpfest
ro.pixelexperience
ro.havoc
ro.bliss
ro.ressurected
ro.carbon
ro.dot
ro.hentai
ro.nusantara
ro.spark
ro.awaken
ro.banana
ro.cherish
ro.corvus
ro.octavi
ro.palladium
ro.pe
ro.potato
ro.proton
ro.rice
ro.syberia
ro.tequila
ro.xtended
ro.your
ro.modversion
ro.cm.version
ro.rom.version
ro.rom.name
ro.build.version.incremental.rom
"

fixed_count=0
for prefix in $CUSTOM_ROM_PREFIXES; do
    # 列出所有以此前缀开头的属性并清除
    existing_props="$(getprop | grep "^\[$prefix" | sed 's/^\[\(.*\)\].*/\1/' 2>/dev/null)"
    for prop in $existing_props; do
        resetprop -n "$prop" "" 2>/dev/null || true
        fixed_count=$((fixed_count + 1))
    done
done

# 3. 分区安全标签修正
SECURITY_PROPS="
ro.boot.verifiedbootstate=green
ro.boot.flash.locked=1
ro.boot.veritymode=enforcing
ro.boot.vbmeta.device_state=locked
ro.boot.warranty_bit=0
ro.warranty_bit=0
sys.oem_unlock_allowed=0
ro.oem_unlock_supported=0
ro.boot.bootloader=unknown
"

while IFS='=' read -r prop val; do
    [ -z "$prop" ] && continue
    current="$(getprop "$prop" 2>/dev/null)"
    if [ "$current" != "$val" ] && [ -n "$val" ]; then
        resetprop "$prop" "$val" 2>/dev/null || true
        fixed_count=$((fixed_count + 1))
    fi
done <<EOF
$SECURITY_PROPS
EOF

# 4. ADB 调试标志清理
DEBUG_PROPS="
ro.debuggable=0
ro.secure=1
ro.adb.secure=1
persist.sys.usb.config=none
sys.usb.config=none
sys.usb.state=none
persist.vendor.usb.config=none
ro.force.debuggable=0
init.svc.adbd=stopped
ro.adb.nonblocking_ffs=0
persist.sys.adb.notify=0
"

while IFS='=' read -r prop val; do
    [ -z "$prop" ] && continue
    current="$(getprop "$prop" 2>/dev/null)"
    if [ "$current" != "$val" ]; then
        resetprop "$prop" "$val" 2>/dev/null || true
    fi
done <<EOF
$DEBUG_PROPS
EOF

# 5. 清理 Magisk/KSU 可能泄露的属性
MAGISK_PROPS="
ro.magisk.version
ro.magisk.version.code
persist.sys.magisk.version
persist.sys.magisk.start
init.svc.magisk_pfs
init.svc.magisk_pfsd
"

for prop in $MAGISK_PROPS; do
    resetprop -n "$prop" "" 2>/dev/null || true
done

# 6. 内核版本字符串伪装（防止 uname -r 暴露自定义内核标记）
# 在 /proc/sys/kernel/ 层面无害，主要通过 resetprop 屏蔽
resetprop ro.kernel.version 2>/dev/null || true

# 7. hostname 清理（部分 ROM 带 lineage/aosp 标识）
current_hostname="$(getprop net.hostname 2>/dev/null)"
case "$current_hostname" in
    *lineage*|*aosp*|*cm_*|*crdroid*)
        resetprop net.hostname "android-$(getprop ro.product.device)" 2>/dev/null || true
        ;;
esac

log_save "AlwaysStrong: ROM fingerprint done ($fixed_count props)"

unset CUSTOM_ROM_PREFIXES SECURITY_PROPS DEBUG_PROPS MAGISK_PROPS fixed_count prefix existing_props prop val current current_hostname
