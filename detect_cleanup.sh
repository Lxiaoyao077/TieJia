#!/system/bin/sh
# detect_cleanup.sh — 检测 App 痕迹清理
# AlwaysStrong v1.3.0
# 清理已知 Root/Magisk 检测 App 的缓存和残留文件，降低二次检测风险

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

# 已知检测 App 包名列表
DETECTOR_PKGS="
io.github.vvb2060.keyattestation
com.dra1n.momo
com.zd6yy7j.ruru
icu.nullptr.nativetest
com.kdrag0n.safetylib
com.scottyab.rootbeer
com.darktideapps.MOMO
com.rosan.xposed.one
io.github.vvb2060.mahoshojo
com.vachel.editor
me.weishu.exp
com.oasisfeng.island
net.mikaellindstrom.momo
moe.shizuku.privileged.api
com.liapp.rm
com.catchingnow.icebox
com.termux
"

# 外部存储检测目录
EXTERNAL_DETECTOR_DIRS="
/sdcard/Android/data
/storage/emulated/0/Android/data
/data/media/0/Android/data
"

log_save "AlwaysStrong: detection cleanup started"

cleaned_count=0

for pkg in $DETECTOR_PKGS; do
    # 内部缓存目录
    data_dir="/data/data/$pkg"
    [ -d "$data_dir" ] || continue

    # 清理 cache
    if [ -d "$data_dir/cache" ]; then
        rm -rf "$data_dir/cache"/* 2>/dev/null
        cleaned_count=$((cleaned_count + 1))
        log_save "AlwaysStrong: cleaned cache for $pkg"
    fi

    # 清理 files (仅清理临时/下载文件，保留配置)
    if [ -d "$data_dir/files" ]; then
        find "$data_dir/files" -maxdepth 1 -name "*.tmp" -delete 2>/dev/null
        find "$data_dir/files" -maxdepth 1 -name "*.log" -delete 2>/dev/null
    fi

    # 清理 code_cache
    if [ -d "$data_dir/code_cache" ]; then
        rm -rf "$data_dir/code_cache"/* 2>/dev/null
    fi

    # 清理外部存储
    for ext_base in $EXTERNAL_DETECTOR_DIRS; do
        ext_dir="$ext_base/$pkg"
        [ -d "$ext_dir" ] || continue
        [ -d "$ext_dir/cache" ] && rm -rf "$ext_dir/cache"/* 2>/dev/null
        find "$ext_dir" -maxdepth 1 \( -name "*.log" -o -name "*.tmp" \) -delete 2>/dev/null
    done
done

# 清理公共临时目录的检测残留
rm -rf /data/local/tmp/key_attestation_* 2>/dev/null
rm -rf /data/local/tmp/playintegrity_* 2>/dev/null
rm -f  /data/local/tmp/check_keybox.xml 2>/dev/null
rm -f  /data/local/tmp/attestation_* 2>/dev/null
rm -f  /data/local/tmp/momo_result_* 2>/dev/null

# 清理 adb 调试残留
rm -f /data/local/tmp/adb_check_* 2>/dev/null

log_save "AlwaysStrong: detection cleanup done ($cleaned_count packages)"

unset DETECTOR_PKGS EXTERNAL_DETECTOR_DIRS cleaned_count data_dir ext_base ext_dir pkg
