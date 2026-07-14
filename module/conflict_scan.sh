#!/system/bin/sh
# conflict_scan.sh — runtime conflict scanner for AlwaysStrong
# Parses conflicts.txt (Specter-style declarative format) and acts on
# each entry according to its type: aggressive / moderate / passive.
#
# Called by service.sh on every boot so that a conflicting module
# installed after AlwaysStrong gets caught without a re-flash.
# Returns the number of modules that were newly handled this run.

MODDIR="${MODPATH:-$(dirname "$0")}"
CFG=/data/adb/tricky_store
CONF_FILE="${CFG}/config/conflicts.txt"
LOG_TAG="AlwaysStrong"

# ----- helpers -----
now_epoch() { date +%s; }
log()  { log -t "$LOG_TAG" "$@"; }

state_file="${CFG}/.conflict_state"
touch "$state_file" 2>/dev/null

# load previous handled state (id=n|since_epoch)
load_state() {
  cat "$state_file" 2>/dev/null
}

save_state() {
  local id="$1" epoch="$2"
  # atomic: write temp → rename so power loss doesn't corrupt
  local tmp="${state_file}.tmp"
  while IFS= read -r line; do
    [ "${line%%=*}" != "$id" ] && echo "$line"
  done < "$state_file" > "$tmp" 2>/dev/null
  echo "${id}=${epoch}" >> "$tmp"
  mv "$tmp" "$state_file" 2>/dev/null
}

was_handled() {
  local id="$1"
  load_state | grep -q "^${id}="
}

# ----- conflict resolution (declarative) -----
CONFLICTS=0

while IFS= read -r line; do
  # skip comments and blanks
  case "$line" in
    ""|"#"*) continue ;;
  esac

  # parse: id|display|type|features|script1,script2,...
  OLDIFS="$IFS"; IFS='|'
  set -- $line
  IFS="$OLDIFS"
  id="$1"; disp="$2"; type="$3"; features="$4"; scripts_list="$5"

  # validate
  [ -z "$id" ] && continue
  [ -z "$type" ] && continue

  cp_dir="/data/adb/modules/$id"
  [ -d "$cp_dir" ] || continue

  # already handled? skip to avoid re-removing on every boot
  was_handled "$id" && continue

  case "$type" in
    aggressive)
      log "aggressive: removing $disp ($id)"
      # run its uninstall.sh first (clean teardown)
      [ -f "$cp_dir/uninstall.sh" ] && sh "$cp_dir/uninstall.sh" 2>/dev/null
      touch "$cp_dir/disable" "$cp_dir/remove" 2>/dev/null
      rm -rf "$cp_dir" 2>/dev/null
      [ -d "/data/adb/modules_update/$id" ] && rm -rf "/data/adb/modules_update/$id" 2>/dev/null
      CONFLICTS=$((CONFLICTS+1))
      ;;

    moderate)
      log "moderate: disabling scripts for $disp ($id)"
      # disable scripts listed in conflicts.txt (comma-separated)
      OLDIFS2="$IFS"; IFS=','
      for sp in $scripts_list; do
        [ -z "$sp" ] && continue
        if [ -f "$sp" ]; then
          mv "$sp" "${sp}.disabled" 2>/dev/null
          log "  disabled: $sp"
        fi
      done
      IFS="$OLDIFS2"
      CONFLICTS=$((CONFLICTS+1))
      ;;

    passive)
      log "passive: logging conflict with $disp ($id)"
      CONFLICTS=$((CONFLICTS+1))
      ;;

    *)
      log "unknown conflict type '$type' for $id — skipped"
      continue
      ;;
  esac

  save_state "$id" "$(now_epoch)"

done < "$CONF_FILE"

# cleanup entries for modules that no longer exist
cleanup_state() {
  local tmp="${state_file}.tmp"
  > "$tmp"
  while IFS= read -r line; do
    local sid="${line%%=*}"
    [ -z "$sid" ] && continue
    if [ -d "/data/adb/modules/$sid" ]; then
      echo "$line" >> "$tmp"
    fi
  done < "$state_file" 2>/dev/null
  mv "$tmp" "$state_file" 2>/dev/null
}
cleanup_state

# exit with count for caller
exit $CONFLICTS
