#!/usr/bin/env bash
# =====================================================
#  TNx Backup Tool - Main entrypoint
#  Android storage  ->  MEGA  (rclone powered)
#  Author: nayem-48ai  |  License: MIT
# =====================================================
set -uo pipefail

TNX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load libraries ---
# shellcheck source=/dev/null
source "$TNX_DIR/lib/common.sh"
source "$TNX_DIR/lib/bootstrap.sh"
source "$TNX_DIR/lib/config.sh"
source "$TNX_DIR/lib/guard.sh"
source "$TNX_DIR/lib/scan.sh"
source "$TNX_DIR/lib/backup.sh"
source "$TNX_DIR/lib/restore.sh"
source "$TNX_DIR/lib/cloud.sh"
source "$TNX_DIR/lib/settings.sh"

# --- First run detection ---
bootstrap() {
  if [ ! -f "$TNX_CONF" ]; then
    die "Missing config: $TNX_CONF"
  fi
  load_config
  # Ensure portable tools (rclone/jq) exist without any system install
  portable_bootstrap
  if [ ! -f "$TNX_DIR/.initialized" ]; then
    first_run_wizard
    load_config
  fi
}

main_menu() {
  while true; do
    banner
    echo -e "  ${C_DIM}Source: $SOURCE_ROOT  |  Remotes: $REMOTES${C_RESET}"
    hr
    echo -e "  ${C_GREEN}1)${C_RESET} 📊  Scan device (storage report + HTML/CSV)"
    echo -e "  ${C_GREEN}2)${C_RESET} ☁️   Full mirror backup"
    echo -e "  ${C_GREEN}3)${C_RESET} 🔄  Incremental backup (sync changes)"
    echo -e "  ${C_GREEN}4)${C_RESET} 🗜️   Zip (archive) backup"
    echo -e "  ${C_GREEN}5)${C_RESET} ♻️   Restore (structure or zip)"
    echo -e "  ${C_GREEN}6)${C_RESET} 📈  Cloud status & quota"
    echo -e "  ${C_GREEN}7)${C_RESET} 🧹  Clean MEGA cloud"
    echo -e "  ${C_GREEN}8)${C_RESET} 🕘  Backup history"
    echo -e "  ${C_GREEN}9)${C_RESET} ⚙️   Settings"
    echo -e "  ${C_GREEN}10)${C_RESET} 🩺  Self-test / health check"
    echo -e "  ${C_GREEN}11)${C_RESET} 🔑  Setup / add MEGA account"
    echo -e "  ${C_GREEN}12)${C_RESET} ⬆️   Update tool (git pull)"
    echo -e "  ${C_GREEN}13)${C_RESET} 🔎  Diagnostics"
    echo -e "  ${C_GREEN}0)${C_RESET} 🚪  Exit"
    hr
    local c; c="$(ask 'Choose an option' '')"
    case "$c" in
       1) scan_device ;;
       2) backup_mirror "copy" ;;
       3) backup_mirror "sync" ;;
       4) backup_zip ;;
       5) restore_menu ;;
       6) cloud_status ;;
       7) clean_cloud ;;
       8) show_history ;;
       9) settings_menu; load_config ;;
       10) self_test ;;
       11) setup_mega_remote ""; pause ;;
       12) self_update; pause ;;
       13) tool_diag; pause ;;
       0) echo -e "${C_CYAN}Goodbye!${C_RESET}"; exit 0 ;;
       *) warn "Invalid option."; sleep 1 ;;
    esac
  done
}

# --- CLI (non-interactive) support ---
cli() {
  load_config
  ensure_rclone >/dev/null 2>&1 || die "rclone unavailable (need internet on first run)."
  ensure_jq >/dev/null 2>&1 || true
  case "$1" in
    scan)        scan_device ;;
    backup)      backup_mirror "copy" ;;
    incremental) backup_mirror "sync" ;;
    zip)         backup_zip ;;
    restore)     restore_menu ;;
    status)      cloud_status ;;
    selftest)    self_test ;;
    update)      self_update ;;
    diag)        tool_diag ;;
    *) echo "Usage: tnxbackup.sh [scan|backup|incremental|zip|restore|status|selftest|update|diag]"; exit 1 ;;
  esac
}

# --- Entry ---
if [ $# -gt 0 ]; then
  # allow selftest/scan even before init
  [ -f "$TNX_DIR/.initialized" ] || bootstrap
  cli "$@"
else
  bootstrap
  update_check
  main_menu
fi
