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
  info "Creating rclone remote '$rname'..."
  if rclone config create "$rname" mega user "$email" pass "$pass" >/dev/null 2>&1; then
    ok "Remote '$rname' created."
    info "Testing connection..."
    if rclone about "${rname}:" >/dev/null 2>&1; then
      ok "MEGA connection successful."
    else
      warn "Remote created but connection test failed. Check credentials/network."
    fi
  else
    err "Failed to create remote."
    return 1
  fi
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
