#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Dependency check, first-run wizard, self-test
# =====================================================

REQUIRED_CORE=(rclone tar jq du df find awk sed grep numfmt)

install_hint() {
  echo -e "${C_YELLOW}Install missing packages with:${C_RESET}"
  echo "   pkg install rclone jq tar pigz coreutils   # Termux"
  echo "   apt install rclone jq tar pigz coreutils   # proot/Debian"
}

check_deps() {
  local missing=()
  for c in "${REQUIRED_CORE[@]}"; do
    require_cmd "$c" || missing+=("$c")
  done
  # optional
  require_cmd "$ZIP_COMPRESSOR" 2>/dev/null || true
  if [ ${#missing[@]} -gt 0 ]; then
    err "Missing required tools: ${missing[*]}"
    install_hint
    return 1
  fi
  return 0
}

# --- Detect termux-api (battery/notification), degrade gracefully ---
has_termux_api() { require_cmd termux-battery-status; }
notify() {
  # notify "title" "content"
  if require_cmd termux-notification; then
    termux-notification --title "$1" --content "$2" >/dev/null 2>&1 || true
  fi
}

first_run_wizard() {
  banner
  title "  FIRST-RUN SETUP WIZARD"
  hr
  info "This one-time wizard prepares TNx Backup."
  echo

  # 1. deps (portable-first: no system install required)
  info "Step 1/4: Preparing tools (portable)..."
  ensure_rclone || die "Could not prepare rclone."
  ensure_jq || true
  for c in tar gzip; do require_cmd "$c" || warn "'$c' not found (needed for zip mode)."; done
  ok "Tools ready (portable, no system install)."
  echo

  # 2. storage permission
  info "Step 2/4: Storage access..."
  if [ -d "$SOURCE_ROOT" ] && ls "$SOURCE_ROOT" >/dev/null 2>&1; then
    ok "Storage reachable at $SOURCE_ROOT"
  else
    warn "Cannot read $SOURCE_ROOT."
    if require_cmd termux-setup-storage; then
      info "Running termux-setup-storage (grant the permission popup)..."
      termux-setup-storage; sleep 2
    fi
  fi
  echo

  # 3. MEGA remote
  info "Step 3/4: MEGA account setup..."
  if rclone listremotes 2>/dev/null | grep -q "^${PRIMARY_REMOTE}:"; then
    ok "Remote '${PRIMARY_REMOTE}' already configured."
  else
    setup_mega_remote "$PRIMARY_REMOTE"
  fi
  echo

  # 4. done
  info "Step 4/4: Finalizing..."
  init_history
  touch "$TNX_ROOT/.initialized"
  ok "Setup complete!"
  pause
}

setup_mega_remote() {
  # setup_mega_remote <remotename>
  local rname="$1"
  [ -z "$rname" ] && rname="$(ask 'Remote name' 'mega')"
  title "Configure MEGA remote: $rname"
  local email pass
  email="$(ask 'MEGA email' '')"
  read -rsp "$(echo -e "${C_CYAN}MEGA password${C_RESET}: ")" pass; echo
  [ -z "$email" ] && { err "Email cannot be empty."; return 1; }
  [ -z "$pass" ]  && { err "Password cannot be empty."; return 1; }

  info "Creating rclone remote '$rname'..."
  # Force-obscure the password (version-safe across rclone builds)
  if ! rclone config create "$rname" mega user "$email" pass "$pass" --obscure >/dev/null 2>&1; then
    err "Failed to create remote."
    return 1
  fi
  ok "Remote '$rname' created."

  # --- Connection test with retries (MEGA can rate-limit fresh logins) ---
  if test_remote "$rname"; then
    ok "MEGA connection successful."
  else
    warn "Connection test did not pass yet."
    echo -e "   ${C_DIM}Checking if MEGA is reachable from this network...${C_RESET}"
    if mega_reachable >/dev/null 2>&1; then
      echo -e "   ${C_DIM}MEGA API is reachable, so the empty login reply is one of:${C_RESET}"
      echo -e "   ${C_DIM}1) Temporary account lockout from too many logins. FIX: open${C_RESET}"
      echo -e "   ${C_DIM}   https://mega.nz in a browser, go to Settings > Security >${C_RESET}"
      echo -e "   ${C_DIM}   'Close all sessions', then wait ~10 min and retry.${C_RESET}"
      echo -e "   ${C_DIM}2) Carrier/proxy truncating MEGA's login reply. FIX: try a VPN${C_RESET}"
      echo -e "   ${C_DIM}   or a different network.${C_RESET}"
    else
      local code; code="$(mega_reachable 2>/dev/null)"
      echo -e "   ${C_RED}MEGA API is NOT reachable from this network (HTTP ${code:-no response}).${C_RESET}"
      echo -e "   ${C_DIM}This is a network/region block on MEGA. Try a VPN or another network.${C_RESET}"
    fi
    echo -e "   ${C_DIM}Run menu option 13 'Diagnostics' (it saves a raw login capture)${C_RESET}"
    echo -e "   ${C_DIM}for deeper analysis. Credentials are saved.${C_RESET}"
  fi

  # --- Register remote into REMOTES so backups can find it ---
  register_remote "$rname"
  return 0
}

# Retry connection test; prints the real error on final failure
test_remote() {
  local r="$1" i out
  for i in 1 2 3 4 5; do
    info "Testing connection (attempt $i/5)..."
    out="$(timeout 60 rclone about "${r}:" --low-level-retries 10 --contimeout 30s --timeout 60s --retries 3 2>&1)"
    if echo "$out" | grep -q "Total:"; then
      echo "$out" | grep -E "Total:|Used:|Free:" | sed 's/^/   /'
      return 0
    fi
    local reason; reason="$(echo "$out" | grep -iE "error|fatal|denied|failed|429|too many|end of JSON" | head -1)"
    [ -n "$reason" ] && warn "   -> ${reason}"
    [ "$i" -lt 5 ] && sleep 8
  done
  return 1
}

# Add a remote name to REMOTES in the config file if not already present
register_remote() {
  local r="$1"
  load_config
  if echo " $REMOTES " | grep -q " $r "; then
    return 0   # already registered
  fi
  if [ -z "$REMOTES" ] || [ "$REMOTES" = "mega" ] && ! rclone listremotes 2>/dev/null | grep -q "^mega:"; then
    set_conf_value REMOTES "$r"       # replace default placeholder
  else
    set_conf_value REMOTES "$REMOTES $r"
  fi
  ok "Remote '$r' registered for backups."
}

# --- HTTP status of MEGA's API endpoint (unauthenticated ping) ---
mega_http_code() {
  if command -v curl >/dev/null 2>&1; then
    curl -sS -m 15 -o /dev/null -w '%{http_code}' 'https://g.api.mega.co.nz/cs' 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -S -O /dev/null 'https://g.api.mega.co.nz/cs' 2>&1 | grep -i 'HTTP/' | tail -1 | awk '{print $2}'
  fi
}

# --- Is MEGA actually reachable from this network? (proves block vs creds) ---
mega_reachable() {
  # returns 0 if the MEGA API endpoint answers 200, 1 if blocked/unreachable
  local code; code="$(mega_http_code)"
  [ "$code" = "200" ] && return 0
  echo "$code"
  return 1
}

# --- Manage MEGA accounts: list / add / delete ---
manage_accounts() {
  while true; do
    banner; title "  MEGA ACCOUNTS"; hr
    load_config
    local i=1; declare -gA ACCT_MAP; ACCT_MAP=()
    local r
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      ACCT_MAP[$i]="$r"; echo -e "  ${C_GREEN}$i)${C_RESET} $r"; i=$((i+1))
    done < <(rclone listremotes 2>/dev/null | sed 's/:$//')
    [ "$((i-1))" -eq 0 ] && echo -e "  ${C_DIM}(no accounts configured)${C_RESET}"
    hr
    echo -e "  ${C_GREEN}a)${C_RESET} Add new account"
    echo -e "  ${C_GREEN}d)${C_RESET} Delete account"
    echo -e "  ${C_GREEN}b)${C_RESET} Back"
    local c; c="$(ask 'Select' 'b')"
    case "$c" in
      a|A)
        setup_mega_remote "$(ask 'Remote name (e.g. mega)' 'mega')"
        pause
        ;;
      d|D)
        [ "$((i-1))" -eq 0 ] && { warn "Nothing to delete."; sleep 1; continue; }
        local n name
        n="$(ask 'Enter number of account to delete' '')"
        name="${ACCT_MAP[$n]:-}"
        [ -z "$name" ] && { warn "Invalid number."; sleep 1; continue; }
        if confirm "Delete remote '$name'? Its backups will stop."; then
          rclone config delete "$name" 2>/dev/null && ok "Deleted remote '$name'."
          # remove from REMOTES list
          local nr=""
          for r in $REMOTES; do [ "$r" != "$name" ] && nr="${nr:+$nr }$r"; done
          set_conf_value REMOTES "${nr:-mega}"
          load_config
        fi
        pause
        ;;
      *) return ;;
    esac
  done
}

self_test() {
  banner
  title "  SELF-TEST / HEALTH CHECK"
  hr
  local fail=0

  echo -e "${C_BOLD}Dependencies:${C_RESET}"
  for c in "${REQUIRED_CORE[@]}" "$ZIP_COMPRESSOR"; do
    if require_cmd "$c"; then echo -e "  ${C_GREEN}✔${C_RESET} $c"; else echo -e "  ${C_RED}✗${C_RESET} $c"; fail=1; fi
  done
  echo

  echo -e "${C_BOLD}Storage:${C_RESET}"
  if ls "$SOURCE_ROOT" >/dev/null 2>&1; then
    echo -e "  ${C_GREEN}✔${C_RESET} $SOURCE_ROOT readable ($(du -sh "$SOURCE_ROOT" 2>/dev/null | awk '{print $1}'))"
  else
    echo -e "  ${C_RED}✗${C_RESET} $SOURCE_ROOT not readable"; fail=1
  fi
  echo

  echo -e "${C_BOLD}Config files:${C_RESET}"
  for f in "$TNX_CONF" "$TNX_FILTERS"; do
    [ -f "$f" ] && echo -e "  ${C_GREEN}✔${C_RESET} $(basename "$f")" || { echo -e "  ${C_RED}✗${C_RESET} $(basename "$f")"; fail=1; }
  done
  echo

  echo -e "${C_BOLD}Remotes:${C_RESET}"
  for r in $REMOTES; do
    if rclone listremotes 2>/dev/null | grep -q "^${r}:"; then
      if rclone about "${r}:" >/dev/null 2>&1; then
        echo -e "  ${C_GREEN}✔${C_RESET} ${r}: online"
      else
        echo -e "  ${C_YELLOW}!${C_RESET} ${r}: configured but unreachable"
      fi
    else
      echo -e "  ${C_RED}✗${C_RESET} ${r}: not configured"; fail=1
    fi
  done
  echo

  echo -e "${C_BOLD}Termux API (battery/notify):${C_RESET}"
  has_termux_api && echo -e "  ${C_GREEN}✔${C_RESET} available" || echo -e "  ${C_YELLOW}!${C_RESET} not available (guard/notify will degrade gracefully)"
  echo; hr
  [ $fail -eq 0 ] && ok "Health check passed." || warn "Health check found issues (see above)."
  pause
}
