#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Portable bootstrap
#  Auto-downloads static binaries (rclone, jq) into ./bin
#  so users DON'T need to install anything system-wide.
#  Requires only: internet + curl/wget + unzip + tar (usually present)
# =====================================================

TNX_BIN="$TNX_ROOT/bin"
mkdir -p "$TNX_BIN"
# Prepend our portable bin dir so bare `rclone`/`jq` calls resolve here first
case ":$PATH:" in *":$TNX_BIN:"*) ;; *) export PATH="$TNX_BIN:$PATH" ;; esac

# --- Detect platform ---
detect_arch() {
  local m; m="$(uname -m)"
  case "$m" in
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l|arm) echo "arm" ;;
    x86_64|amd64) echo "amd64" ;;
    i386|i686) echo "386" ;;
    *) echo "unknown" ;;
  esac
}
detect_os() {
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "osx" ;;
    *) echo "unknown" ;;
  esac
}

_dl() {
  # _dl <url> <output>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    return 127
  fi
}

# --- Ensure portable rclone ---
# We ALWAYS prefer our own ./bin/rclone. A system rclone (e.g. apt/Termux
# package) may predate/lack the MEGA backend or be broken, which produces
# cryptic errors like "unexpected end of JSON input". Only fall back to a
# system rclone if we cannot download our own.
ensure_rclone() {
  local os arch url tmp d
  os="$(detect_os)"; arch="$(detect_arch)"
  [ "$arch" = "unknown" ] && { err "Unsupported CPU arch: $(uname -m)"; return 1; }

  if [ -x "$TNX_BIN/rclone" ] && "$TNX_BIN/rclone" help backends 2>/dev/null | grep -qi '^  mega'; then
    return 0   # our portable, MEGA-capable binary is good
  fi

  url="https://downloads.rclone.org/rclone-current-${os}-${arch}.zip"
  info "Downloading portable rclone ($os-$arch)..."
  tmp="$(mktemp -d)"
  if ! _dl "$url" "$tmp/rclone.zip"; then
    rm -rf "$tmp"
    # Fallback: try any system rclone that has the MEGA backend
    if command -v rclone >/dev/null 2>&1 && rclone help backends 2>/dev/null | grep -qi '^  mega'; then
      warn "Using system rclone (download failed). If login fails, run: pkg install ca-certificates"
      return 0
    fi
    err "Download failed (need curl/wget + internet)."; return 1
  fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$tmp/rclone.zip" -d "$tmp"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$tmp/rclone.zip" "$tmp"
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$tmp/rclone.zip" -C "$tmp"
  else
    err "Need one of: unzip / python3 / bsdtar to extract rclone. Try: pkg install unzip"; rm -rf "$tmp"; return 1
  fi
  d="$(find "$tmp" -maxdepth 1 -type d -name 'rclone-*' | head -1)"
  cp "$d/rclone" "$TNX_BIN/rclone" && chmod +x "$TNX_BIN/rclone"
  rm -rf "$tmp"
  hash -r
  if [ -x "$TNX_BIN/rclone" ] && "$TNX_BIN/rclone" help backends 2>/dev/null | grep -qi '^  mega'; then
    ok "Portable rclone ready: $("$TNX_BIN/rclone" version | head -1)"
  else
    err "Downloaded rclone lacks MEGA backend."; return 1
  fi
}

# --- Force HTTP/1.1 for rclone ---
# Some mobile carriers / transparent proxies mangle HTTP/2 (chunked) responses
# from MEGA, which makes rclone receive an empty body and fail with
# "unexpected end of JSON input". Forcing HTTP/1.1 (content-length framed)
# avoids that truncation. Safe and applies to all rclone calls.
export RCLONE_DISABLE_HTTP2=true

# --- TLS / CA certificates ---
# The static rclone build does NOT bundle CA certs. On Termux, if the
# ca-certificates package is missing, TLS to MEGA fails and rclone returns
# "unexpected end of JSON input" (empty response). Point rclone at the
# system CA bundle so logins succeed.
ensure_ca() {
  local bundle=""
  for p in "${PREFIX:+${PREFIX}/etc/tls/cert.pem}" \
           "${PREFIX:+${PREFIX}/etc/ssl/certs/ca-certificates.crt}" \
           "/data/data/com.termux/files/usr/etc/tls/cert.pem" \
           "/data/data/com.termux/files/usr/etc/ssl/certs/ca-certificates.crt" \
           "/etc/ssl/certs/ca-certificates.crt"; do
    [ -f "$p" ] && { bundle="$p"; break; }
  done
  if [ -n "$bundle" ]; then
    export RCLONE_CACERT="$bundle"
    export SSL_CERT_FILE="$bundle"
    export CURL_CERT_FILE="$bundle"
  else
    warn "No CA certificate bundle found. If MEGA login fails with a JSON error,"
    warn "run:  pkg install ca-certificates   then restart the tool."
  fi
}

# --- Migrate any pre-existing rclone remote config into the project ---
migrate_rclone_config() {
  local def="$HOME/.config/rclone/rclone.conf"
  if [ ! -f "$TNX_CONF_DIR/rclone.conf" ] && [ -f "$def" ] && [ -s "$def" ]; then
    cp "$def" "$TNX_CONF_DIR/rclone.conf"
    ok "Imported existing rclone remotes from $def into the project."
  fi
}

# --- Ensure portable jq ---
ensure_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  local os arch url
  arch="$(detect_arch)"; os="$(detect_os)"
  case "$os" in linux) os="linux" ;; osx) os="macos" ;; esac
  url="https://github.com/jqlang/jq/releases/latest/download/jq-${os}-${arch}"
  info "Downloading portable jq ($os-$arch)..."
  if _dl "$url" "$TNX_BIN/jq"; then chmod +x "$TNX_BIN/jq"; hash -r; ok "Portable jq ready."; else
    warn "Could not fetch jq (history/quota parsing may be limited)."
  fi
}

# --- Master bootstrap: make everything runnable with no system install ---
portable_bootstrap() {
  banner
  title "  PORTABLE BOOTSTRAP"
  hr
  info "Preparing self-contained tools (no system install needed)..."

  # tar / gzip are effectively always present; pigz is optional
  command -v tar  >/dev/null 2>&1 || warn "'tar' missing (zip mode needs it)."
  command -v gzip >/dev/null 2>&1 || warn "'gzip' missing."
  if ! command -v pigz >/dev/null 2>&1; then
    ZIP_COMPRESSOR="gzip"   # graceful fallback for this run
  fi

  migrate_rclone_config
  ensure_jq
  ensure_ca
  ensure_rclone || die "rclone is required and could not be prepared."
  ok "All tools ready (portable)."
  hr
}

# Lightweight, non-blocking update check (prints only if behind).
update_check() {
  require_cmd git || return 0
  [ -d "$TNX_ROOT/.git" ] || return 0
  git -C "$TNX_ROOT" fetch --quiet origin 2>/dev/null || return 0
  local behind; behind="$(git -C "$TNX_ROOT" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "$behind" != "0" ] && [ -n "$behind" ]; then
    echo -e "${C_YELLOW}[!] Update available ($behind commit(s)). Run menu option 12 to update.${C_RESET}"
  fi
}
