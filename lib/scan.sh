#!/usr/bin/env bash
# =====================================================
#  TNx Backup - Device scan + HTML/CSV reports
# =====================================================

scan_device() {
  banner
  title "  DEVICE SCAN"
  hr
  local ts stamp csv html
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  stamp="$(date '+%Y%m%d_%H%M%S')"
  csv="$TNX_REPORTDIR/scan-$stamp.csv"
  html="$TNX_REPORTDIR/scan-$stamp.html"

  info "Scanning $SOURCE_ROOT ... (this may take a moment)"

  # --- Storage overview ---
  local dfline total used avail usep
  dfline="$(df -h "$SOURCE_ROOT" 2>/dev/null | tail -1)"
  total=$(echo "$dfline" | awk '{print $2}')
  used=$(echo "$dfline" | awk '{print $3}')
  avail=$(echo "$dfline" | awk '{print $4}')
  usep=$(echo "$dfline" | awk '{print $5}')

  local totalfiles totaldirs srcsize
  totalfiles=$(find "$SOURCE_ROOT" -type f 2>/dev/null | wc -l)
  totaldirs=$(find "$SOURCE_ROOT" -type d 2>/dev/null | wc -l)
  srcsize=$(du -sh "$SOURCE_ROOT" 2>/dev/null | awk '{print $1}')

  echo
  echo -e "${C_BOLD}Storage:${C_RESET} total ${C_CYAN}$total${C_RESET} | used ${C_YELLOW}$used${C_RESET} | free ${C_GREEN}$avail${C_RESET} | usage $usep"
  echo -e "${C_BOLD}$SOURCE_ROOT:${C_RESET} ${C_CYAN}$srcsize${C_RESET} | files: $totalfiles | folders: $totaldirs"
  hr

  # --- Per top-level folder sizes ---
  echo -e "${C_BOLD}Top-level folders (largest first):${C_RESET}"
  # header for CSV
  echo "path,size_human,size_bytes,type" > "$csv"

  # collect entries (folders + loose files), incl hidden
  local rows="" line p b h t
  while IFS= read -r line; do
    b=$(echo "$line" | awk '{print $1}')
    p=$(echo "$line" | cut -f2-)
    [ "$p" = "$SOURCE_ROOT" ] && continue
    h=$(numfmt --to=iec --suffix=B "$b" 2>/dev/null)
    if [ -d "$p" ]; then t="folder"; else t="file"; fi
    printf "  %-10s %s\n" "$h" "${p#$SOURCE_ROOT/}"
    echo "\"${p#$SOURCE_ROOT/}\",\"$h\",$b,$t" >> "$csv"
    rows+="<tr><td>${p#$SOURCE_ROOT/}</td><td>$h</td><td>$b</td><td>$t</td></tr>"
  done < <(du -ab --max-depth=1 "$SOURCE_ROOT" 2>/dev/null | sort -rn)

  hr
  # --- Largest 15 files ---
  echo -e "${C_BOLD}Largest 15 files:${C_RESET}"
  local bigrows=""
  while IFS= read -r line; do
    b=$(echo "$line" | awk '{print $1}')
    p=$(echo "$line" | cut -f2-)
    h=$(numfmt --to=iec --suffix=B "$b" 2>/dev/null)
    printf "  %-10s %s\n" "$h" "${p#$SOURCE_ROOT/}"
    bigrows+="<tr><td>${p#$SOURCE_ROOT/}</td><td>$h</td></tr>"
  done < <(find "$SOURCE_ROOT" -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -15)

  # --- Write HTML report ---
  cat > "$html" <<HTML
<!DOCTYPE html><html><head><meta charset="utf-8">
<title>TNx Backup - Device Scan $ts</title>
<style>
body{font-family:system-ui,Segoe UI,Roboto,sans-serif;background:#0f1420;color:#e6edf3;margin:0;padding:24px}
h1{color:#4dd0e1}h2{color:#ffb74d;border-bottom:1px solid #2a3346;padding-bottom:6px;margin-top:32px}
.cards{display:flex;gap:16px;flex-wrap:wrap;margin:16px 0}
.card{background:#161c2c;border:1px solid #2a3346;border-radius:12px;padding:16px 20px;min-width:140px}
.card .n{font-size:22px;font-weight:700;color:#4dd0e1}.card .l{font-size:12px;color:#8b98a9}
table{width:100%;border-collapse:collapse;margin-top:8px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #222b3d;font-size:14px}
th{color:#8b98a9;text-transform:uppercase;font-size:11px;letter-spacing:.05em}
tr:hover td{background:#131a28}.foot{margin-top:32px;color:#5a6577;font-size:12px}
</style></head><body>
<h1>TNx Backup — Device Scan Report</h1>
<div class="foot">Generated: $ts &nbsp;|&nbsp; Source: $SOURCE_ROOT</div>
<div class="cards">
<div class="card"><div class="n">$total</div><div class="l">Total storage</div></div>
<div class="card"><div class="n">$used</div><div class="l">Used</div></div>
<div class="card"><div class="n">$avail</div><div class="l">Free</div></div>
<div class="card"><div class="n">$srcsize</div><div class="l">$SOURCE_ROOT size</div></div>
<div class="card"><div class="n">$totalfiles</div><div class="l">Files</div></div>
<div class="card"><div class="n">$totaldirs</div><div class="l">Folders</div></div>
</div>
<h2>Top-level items</h2>
<table><tr><th>Path</th><th>Size</th><th>Bytes</th><th>Type</th></tr>$rows</table>
<h2>Largest 15 files</h2>
<table><tr><th>Path</th><th>Size</th></tr>$bigrows</table>
<div class="foot">TNx Backup Tool v1.0 — report auto-generated.</div>
</body></html>
HTML

  hr
  ok "Reports saved:"
  echo -e "   ${C_CYAN}CSV :${C_RESET} $csv"
  echo -e "   ${C_CYAN}HTML:${C_RESET} $html"
  pause
}
