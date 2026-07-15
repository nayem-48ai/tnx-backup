#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Battery / Wi-Fi guard
# =====================================================

get_battery_pct() {
  # Try termux-api, then /sys, else empty
  if require_cmd termux-battery-status; then
    termux-battery-status 2>/dev/null | jq -r '.percentage' 2>/dev/null
    return
  fi
  local f
  for f in /sys/class/power_supply/*/capacity; do
    [ -r "$f" ] && { cat "$f"; return; }
  done
  echo ""
}

is_on_wifi() {
  # returns 0 if on wifi, 1 if not, 2 if unknown
  if require_cmd termux-wifi-connectioninfo; then
    local ssid
    ssid=$(termux-wifi-connectioninfo 2>/dev/null | jq -r '.ssid' 2>/dev/null)
    [ -n "$ssid" ] && [ "$ssid" != "null" ] && [ "$ssid" != "<unknown ssid>" ] && return 0 || return 1
  fi
  # fallback: check for wlan interface with an IP
  if require_cmd ip; then
    ip addr show 2>/dev/null | grep -qE "wlan[0-9].*inet " && return 0 || return 1
  fi
  return 2
}

guard_check() {
  # Returns 0 = OK to proceed, 1 = blocked
  [ "$GUARD_ENABLE" != "true" ] && return 0
  title "Pre-flight guard check"

  # Battery
  local pct
  pct="$(get_battery_pct)"
  if [ -n "$pct" ]; then
    if [ "$pct" -lt "$GUARD_MIN_BATTERY" ]; then
      warn "Battery ${pct}% is below minimum ${GUARD_MIN_BATTERY}%."
      confirm "Proceed anyway?" || return 1
    else
      ok "Battery: ${pct}% (min ${GUARD_MIN_BATTERY}%)"
    fi
  else
    warn "Battery level unknown (termux-api not available) - skipping battery guard."
  fi

  # Wi-Fi
  if [ "$GUARD_REQUIRE_WIFI" = "true" ]; then
    is_on_wifi; local w=$?
    case $w in
      0) ok "Network: Wi-Fi connected." ;;
      1) warn "Not on Wi-Fi (mobile data may incur charges)."
         confirm "Proceed on non-Wi-Fi?" || return 1 ;;
      2) warn "Network type unknown - skipping Wi-Fi guard." ;;
    esac
  fi
  return 0
}
