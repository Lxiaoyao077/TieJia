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

CONFIG_DIR=/data/adb/tricky_store
SRC="$CONFIG_DIR/keybox.xml"
DST="$CONFIG_DIR/keybox_active.xml"

log() { echo "keybox_rotate: $*"; }

[ -f "$SRC" ] || { log "no keybox.xml"; exit 1; }

# Count <Keybox entries — if only one, no rotation needed
ENTRIES=$(grep -c '<Keybox ' "$SRC" 2>/dev/null)
[ "$ENTRIES" = "1" ] && { log "single entry — no rotation needed"; exit 2; }
[ "$ENTRIES" -lt 1 ] && { log "no Keybox entries found"; exit 1; }

# Extract all Keybox blocks (from <Keybox to </Keybox>)
mkdir -p "$CONFIG_DIR/.keybox_entries"
rm -rf "$CONFIG_DIR/.keybox_entries"/*
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
done < "$SRC"

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
  # Symlink for tricky_store if it reads from keybox_active.xml
  # If tricky_store only reads keybox.xml, just copy back
  cp "$ENTRY_FILE" "$SRC"
  chmod 600 "$SRC"
  log "active keybox rotated"
  rm -rf "$CONFIG_DIR/.keybox_entries"
  exit 0
else
  log "entry $RAND_IDX invalid — keeping existing"
  rm -rf "$CONFIG_DIR/.keybox_entries"
  exit 1
fi
