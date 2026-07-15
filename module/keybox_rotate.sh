#!/system/bin/sh
# keybox_rotate.sh — multi-entry keybox random selector for TieJia
#
# If keybox.xml contains multiple <Keybox> elements (multi-entry format),
# randomly selects one and writes it to keybox_active.xml — a single-entry
# subset that tricky_store uses as its active key source.
#
# For single-entry keyboxes, this is a no-op (already optimal).
#
# This enables "Keybox 智能选择" (intelligent keybox selection): when the
# mirror serves a multi-entry keybox or the user manually provides one,
# TieJia randomly picks a working entry on each boot or refresh.
#
# Exit 0: active keybox selected
# Exit 1: no valid entries found
# Exit 2: single entry (no rotation needed, already in place)

SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
[ -f "$SELF_DIR/common_func.sh" ] && . "$SELF_DIR/common_func.sh"
find_sed 2>/dev/null || SED="sed -i"

init_config
SRC="$CONFIG_DIR/keybox.xml"
DST="$CONFIG_DIR/keybox_active.xml"

log() { echo "keybox_rotate: $*"; }

# Allow re-rotation: if keybox.xml was overwritten to single-entry by a previous
# rotation, restore from the multi-entry backup so rotation continues to work.
if [ -f "$CONFIG_DIR/keybox_multi.xml" ]; then
    SRC="$CONFIG_DIR/keybox_multi.xml"
fi

[ -f "$SRC" ] || { log "no keybox.xml"; exit 1; }

# Count <Keybox entries — if only one, no rotation needed
ENTRIES=$(grep -c '<Keybox ' "$SRC" 2>/dev/null)
[ "$ENTRIES" = "1" ] && { log "single entry — no rotation needed"; exit 2; }
[ "$ENTRIES" -lt 1 ] && { log "no Keybox entries found"; exit 1; }

# Extract all Keybox blocks (from <Keybox to </Keybox>).
# Also handles single-line <Keybox>...</Keybox> via sed expansion.
mkdir -p "$CONFIG_DIR/.keybox_entries"
rm -rf "$CONFIG_DIR/.keybox_entries"/*

# Pre-process: expand single-line <Keybox>...</Keybox> to multi-line
TMP_EXPANDED="$CONFIG_DIR/.keybox_entries/_expanded.xml"
$SED 's|\(<Keybox [^>]*>\)|\n\1\n|g; s|\(</Keybox>\)|\n\1\n|g' "$SRC" > "$TMP_EXPANDED" 2>/dev/null

IDX=0
IN_KEYBOX=0
while IFS= read -r line; do
  case "$line" in
    *"<Keybox "*)
      IN_KEYBOX=1; IDX=$((IDX+1))
      echo '<?xml version="1.0"?>' > "$CONFIG_DIR/.keybox_entries/${IDX}.xml"
      echo "$line" >> "$CONFIG_DIR/.keybox_entries/${IDX}.xml"
      ;;
    *"</Keybox>"*)
      echo "$line" >> "$CONFIG_DIR/.keybox_entries/${IDX}.xml"
      IN_KEYBOX=0
      ;;
    *)
      [ "$IN_KEYBOX" = "1" ] && echo "$line" >> "$CONFIG_DIR/.keybox_entries/${IDX}.xml"
      ;;
  esac
done < "$TMP_EXPANDED"
rm -f "$TMP_EXPANDED"

log "found $IDX keybox entries"

# Randomly select one entry
RAND_IDX=$(( ($(od -An -N2 -tu2 /dev/urandom 2>/dev/null || echo "$$") % IDX) + 1 ))
[ "$RAND_IDX" -lt 1 ] && RAND_IDX=1
[ "$RAND_IDX" -gt "$IDX" ] && RAND_IDX="$IDX"

ENTRY_FILE="$CONFIG_DIR/.keybox_entries/${RAND_IDX}.xml"

# Validate: must contain Keybox and be non-empty
if [ -s "$ENTRY_FILE" ] && grep -q "Keybox" "$ENTRY_FILE"; then
  cp "$ENTRY_FILE" "$DST"
  chmod 600 "$DST"
  log "selected entry $RAND_IDX/$IDX ($(wc -c < "$DST") bytes)"

  # Persist single entry to keybox.xml so tricky_store reads the active one.
  # But first save the multi-entry source so rotation can continue on next run.
  if [ "$ENTRIES" -gt 1 ] && [ "$SRC" = "$CONFIG_DIR/keybox.xml" ]; then
    cp "$SRC" "$CONFIG_DIR/keybox_multi.xml"
    chmod 600 "$CONFIG_DIR/keybox_multi.xml"
  fi
  cp "$ENTRY_FILE" "$CONFIG_DIR/keybox.xml"
  chmod 600 "$CONFIG_DIR/keybox.xml"

  log "active keybox rotated"
  rm -rf "$CONFIG_DIR/.keybox_entries"
  exit 0
else
  log "entry $RAND_IDX invalid — keeping existing"
  rm -rf "$CONFIG_DIR/.keybox_entries"
  exit 1
fi
