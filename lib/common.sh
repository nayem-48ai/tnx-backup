#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Common helpers, colors, logging, config
# =====================================================

# --- Resolve project directories ---
TNX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TNX_LIB="$TNX_ROOT/lib"
TNX_CONF_DIR="$TNX_ROOT/config"
TNX_CONF="$TNX_CONF_DIR/tnxbackup.conf"
TNX_FILTERS="$TNX_CONF_DIR/filters.txt"
TNX_PROFILES="$TNX_CONF_DIR/profiles"
TNX_LOGDIR="$TNX_ROOT/logs"
TNX_REPORTDIR="$TNX_ROOT/reports"
TNX_HISTORY="$TNX_ROOT/logs/history.json"

# Keep rclone's remote config INSIDE the project so it's easy to find/backup.
# (rclone defaults to ~/.config/rclone/rclone.conf otherwise.)
export RCLONE_CONFIG="$TNX_CONF_DIR/rclone.conf"

mkdir -p "$TNX_LOGDIR" "$TNX_REPORTDIR" "$TNX_PROFILES"

# --- Environment detection (native Termux vs PRoot/distro) ---
# $PREFIX is set ONLY in native Termux (points at the Termux usr dir). Inside a
# PRoot/distro (e.g. Ubuntu) $PREFIX is unset, and /sdcard is typically NOT bound
# to the real Android storage -> scans come back empty. We detect this so we can
# warn the user to run the tool from native Termux.
detect_env() {
  if [ -n "${PREFIX:-}" ]; then
    TNX_ENV="termux"
  else
    TNX_ENV="proot_or_linux"
  fi
}
detect_env

# --- Colors (auto-disable if not a terminal) ---
if [ -t 1 ]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
  C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
  C_BLUE='\033[34m'; C_MAGENTA='\033[35m'; C_CYAN='\033[36m'; C_WHITE='\033[37m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
  C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_WHITE=''
fi

# --- Logging ---
TNX_RUNLOG="$TNX_LOGDIR/run-$(date +%Y%m%d_%H%M%S).log"
log()   { echo -e "$(date '+%H:%M:%S') $*" | tee -a "$TNX_RUNLOG" >/dev/null; }
info()  { echo -e "${C_CYAN}[i]${C_RESET} $*"; log "[i] $*"; }
ok()    { echo -e "${C_GREEN}[✔]${C_RESET} $*"; log "[OK] $*"; }
warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*"; log "[WARN] $*"; }
err()   { echo -e "${C_RED}[x]${C_RESET} $*" >&2; log "[ERR] $*"; }
die()   { err "$*"; exit 1; }

hr()    { echo -e "${C_DIM}────────────────────────────────────────────────────${C_RESET}"; }
title() { echo -e "${C_BOLD}${C_MAGENTA}$*${C_RESET}"; }

pause() { echo; read -rp "$(echo -e "${C_DIM}Press Enter to continue...${C_RESET}")" _; }

confirm() {
  # confirm "message" -> returns 0 if yes
  local msg="$1" ans
  read -rp "$(echo -e "${C_YELLOW}${msg} [y/N]: ${C_RESET}")" ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

ask() {
  # ask "prompt" "default" -> echoes answer
  local prompt="$1" def="$2" ans
  if [ -n "$def" ]; then
    read -rp "$(echo -e "${C_CYAN}${prompt} ${C_DIM}[${def}]${C_RESET}: ")" ans
    echo "${ans:-$def}"
  else
    read -rp "$(echo -e "${C_CYAN}${prompt}${C_RESET}: ")" ans
    echo "$ans"
  fi
}

# --- Config loader ---
load_config() {
  [ -f "$TNX_CONF" ] || die "Config not found: $TNX_CONF (run first-run wizard)"
  # shellcheck disable=SC1090
  source "$TNX_CONF"
  : "${SOURCE_ROOT:=/sdcard}"
  : "${REMOTES:=mega}"
  : "${REMOTE_BASE:=TNxBackup}"
  : "${DEFAULT_MODE:=mirror}"
  : "${DEFAULT_PROFILE:=full}"
  : "${RETENTION_KEEP:=5}"
  : "${RETENTION_DAYS:=0}"
  : "${GUARD_ENABLE:=true}"
  : "${GUARD_MIN_BATTERY:=20}"
  : "${GUARD_REQUIRE_WIFI:=true}"
  : "${RCLONE_TRANSFERS:=4}"
  : "${RCLONE_CHECKERS:=8}"
  : "${ZIP_COMPRESSOR:=pigz}"
  PRIMARY_REMOTE="$(echo "$REMOTES" | awk '{print $1}')"
}

set_conf_value() {
  # set_conf_value KEY VALUE  (updates tnxbackup.conf in place)
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$TNX_CONF"; then
    sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$TNX_CONF"
  else
    echo "${key}=\"${val}\"" >> "$TNX_CONF"
  fi
}

human() {
  # human <bytes> -> human readable
  numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1}B"
}

require_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- History manifest (JSON array) ---
init_history() { [ -f "$TNX_HISTORY" ] || echo "[]" > "$TNX_HISTORY"; }
add_history() {
  # add_history mode remote profile status size files dest
  init_history
  local entry
  entry=$(jq -n \
    --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" \
    --arg mode "$1" --arg remote "$2" --arg profile "$3" \
    --arg status "$4" --arg size "$5" --arg files "$6" --arg dest "$7" \
    '{time:$ts,mode:$mode,remote:$remote,profile:$profile,status:$status,size:$size,files:$files,dest:$dest}')
  jq ". += [$entry]" "$TNX_HISTORY" > "$TNX_HISTORY.tmp" && mv "$TNX_HISTORY.tmp" "$TNX_HISTORY"
}

banner() {
  clear 2>/dev/null || true
  echo -e "${C_BOLD}${C_CYAN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║           TNx  BACKUP   TOOL   v1.0           ║"
  echo "  ║      Android  →  MEGA   (rclone powered)      ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${C_RESET}"
}
