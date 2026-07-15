#!/system/bin/sh
# AlwaysStrong — cloud update checker & installer
#
# Usage:
#   sh cloud_update.sh check     Check for updates, print JSON + exit code
#   sh cloud_update.sh install   Download & install the latest version
#
# Exit codes:
#   0   Already up-to-date
#   1   New version available (check mode)
#   2   Download/install failed
#   3   Network error
#   4   No root

REMOTE="https://raw.githubusercontent.com/Lxiaoyao077/AlwaysStrong/main/update.json"
MIRROR="https://gh-proxy.com/raw.githubusercontent.com/Lxiaoyao077/AlwaysStrong/main/update.json"
CACHE_DIR="/data/adb/tricky_store/update_cache"
TMP_ZIP="/data/local/tmp/AlwaysStrong-update.zip"

ROOT="$(id -u 2>/dev/null || echo 0)"
[ "$ROOT" != "0" ] && { echo "E: root required"; exit 4; }

# --- helpers from common_func.sh (self-contained for network resilience) ---
dl_to() { curl -fkL --connect-timeout 10 --max-time 90 -o "$1" "$2" 2>/dev/null; }
dl_out() { curl -fkLs --connect-timeout 10 --max-time 30 "$1" 2>/dev/null; }

# --- parse versionCode from module.prop ---
MODPROP=""
for d in /data/adb/modules/tricky_store /data/adb/modules_update/tricky_store; do
    [ -f "$d/module.prop" ] && { MODPROP="$d/module.prop"; break; }
done
[ -z "$MODPROP" ] && { echo "E: module not found"; exit 2; }

THIS_VC=$(grep '^versionCode=' "$MODPROP" | cut -d= -f2 | tr -d ' ')
THIS_VER=$(grep '^version=' "$MODPROP" | cut -d= -f2 | tr -d ' ')
[ -z "$THIS_VC" ] && THIS_VC=0

# --- fetch remote update.json ---
REMOTE_JSON=""
for URL in "$REMOTE" "$MIRROR"; do
    REMOTE_JSON=$(dl_out "$URL")
    [ -n "$REMOTE_JSON" ] && break
done
[ -z "$REMOTE_JSON" ] && { echo "E: cannot reach update server"; exit 3; }

mkdir -p "$CACHE_DIR"
echo "$REMOTE_JSON" > "$CACHE_DIR/update.json"

REMOTE_VC=$(echo "$REMOTE_JSON" | sed -n 's/.*"versionCode"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
REMOTE_VER=$(echo "$REMOTE_JSON" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
ZIP_URL=$(echo "$REMOTE_JSON" | sed -n 's/.*"zipUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
CHG_URL=$(echo "$REMOTE_JSON" | sed -n 's/.*"changelog"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

[ -z "$REMOTE_VC" ] && { echo "E: malformed update.json"; exit 2; }

# --- compare ---
MODE="${1:-check}"
if [ "$MODE" = "check" ]; then
    if [ "$REMOTE_VC" -gt "$THIS_VC" ]; then
        echo "{\"current\":\"$THIS_VER ($THIS_VC)\",\"latest\":\"$REMOTE_VER ($REMOTE_VC)\",\"changelog\":\"$CHG_URL\"}"
        exit 1
    else
        echo "{\"current\":\"$THIS_VER ($THIS_VC)\",\"status\":\"up-to-date\"}"
        exit 0
    fi
fi

# --- install mode ---
if [ "$REMOTE_VC" -le "$THIS_VC" ]; then
    echo "Already up-to-date: $THIS_VER ($THIS_VC)"
    exit 0
fi

echo "Downloading $REMOTE_VER ..."
rm -f "$TMP_ZIP"

# try primary + mirror
SUCCESS=0
for URL in "$ZIP_URL" "${ZIP_URL//github.com/gh-proxy.com/github.com}"; do
    dl_to "$TMP_ZIP" "$URL" && { SUCCESS=1; break; }
done

[ "$SUCCESS" != "1" ] && { echo "E: download failed"; exit 2; }

# verify zip
if ! unzip -tq "$TMP_ZIP" >/dev/null 2>&1; then
    echo "E: downloaded zip is corrupt"
    rm -f "$TMP_ZIP"
    exit 2
fi

# install via Magisk/KSU
if command -v magisk >/dev/null 2>&1; then
    magisk --install-module "$TMP_ZIP" 2>&1
elif command -v ksud >/dev/null 2>&1; then
    ksud module install "$TMP_ZIP" 2>&1
else
    echo "E: no supported manager found"
    rm -f "$TMP_ZIP"
    exit 2
fi

rm -f "$TMP_ZIP"
echo "Install queued — reboot to apply $REMOTE_VER"
exit 0
