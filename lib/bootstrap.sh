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
ensure_rclone() {
  if command -v rclone >/dev/null 2>&1 && rclone help backends 2>/dev/null | grep -qi '^  mega'; then
    return 0   # a MEGA-capable rclone already available
  fi
  local os arch url tmp d
  os="$(detect_os)"; arch="$(detect_arch)"
  [ "$arch" = "unknown" ] && { err "Unsupported CPU arch: $(uname -m)"; return 1; }
  url="https://downloads.rclone.org/rclone-current-${os}-${arch}.zip"
  info "Downloading portable rclone ($os-$arch)..."
  tmp="$(mktemp -d)"
  if ! _dl "$url" "$tmp/rclone.zip"; then err "Download failed (need curl/wget)."; rm -rf "$tmp"; return 1; fi
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
  command -v rclone >/dev/null 2>&1 && ok "Portable rclone ready: $(rclone version | head -1)" || return 1
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

  ensure_jq
  ensure_rclone || die "rclone is required and could not be prepared."
  ok "All tools ready (portable)."
  hr
}
