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
  setup_mega_remote "$name"
  if ! echo "$REMOTES" | grep -qw "$name"; then
    set_conf_value REMOTES "$REMOTES $name"
    ok "Added '$name' to remotes list."
  fi
  pause
}
