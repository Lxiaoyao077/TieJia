#!/system/bin/sh
# target_cleanup.sh — periodic cleanup of expired / blacklisted target.txt entries
#
# Called periodically from the hourly refresh loop. Removes:
#   1. Entries for packages that no longer exist on device (uninstalled apps)
#   2. Blacklisted packages (apps that should never be targeted by cert spoofing)
#   3. Duplicate entries
#
# Also ensures target.txt ends with a newline so aswatcher (inotify) picks
# up the clean file correctly.

MODDIR="${MODPATH:-$(dirname "$0")}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"
init_config
TARGET="$CONFIG_DIR/target.txt"
BLACKLIST="$CONFIG_DIR/config/target_blacklist.txt"

# Source common helpers (find_sed for $SED)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"
find_sed 2>/dev/null || SED="sed -i"

log() { echo "target_cleanup: $*"; }

[ -f "$TARGET" ] || exit 0

# ---- Expired: remove packages that no longer exist ----
TMP="$CONFIG_DIR/.target_cleanup.tmp"
> "$TMP"

while IFS= read -r line; do
  # keep comments and blanks
  case "$line" in
    ""|"#"*) echo "$line" >> "$TMP"; continue ;;
  esac

  pkg="${line%% *}"  # everything up to first space (package name)
  [ -z "$pkg" ] && { echo "$line" >> "$TMP"; continue; }

  # Check if package still exists on device
  if pm path "$pkg" >/dev/null 2>&1; then
    echo "$line" >> "$TMP"
  else
    log "removed uninstalled: $pkg"
  fi
done < "$TARGET"

# Ensure exactly one trailing newline (no accumulation across runs)
if [ -s "$TMP" ]; then
  ensure_trailing_newline "$TMP"
fi

if ! cmp -s "$TMP" "$TARGET" 2>/dev/null; then
  mv "$TMP" "$TARGET"
  chmod 644 "$TARGET"
  # Touch trigger file so aswatcher re-reads target list
  touch "$CONFIG_DIR/.target_updated" 2>/dev/null
  log "target.txt cleaned (stale entries removed)"
fi
rm -f "$TMP" 2>/dev/null

# ---- Blacklist removal (if blacklist file exists) ----
if [ -f "$BLACKLIST" ] && [ -s "$BLACKLIST" ]; then
  CHANGED=0
  for bp in $(tr '\n' ' ' < "$BLACKLIST" 2>/dev/null); do
    [ -z "$bp" ] && continue
    bp_escaped=$(printf '%s\n' "$bp" | sed 's/[.[\*^$\\]/\\&/g')
    if grep -qE "^${bp_escaped}([[:space:]]|\$)" "$TARGET" 2>/dev/null; then
      $SED "/^${bp_escaped}[[:space:]]/d; /^${bp_escaped}$/d" "$TARGET"
      log "blacklist removed: $bp"
      CHANGED=1
    fi
  done
  [ "$CHANGED" = "1" ] && touch "$CONFIG_DIR/.target_updated" 2>/dev/null
fi

exit 0
