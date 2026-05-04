#!/bin/bash
# Phase 4 — JavaScript / source code mining for hostname references
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ JS files)
# Reference: PAT      /Methodology and Resources/Web Attack Surface.md
#
# Why: Internal apps reference each other in JS files, redirects, and API calls.
# These hostnames are not in CT logs and are missed by pure passive enumeration.
# Especially valuable for wildcard-cert domains (Phase 2 flagged) where CT-log
# tools return zero results.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/subdomains"
LIVE="$ENGAGEMENT_DIR/live/probed.tsv"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/04_js_mining.log"
JS_OUT="$OUT/js_mined.txt"
> "$JS_OUT"
mkdir -p "$(dirname $LOG)"

echo "[*] Phase 4 — JS / source mining" | tee "$LOG"

# Pick targets to crawl: use the live web apps if Phase 7 already ran, else use seeds
TARGETS=()
if [ -f "$LIVE" ]; then
    while IFS=$'\t' read -r host scheme status _; do
        [ "$status" = "200" ] && TARGETS+=("$scheme://$host")
    done < <(awk -F'\t' 'NR>1' "$LIVE")
else
    while read -r ROOT; do
        TARGETS+=("https://$ROOT" "https://www.$ROOT")
    done < "$SEEDS"
fi

echo "    targets: ${#TARGETS[@]} live apps" | tee -a "$LOG"

for url in "${TARGETS[@]}"; do
    echo "    [+] crawl $url" | tee -a "$LOG"

    # katana — fast JS-aware crawler
    if command -v katana &>/dev/null; then
        katana -u "$url" -jc -d 2 -silent -timeout 10 2>/dev/null \
          | grep -oE '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' \
          >> "$JS_OUT" || true
    fi

    # gospider as fallback
    if command -v gospider &>/dev/null; then
        gospider -s "$url" -d 1 --js -t 5 --timeout 10 -q 2>/dev/null \
          | grep -oE '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' \
          >> "$JS_OUT" || true
    fi
done

# Filter to org-related domains only
> "$OUT/js_filtered.txt"
while read -r ROOT; do
    grep -E "\.${ROOT//./\\.}$" "$JS_OUT" 2>/dev/null >> "$OUT/js_filtered.txt"
done < "$SEEDS"

sort -u "$OUT/js_filtered.txt" -o "$OUT/js_filtered.txt"

NEW=$(comm -23 "$OUT/js_filtered.txt" "$OUT/all_master.txt" 2>/dev/null | wc -l)
echo "[+] Phase 4 complete." | tee -a "$LOG"
echo "    JS-mined hostnames: $(wc -l < $OUT/js_filtered.txt)" | tee -a "$LOG"
echo "    NEW (not in passive enum): $NEW" | tee -a "$LOG"

# Merge into master
sort -u "$OUT/all_master.txt" "$OUT/js_filtered.txt" -o "$OUT/all_master.txt"
