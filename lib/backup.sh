#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Backup engine (mirror / zip / incremental)
# =====================================================

# Resolve profile filter file
profile_filter() {
  local p="$1"
  local f="$TNX_PROFILES/${p}.profile"
  [ -f "$f" ] && echo "$f" || echo "$TNX_FILTERS"
}

profile_desc() {
  local f; f="$(profile_filter "$1")"
  grep -m1 '# DESC:' "$f" 2>/dev/null | sed 's/.*# DESC:[[:space:]]*//' || echo "(no description)"
}

list_profiles() {
  echo -e "${C_BOLD}Available profiles:${C_RESET}"
  local i=1
  for f in "$TNX_PROFILES"/*.profile; do
    [ -f "$f" ] || continue
    local name desc
    name="$(basename "$f" .profile)"
    desc="$(profile_desc "$name")"
    printf "  ${C_GREEN}%d)${C_RESET} %-12s ${C_DIM}%s${C_RESET}\n" "$i" "$name" "$desc"
    PROFILE_MAP[$i]="$name"; i=$((i+1))
  done
}

choose_profile() {
  declare -gA PROFILE_MAP
  list_profiles
  local sel
  sel="$(ask 'Choose profile number' '1')"
  SELECTED_PROFILE="${PROFILE_MAP[$sel]:-$DEFAULT_PROFILE}"
  info "Profile: $SELECTED_PROFILE"
}

choose_remote() {
  local i=1; declare -gA REMOTE_MAP
  echo -e "${C_BOLD}Remotes:${C_RESET}"
  for r in $REMOTES; do
    local status="?"
    rclone about "${r}:" >/dev/null 2>&1 && status="${C_GREEN}online${C_RESET}" || status="${C_RED}offline${C_RESET}"
    printf "  ${C_GREEN}%d)${C_RESET} %-10s [%b]\n" "$i" "$r" "$status"
    REMOTE_MAP[$i]="$r"; i=$((i+1))
  done
  local sel; sel="$(ask 'Choose remote number' '1')"
  SELECTED_REMOTE="${REMOTE_MAP[$sel]:-$PRIMARY_REMOTE}"
  info "Remote: $SELECTED_REMOTE"
}

# --- Mirror / incremental backup ---
backup_mirror() {
  local incremental="$1"   # "sync" for incremental, "copy" for additive
  banner
  [ "$incremental" = "sync" ] && title "  INCREMENTAL BACKUP (mirror sync)" || title "  FULL MIRROR BACKUP"
  hr
  guard_check || { warn "Backup cancelled by guard."; pause; return; }
  choose_remote
  choose_profile

  local filter dest op
  filter="$(profile_filter "$SELECTED_PROFILE")"
  dest="${SELECTED_REMOTE}:${REMOTE_BASE}/mirror"
  op="copy"; [ "$incremental" = "sync" ] && op="sync"

  echo; info "Source : $SOURCE_ROOT"
  info "Dest   : $dest"
  info "Filter : $(basename "$filter")"
  info "Mode   : $op (incremental=$incremental)"
  echo
  confirm "Start backup now?" || { warn "Cancelled."; pause; return; }

  local start end dur
  start=$(date +%s)
  rclone "$op" "$SOURCE_ROOT" "$dest" \
    --filter-from "$filter" \
    --transfers "$RCLONE_TRANSFERS" --checkers "$RCLONE_CHECKERS" \
    --progress --stats-one-line $RCLONE_EXTRA_FLAGS \
    --log-file "$TNX_RUNLOG" --log-level INFO
  local rc=$?
  end=$(date +%s); dur=$((end-start))

  echo; hr
  local size files
  size=$(rclone size "$dest" 2>/dev/null | awk -F'[()]' '/Total size/{print $2}')
  files=$(rclone size "$dest" 2>/dev/null | awk '/Total objects/{print $NF}')
  if [ $rc -eq 0 ]; then
    ok "Backup complete in ${dur}s."
    echo -e "   ${C_BOLD}Uploaded to:${C_RESET} $dest"
    echo -e "   ${C_BOLD}Cloud size :${C_RESET} ${size:-n/a} | objects: ${files:-n/a}"
    add_history "$op" "$SELECTED_REMOTE" "$SELECTED_PROFILE" "success" "${size:-?}" "${files:-?}" "$dest"
    notify "TNx Backup" "Mirror backup done in ${dur}s"
    apply_retention "$SELECTED_REMOTE"
  else
    err "Backup failed (rc=$rc). See log: $TNX_RUNLOG"
    add_history "$op" "$SELECTED_REMOTE" "$SELECTED_PROFILE" "failed" "-" "-" "$dest"
    notify "TNx Backup" "Backup FAILED"
  fi
  pause
}

# --- Zip / archive backup ---
backup_zip() {
  banner
  title "  ZIP (ARCHIVE) BACKUP"
  hr
  guard_check || { warn "Backup cancelled by guard."; pause; return; }
  choose_remote
  choose_profile

  local stamp archive tmpdir filter dest
  stamp="$(date +%Y%m%d_%H%M%S)"
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tnxzip.XXXXXX")"
  archive="$tmpdir/sdcard-${SELECTED_PROFILE}-${stamp}.tar.gz"
  filter="$(profile_filter "$SELECTED_PROFILE")"
  dest="${SELECTED_REMOTE}:${REMOTE_BASE}/archives"

  info "Building file list from profile '$SELECTED_PROFILE'..."
  local listfile="$tmpdir/files.list"
  # Use rclone to resolve included files, then tar them (relative to SOURCE_ROOT)
  rclone lsf "$SOURCE_ROOT" --filter-from "$filter" -R --files-only > "$listfile" 2>/dev/null
  local n; n=$(wc -l < "$listfile")
  [ "$n" -eq 0 ] && { err "No files matched profile."; rm -rf "$tmpdir"; pause; return; }
  info "$n files selected. Compressing with $ZIP_COMPRESSOR ..."

  ( cd "$SOURCE_ROOT" && tar -cf - -T "$listfile" 2>/dev/null | "$ZIP_COMPRESSOR" > "$archive" )
  local asize; asize=$(du -h "$archive" | awk '{print $1}')
  ok "Archive built: $asize"

  echo; info "Uploading to $dest ..."
  confirm "Start upload now?" || { warn "Cancelled."; rm -rf "$tmpdir"; pause; return; }

  local start end dur
  start=$(date +%s)
  rclone copy "$archive" "$dest" --progress --stats-one-line \
    --transfers "$RCLONE_TRANSFERS" --log-file "$TNX_RUNLOG" --log-level INFO
  local rc=$?
  end=$(date +%s); dur=$((end-start))
  rm -rf "$tmpdir"

  echo; hr
  if [ $rc -eq 0 ]; then
    ok "Zip backup uploaded in ${dur}s ($asize)."
    echo -e "   ${C_BOLD}File:${C_RESET} $dest/$(basename "$archive")"
    add_history "zip" "$SELECTED_REMOTE" "$SELECTED_PROFILE" "success" "$asize" "$n" "$dest/$(basename "$archive")"
    notify "TNx Backup" "Zip backup done ($asize)"
    apply_retention "$SELECTED_REMOTE"
  else
    err "Upload failed (rc=$rc)."
    add_history "zip" "$SELECTED_REMOTE" "$SELECTED_PROFILE" "failed" "-" "-" "$dest"
    notify "TNx Backup" "Zip backup FAILED"
  fi
  pause
}
