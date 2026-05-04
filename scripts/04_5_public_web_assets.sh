#!/bin/bash
# Phase 4.5 — Public web asset reading (robots.txt, security.txt, sitemap, doc paths)
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md
# Reference: RFC 9116 (security.txt)
#
# Why: Every live web app has standard convention files that often leak admin
# paths, internal contacts, full URL inventory, or API doc paths. Pure GET-and-read.
# A senior pentester always checks these first.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/web_assets"
LIVE="$ENGAGEMENT_DIR/live/probed.tsv"
LOG="$ENGAGEMENT_DIR/logs/04_5_public_web_assets.log"
mkdir -p "$OUT"

[ ! -f "$LIVE" ] && { echo "Run Phase 7 first"; exit 1; }

PATHS=(
    "/robots.txt"
    "/security.txt"
    "/.well-known/security.txt"
    "/humans.txt"
    "/sitemap.xml"
    "/sitemap_index.xml"
    "/api-docs"
    "/swagger-ui"
    "/swagger-ui.html"
    "/v2/api-docs"
    "/v3/api-docs"
    "/graphql"
    "/.well-known/openid-configuration"
    "/.well-known/oauth-authorization-server"
    "/ads.txt"
)

echo "[*] Phase 4.5 — Public web asset reading" | tee "$LOG"

# Get only HTTP 200 hosts from probed.tsv
HOSTS=$(awk -F'\t' 'NR>1 && $3=="200" {print $1"\t"$2}' "$LIVE")

> "$OUT/findings.tsv"
echo -e "host\tpath\tstatus\tsize" > "$OUT/findings.tsv"

while IFS=$'\t' read -r host scheme; do
    [ -z "$host" ] && continue
    for p in "${PATHS[@]}"; do
        body=$(curl -sk --max-time 6 "$scheme://$host$p" 2>/dev/null)
        code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 6 "$scheme://$host$p" 2>/dev/null)
        size=${#body}
        if [ "$code" = "200" ] && [ "$size" -gt 50 ]; then
            safe_path=$(echo "$p" | tr '/' '_' | tr -d '.')
            echo "$body" > "$OUT/${host}${safe_path}.txt"
            echo -e "$host\t$p\t$code\t$size" >> "$OUT/findings.tsv"
            echo "    [+] $host$p -> $code ($size bytes)" | tee -a "$LOG"
        fi
    done
done <<< "$HOSTS"

# Extract Disallow paths from any robots.txt — these go into Active Scan target list
> "$OUT/disallowed_paths.txt"
for f in "$OUT"/*_robotstxt.txt; do
    [ -f "$f" ] || continue
    host=$(basename "$f" _robotstxt.txt)
    grep -i '^Disallow:' "$f" | awk '{print $2}' | while read -r path; do
        [ -n "$path" ] && [ "$path" != "/" ] && echo "${host}${path}" >> "$OUT/disallowed_paths.txt"
    done
done
sort -u "$OUT/disallowed_paths.txt" -o "$OUT/disallowed_paths.txt"

# Extract URLs from sitemap.xml
> "$OUT/sitemap_urls.txt"
for f in "$OUT"/*_sitemapxml.txt "$OUT"/*_sitemap_indexxml.txt; do
    [ -f "$f" ] || continue
    grep -oP '<loc>\K[^<]+' "$f" >> "$OUT/sitemap_urls.txt" || true
done
sort -u "$OUT/sitemap_urls.txt" -o "$OUT/sitemap_urls.txt"

TOTAL_HITS=$(($(wc -l < "$OUT/findings.tsv") - 1))
echo ""
echo "[+] Phase 4.5 complete." | tee -a "$LOG"
echo "    Files harvested: $TOTAL_HITS" | tee -a "$LOG"
echo "    Disallowed paths extracted: $(wc -l < $OUT/disallowed_paths.txt)" | tee -a "$LOG"
echo "    Sitemap URLs extracted: $(wc -l < $OUT/sitemap_urls.txt)" | tee -a "$LOG"
