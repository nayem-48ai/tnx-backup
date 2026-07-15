#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Settings / config editor & remote mgmt
# =====================================================

settings_menu() {
  while true; do
    banner
    title "  SETTINGS"
    hr
    load_config
    echo -e "  ${C_BOLD}Current configuration${C_RESET}"
    echo -e "   Source root      : ${C_CYAN}$SOURCE_ROOT${C_RESET}"
    echo -e "   Remotes          : ${C_CYAN}$REMOTES${C_RESET}"
    echo -e "   Default mode     : ${C_CYAN}$DEFAULT_MODE${C_RESET}"
    echo -e "   Default profile  : ${C_CYAN}$DEFAULT_PROFILE${C_RESET}"
    echo -e "   Retention keep   : ${C_CYAN}$RETENTION_KEEP${C_RESET} newest"
    echo -e "   Retention days   : ${C_CYAN}$RETENTION_DAYS${C_RESET}"
    echo -e "   Guard enabled    : ${C_CYAN}$GUARD_ENABLE${C_RESET}"
    echo -e "   Min battery %    : ${C_CYAN}$GUARD_MIN_BATTERY${C_RESET}"
    echo -e "   Require Wi-Fi    : ${C_CYAN}$GUARD_REQUIRE_WIFI${C_RESET}"
    hr
    echo -e "  ${C_GREEN}1)${C_RESET} Set retention (keep N newest)"
    echo -e "  ${C_GREEN}2)${C_RESET} Set retention (age in days)"
    echo -e "  ${C_GREEN}3)${C_RESET} Toggle battery/Wi-Fi guard"
    echo -e "  ${C_GREEN}4)${C_RESET} Set minimum battery %"
    echo -e "  ${C_GREEN}5)${C_RESET} Toggle require Wi-Fi"
    echo -e "  ${C_GREEN}6)${C_RESET} Default profile"
    echo -e "  ${C_GREEN}7)${C_RESET} Add / configure a remote (multi-remote)"
    echo -e "  ${C_GREEN}8)${C_RESET} Edit config file in \$EDITOR"
    echo -e "  ${C_GREEN}0)${C_RESET} Back"
    local c; c="$(ask 'Select' '0')"
    case "$c" in
      1) set_conf_value RETENTION_KEEP "$(ask 'Keep how many newest backups' "$RETENTION_KEEP")"; ok "Saved." ;;
      2) set_conf_value RETENTION_DAYS "$(ask 'Delete backups older than N days (0=off)' "$RETENTION_DAYS")"; ok "Saved." ;;
      3) [ "$GUARD_ENABLE" = "true" ] && set_conf_value GUARD_ENABLE "false" || set_conf_value GUARD_ENABLE "true"; ok "Toggled." ;;
      4) set_conf_value GUARD_MIN_BATTERY "$(ask 'Minimum battery %' "$GUARD_MIN_BATTERY")"; ok "Saved." ;;
      5) [ "$GUARD_REQUIRE_WIFI" = "true" ] && set_conf_value GUARD_REQUIRE_WIFI "false" || set_conf_value GUARD_REQUIRE_WIFI "true"; ok "Toggled." ;;
      6) declare -A PROFILE_MAP; list_profiles; local s; s="$(ask 'Default profile number' '1')"; [ -n "${PROFILE_MAP[$s]}" ] && set_conf_value DEFAULT_PROFILE "${PROFILE_MAP[$s]}"; ok "Saved." ;;
      7) add_remote_flow ;;
      8) "${EDITOR:-nano}" "$TNX_CONF" 2>/dev/null || vi "$TNX_CONF" ;;
      *) return ;;
    esac
  done
}

add_remote_flow() {
  local name; name="$(ask 'New remote name (e.g. mega2)' '')"
  [ -z "$name" ] && { warn "Cancelled."; return; }
  setup_mega_remote "$name"   # handles creation, test, and registration
  pause
}

# --- Auto-update the tool from GitHub ---
self_update() {
  require_cmd git || { err "git not installed. Run: pkg install git"; return 1; }
  [ -d "$TNX_ROOT/.git" ] || { err "Not a git checkout - cannot auto-update."; return 1; }
  info "Fetching updates from GitHub..."
  git -C "$TNX_ROOT" fetch --quiet origin 2>&1 | tail -3
  local behind; behind="$(git -C "$TNX_ROOT" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "$behind" = "0" ] || [ -z "$behind" ]; then
    ok "Already up to date."; return 0
  fi
  info "Pulling $behind commit(s)..."
  if git -C "$TNX_ROOT" pull --ff-only 2>&1 | tail -6; then
    ok "Updated. Restart the tool (./tnxbackup.sh) to use the new version."
  else
    err "Update failed (local changes conflict?). Try: cd $TNX_ROOT && git stash && git pull"
    return 1
  fi
}

# --- Diagnostics: pinpoint login / network / config problems ---
tool_diag() {
  banner; title "  DIAGNOSTICS"; hr
  ensure_ca
  local rc; rc="$(command -v rclone || echo 'NOT FOUND')"
  echo -e "  rclone path    : ${C_CYAN}$rc${C_RESET}"
  echo -e "  rclone version : ${C_CYAN}$(rclone version 2>/dev/null | head -1 || echo '?')${C_RESET}"
  echo -e "  has MEGA backend: ${C_CYAN}$(rclone help backends 2>/dev/null | grep -qi '^  mega' && echo yes || echo NO)${C_RESET}"
  echo -e "  rclone config  : ${C_CYAN}${RCLONE_CONFIG}${C_RESET} $([ -f "$RCLONE_CONFIG" ] && echo "(exists)" || echo "(missing)")"
  echo -e "  CA bundle      : ${C_CYAN}${RCLONE_CACERT:-<default system>}${C_RESET}"
  echo -e "  SSL_CERT_FILE  : ${C_CYAN}${SSL_CERT_FILE:-<unset>}${C_RESET}"
  hr
  echo -e "  ${C_BOLD}Remotes defined in config:${C_RESET}"
  rclone listremotes 2>/dev/null | sed 's/^/   /' || echo "   (none / error)"
  hr
  echo -e "  ${C_BOLD}Network reachability to MEGA:${C_RESET}"
  local code; code="$(mega_http_code)"
  if [ "$code" = "200" ]; then
    echo -e "   ${C_GREEN}MEGA API reachable (HTTP 200)${C_RESET}"
  else
    echo -e "   ${C_RED}MEGA API NOT reachable (HTTP ${code:-no response})${C_RESET} -> network/region block"
    echo -e "   ${C_DIM}The login error is caused by this block, not by the tool or your password.${C_RESET}"
  fi
  hr
  echo -e "  ${C_BOLD}Network login test to MEGA:${C_RESET}"
  local r; r="$(rclone listremotes 2>/dev/null | head -1 | tr -d ':')"
  if [ -n "$r" ]; then
    echo -e "   testing remote '${r}' (saving raw capture to logs/mega-debug.log)..."
    out="$(timeout 60 rclone about "${r}:" --dump-bodies --low-level-retries 3 --retries 1 2>&1 | tee "$TNX_LOGDIR/mega-debug.log")"
    echo "$out" | grep -E "Total:|error|Error|CRITICAL|denied|failed|end of JSON" | sed 's/^/   /'
    echo -e "   ${C_DIM}Capture saved: $TNX_LOGDIR/mega-debug.log (last 12 lines:)${C_RESET}"
    tail -n 12 "$TNX_LOGDIR/mega-debug.log" 2>/dev/null | sed 's/^/   /'
  else
    echo -e "   ${C_YELLOW}No remote configured yet - use menu 11.${C_RESET}"
  fi
  hr
}
