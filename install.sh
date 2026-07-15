#!/usr/bin/env bash
# =====================================================
#  TNx Backup - One-command installer / updater
#  Usage:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nayem-48ai/tnx-backup/main/install.sh)
#  Or locally:
#    ./install.sh
#  Safe to re-run: updates an existing checkout instead of re-cloning.
# =====================================================
set -euo pipefail

REPO="https://github.com/nayem-48ai/tnx-backup.git"
DIR="$HOME/tnx-backup"

# Termux basics
if command -v pkg >/dev/null 2>&1; then
  pkg update -y >/dev/null 2>&1 || true
  pkg install -y git ca-certificates curl unzip >/dev/null 2>&1 || true
fi

if [ -d "$DIR/.git" ]; then
  echo "==> Updating existing install at $DIR"
  git -C "$DIR" pull --ff-only
else
  echo "==> Cloning $REPO into $DIR"
  rm -rf "$DIR"
  git clone "$REPO" "$DIR"
fi

chmod +x "$DIR/tnxbackup.sh" "$DIR/lib/"*.sh

echo "==> Done. Launching TNx Backup..."
cd "$DIR"
exec ./tnxbackup.sh "$@"
