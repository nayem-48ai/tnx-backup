#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Restore (exact structure OR zip)
# =====================================================

restore_menu() {
  banner
  title "  RESTORE"
  hr
  choose_remote
  echo
  echo -e "${C_BOLD}How do you want to restore?${C_RESET}"
  echo -e "  ${C_GREEN}1)${C_RESET} Exact structure (mirror)  ${C_DIM}- files placed back into folders${C_RESET}"
  echo -e "  ${C_GREEN}2)${C_RESET} Zip archive               ${C_DIM}- download a .tar.gz backup${C_RESET}"
  echo -e "  ${C_GREEN}0)${C_RESET} Cancel"
  local c; c="$(ask 'Select' '1')"
  case "$c" in
    1) restore_mirror ;;
    2) restore_zip ;;
    *) return ;;
  esac
}

restore_mirror() {
  local src target
  src="${SELECTED_REMOTE}:${REMOTE_BASE}/mirror"
  if ! rclone lsf "$src" >/dev/null 2>&1; then
    err "No mirror backup found at $src"; pause; return
  fi
  echo
  info "Mirror backup contents (top level):"
  rclone lsf "$src" 2>/dev/null | head -30 | sed 's/^/   /'
  local size; size=$(rclone size "$src" 2>/dev/null | awk -F'[()]' '/Total size/{print $2}')
  echo -e "   ${C_DIM}Total: ${size:-?}${C_RESET}"
  echo
  warn "Restoring to your device can OVERWRITE existing files."
  target="$(ask 'Restore target folder' "$SOURCE_ROOT/TNx-Restored")"
  mkdir -p "$target"
  echo
  info "Source: $src"
  info "Target: $target"
  confirm "Proceed with restore?" || { warn "Cancelled."; pause; return; }

  rclone copy "$src" "$target" --progress --stats-one-line \
    --transfers "$RCLONE_TRANSFERS" --log-file "$TNX_RUNLOG" --log-level INFO
  local rc=$?
  echo; hr
  if [ $rc -eq 0 ]; then
    ok "Restore complete -> $target"
    notify "TNx Backup" "Restore (mirror) complete"
  else
    err "Restore failed (rc=$rc)."
  fi
  pause
}

restore_zip() {
  local src; src="${SELECTED_REMOTE}:${REMOTE_BASE}/archives"
  local -a arr; local i=1; declare -A ZMAP
  echo; info "Available zip archives:"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf "  ${C_GREEN}%d)${C_RESET} %s\n" "$i" "$line"
    ZMAP[$i]="$line"; i=$((i+1))
  done < <(rclone lsf "$src" 2>/dev/null | grep '\.tar\.gz$' | sort -r)
  [ ${#ZMAP[@]} -eq 0 ] && { err "No zip archives found."; pause; return; }

  local sel file; sel="$(ask 'Choose archive number' '1')"
  file="${ZMAP[$sel]}"
  [ -z "$file" ] && { warn "Invalid selection."; pause; return; }

  local target extract
  target="$(ask 'Download to folder' "$SOURCE_ROOT/Download")"
  mkdir -p "$target"
  echo
  info "Downloading $file -> $target ..."
  rclone copy "${src}/${file}" "$target" --progress --stats-one-line \
    --log-file "$TNX_RUNLOG" --log-level INFO
  local rc=$?
  [ $rc -ne 0 ] && { err "Download failed."; pause; return; }
  ok "Downloaded: $target/$file"

  echo
  if confirm "Extract the archive now?"; then
    extract="$(ask 'Extract into folder' "$SOURCE_ROOT/TNx-Restored")"
    mkdir -p "$extract"
    info "Extracting..."
    tar -xf "$target/$file" -C "$extract" && ok "Extracted to $extract" || err "Extraction failed."
  else
    info "Left as archive: $target/$file"
  fi
  notify "TNx Backup" "Restore (zip) complete"
  pause
}
