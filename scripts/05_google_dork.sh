#!/bin/bash
# Phase 5 — Google / Bing dorking for indexed subdomains
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Google Dorks)
#
# Why: Search engines index subdomains regardless of naming convention. A Google
# dork takes 10 seconds and catches things wordlists never will. Especially
# useful when the company has linked an internal tool from a public page.
#
# NOTE: Google has aggressive anti-bot measures. Best results via:
#   - Browser-driven: open the dork URLs manually
#   - SerpAPI / Bing Web Search API if you have a key
#   - This script gives you the ready-made URLs and tries Bing scraping

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/subdomains"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/05_google_dork.log"
DORK_URLS="$OUT/dork_urls.txt"
> "$DORK_URLS"

echo "[*] Phase 5 — Google / Bing dorking" | tee "$LOG"

while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    cat >> "$DORK_URLS" <<EOF
# === $ROOT ===
https://www.google.com/search?q=site%3A${ROOT}
https://www.google.com/search?q=site%3A${ROOT}+-www
https://www.google.com/search?q=site%3A${ROOT}+inurl%3Aadmin
https://www.google.com/search?q=site%3A${ROOT}+inurl%3Alogin
https://www.google.com/search?q=site%3A${ROOT}+inurl%3Aportal
https://www.google.com/search?q=site%3A${ROOT}+intitle%3A%22index+of%22
https://www.google.com/search?q=site%3A${ROOT}+filetype%3Apdf
https://www.bing.com/search?q=site%3A${ROOT}
https://duckduckgo.com/?q=site%3A${ROOT}
EOF

    # Bing API scraping (works passively without auth, low rate)
    echo "    [+] bing site:$ROOT" | tee -a "$LOG"
    curl -sA "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36" \
         --max-time 20 "https://www.bing.com/search?q=site:${ROOT}&count=50&first=1" 2>/dev/null \
      | grep -oE "[a-zA-Z0-9._-]+\.${ROOT//./\\.}" | sort -u > "$OUT/bing_${ROOT}.txt" || true
done < "$SEEDS"

# Aggregate
cat "$OUT"/bing_*.txt 2>/dev/null | sort -u > "$OUT/dork_aggregated.txt"

NEW=$(comm -23 "$OUT/dork_aggregated.txt" "$OUT/all_master.txt" 2>/dev/null | wc -l)
echo ""
echo "[+] Phase 5 complete." | tee -a "$LOG"
echo "    Dork-found hostnames: $(wc -l < $OUT/dork_aggregated.txt)" | tee -a "$LOG"
echo "    NEW (not in master): $NEW" | tee -a "$LOG"
echo ""
echo "[!] MANUAL STEP RECOMMENDED:"
echo "    Open each URL in $DORK_URLS in a real browser to catch what Bing scraping missed."
echo "    Especially useful for: indexed admin panels, leaked PDFs, directory listings."

sort -u "$OUT/all_master.txt" "$OUT/dork_aggregated.txt" -o "$OUT/all_master.txt"
