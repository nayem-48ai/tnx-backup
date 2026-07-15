#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Cloud status, clean, retention, history, multi-remote
# =====================================================

cloud_status() {
  banner
  title "  CLOUD STATUS"
  hr
  for r in $REMOTES; do
    echo -e "${C_BOLD}Remote: ${C_CYAN}${r}${C_RESET}"
    if ! rclone about "${r}:" >/dev/null 2>&1; then
      echo -e "  ${C_RED}offline / not configured${C_RESET}"; echo; continue
    fi
    # Quota
    rclone about "${r}:" 2>/dev/null | sed 's/^/  /'
    # Backups
    local base="${r}:${REMOTE_BASE}"
    echo -e "  ${C_DIM}--- backups in ${REMOTE_BASE} ---${C_RESET}"
    if rclone lsf "$base" >/dev/null 2>&1; then
      local msize mfiles
      if rclone lsf "${base}/mirror" >/dev/null 2>&1; then
        msize=$(rclone size "${base}/mirror" 2>/dev/null | awk -F'[()]' '/Total size/{print $2}')
        echo -e "  mirror/   size: ${msize:-0}"
      fi
      echo -e "  archives/:"
      rclone lsl "${base}/archives" 2>/dev/null | awk '{print "     "$4"  "$2" "$3"  "$1" bytes"}' | head -20
    else
      echo -e "  ${C_DIM}(no backups yet)${C_RESET}"
    fi
    echo
  done
  pause
}

apply_retention() {
  # apply_retention <remote>  - keep newest RETENTION_KEEP archives, delete older than RETENTION_DAYS
  local r="$1"
  local base="${r}:${REMOTE_BASE}/archives"
  rclone lsf "$base" >/dev/null 2>&1 || return 0

  # Age-based
  if [ "${RETENTION_DAYS:-0}" -gt 0 ]; then
    info "Retention: deleting archives older than ${RETENTION_DAYS} days..."
    rclone delete "$base" --min-age "${RETENTION_DAYS}d" --include "*.tar.gz" \
      --log-file "$TNX_RUNLOG" --log-level INFO 2>/dev/null
  fi

  # Count-based
  if [ "${RETENTION_KEEP:-0}" -gt 0 ]; then
    local -a files
    mapfile -t files < <(rclone lsf "$base" 2>/dev/null | grep '\.tar\.gz$' | sort -r)
    local total=${#files[@]}
    if [ "$total" -gt "$RETENTION_KEEP" ]; then
      info "Retention: keeping newest $RETENTION_KEEP of $total archives..."
      local idx
      for ((idx=RETENTION_KEEP; idx<total; idx++)); do
        rclone deletefile "${base}/${files[$idx]}" 2>/dev/null && \
          log "[retention] deleted ${files[$idx]}"
      done
    fi
  fi
}

clean_cloud() {
  banner
  title "  CLEAN MEGA CLOUD"
  hr
  choose_remote
  local base="${SELECTED_REMOTE}:${REMOTE_BASE}"
  echo
  echo -e "${C_BOLD}What to clean on '${SELECTED_REMOTE}'?${C_RESET}"
  echo -e "  ${C_GREEN}1)${C_RESET} Delete a single zip archive"
  echo -e "  ${C_GREEN}2)${C_RESET} Empty the mirror/ folder"
  echo -e "  ${C_GREEN}3)${C_RESET} Empty the archives/ folder"
  echo -e "  ${C_RED}4)${C_RESET} Wipe entire ${REMOTE_BASE}/ (all backups)"
  echo -e "  ${C_GREEN}0)${C_RESET} Cancel"
  local c; c="$(ask 'Select' '0')"
  case "$c" in
    1)
      local i=1; declare -A DM
      while IFS= read -r f; do
        printf "  %d) %s\n" "$i" "$f"; DM[$i]="$f"; i=$((i+1))
      done < <(rclone lsf "${base}/archives" 2>/dev/null | grep '\.tar\.gz$' | sort -r)
      [ ${#DM[@]} -eq 0 ] && { warn "No archives."; pause; return; }
      local s; s="$(ask 'Archive number to delete' '')"
      [ -z "${DM[$s]}" ] && { warn "Invalid."; pause; return; }
      confirm "Delete ${DM[$s]} permanently?" && \
        rclone deletefile "${base}/archives/${DM[$s]}" && ok "Deleted." ;;
    2)
      confirm "Empty mirror/ folder on ${SELECTED_REMOTE}?" && \
        { rclone purge "${base}/mirror" 2>/dev/null; ok "mirror/ cleared."; } ;;
    3)
      confirm "Empty archives/ folder on ${SELECTED_REMOTE}?" && \
        { rclone purge "${base}/archives" 2>/dev/null; ok "archives/ cleared."; } ;;
    4)
      warn "This deletes ALL TNx backups on ${SELECTED_REMOTE}."
      if confirm "Are you absolutely sure?"; then
        local word; word="$(ask 'Type DELETE to confirm' '')"
        [ "$word" = "DELETE" ] && { rclone purge "$base" 2>/dev/null; ok "All backups wiped."; } || warn "Aborted."
      fi ;;
    *) return ;;
  esac
  pause
}

show_history() {
  banner
  title "  BACKUP HISTORY"
  hr
  init_history
  local n; n=$(jq 'length' "$TNX_HISTORY" 2>/dev/null)
  if [ "${n:-0}" -eq 0 ]; then info "No history yet."; pause; return; fi
  printf "${C_BOLD}%-19s %-8s %-8s %-10s %-8s %-8s${C_RESET}\n" "TIME" "MODE" "REMOTE" "PROFILE" "STATUS" "SIZE"
  jq -r '.[] | [.time,.mode,.remote,.profile,.status,.size] | @tsv' "$TNX_HISTORY" 2>/dev/null | \
  while IFS=$'\t' read -r t m r p s z; do
    local col="$C_GREEN"; [ "$s" != "success" ] && col="$C_RED"
    printf "%-19s %-8s %-8s %-10s ${col}%-8s${C_RESET} %-8s\n" "$t" "$m" "$r" "$p" "$s" "$z"
  done
  echo; info "Full manifest: $TNX_HISTORY"
  pause
}
