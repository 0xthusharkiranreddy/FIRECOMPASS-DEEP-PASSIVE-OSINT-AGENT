#!/bin/bash
# Phase 7.7 — Wayback Machine deep URL crawl
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Wayback Machine)
# Reference: PAT /Methodology and Resources/Network Pivoting Techniques.md
#
# Why: The Wayback Machine preserves crawled URLs for years — deleted pages,
# old admin panels, legacy APIs, backup files (.bak/.zip/.sql), and endpoints
# that were once public and are now "hidden" all remain discoverable.
# Key findings this produces:
#   - /api/v1/ paths → direct active-test candidates
#   - *.bak / *.sql / *.zip / *.tar.gz → accidental data exposure
#   - /admin/ / /wp-admin/ / /phpmyadmin/ → admin panel paths
#   - Parameter names (id=, file=, path=) → injection-point hints
#   - Subdomain URLs seen in archives → new targets not in current DNS
#
# Tools: gau (GetAllUrls — wraps Wayback + URLScan + OTX + CommonCrawl),
#         waybackurls (go binary, direct CDX API query), curl fallback to CDX API.
# This is fully passive — read-only queries to public archives.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/wayback_urls"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
MASTER_SUB="$ENGAGEMENT_DIR/subdomains/all_master.txt"
LOG="$ENGAGEMENT_DIR/logs/07d_wayback_url_crawl.log"
mkdir -p "$OUT"

[ ! -f "$SEEDS" ] && { echo "Run Phase 0 first (needs seeds/seed_roots.txt)"; exit 1; }

echo "[*] Phase 7.7 — Wayback Machine deep URL crawl" | tee "$LOG"
log_phase_start "7.7" "Wayback Machine / Historical URL Crawl"
log_hypothesis \
    "Historical crawl archives preserve URLs that no longer appear in current DNS, sitemaps, or live responses — including deleted admin panels, legacy APIs, and backup files" \
    "Query Wayback CDX API (or gau/waybackurls if installed) for all archived URLs across scope domains, then filter by extension and path pattern" \
    "If zero archived URLs returned for a domain, it is either too new (check whois creation date) or was never publicly crawled (dark/internal-only)"

# Build query scope: roots + top subdomains (live ones are most valuable)
SCOPE_LIST="$OUT/scope.txt"
{ cat "$SEEDS"; [ -f "$MASTER_SUB" ] && cat "$MASTER_SUB"; } | sort -u > "$SCOPE_LIST"
TOTAL=$(wc -l < "$SCOPE_LIST")
echo "    scope: $TOTAL domains" | tee -a "$LOG"

# Cap to first 50 to avoid hammering public APIs — prioritise roots
HEAD_SCOPE="$OUT/scope_capped.txt"
head -50 "$SCOPE_LIST" > "$HEAD_SCOPE"

ALL_URLS="$OUT/all_urls_raw.txt"
> "$ALL_URLS"

while read -r DOMAIN; do
    [ -z "$DOMAIN" ] && continue

    # ── Method 1: gau (if installed) ──────────────────────────────
    if command -v gau &>/dev/null; then
        echo "    [gau] $DOMAIN" | tee -a "$LOG"
        gau --threads 3 --timeout 20 "$DOMAIN" 2>/dev/null >> "$ALL_URLS" || true

    # ── Method 2: waybackurls (if installed) ──────────────────────
    elif command -v waybackurls &>/dev/null; then
        echo "    [waybackurls] $DOMAIN" | tee -a "$LOG"
        waybackurls "$DOMAIN" 2>/dev/null >> "$ALL_URLS" || true

    # ── Method 3: CDX API (pure curl fallback — always available) ──
    else
        echo "    [CDX API] $DOMAIN" | tee -a "$LOG"
        # CDX API — fl=original returns just the original URLs, collapse=urlkey dedupes
        CDX_URL="http://web.archive.org/cdx/search/cdx?url=*.${DOMAIN}/*&output=text&fl=original&collapse=urlkey&limit=3000"
        curl -sk --max-time 30 "$CDX_URL" 2>/dev/null >> "$ALL_URLS" || true
        # Also query the domain itself (non-wildcard)
        CDX_EXACT="http://web.archive.org/cdx/search/cdx?url=${DOMAIN}/*&output=text&fl=original&collapse=urlkey&limit=2000"
        curl -sk --max-time 30 "$CDX_EXACT" 2>/dev/null >> "$ALL_URLS" || true
    fi

done < "$HEAD_SCOPE"

# Dedupe
sort -u "$ALL_URLS" -o "$ALL_URLS"
TOTAL_URLS=$(wc -l < "$ALL_URLS")
echo "    raw URLs collected: $TOTAL_URLS" | tee -a "$LOG"

# ── Filtering & Categorisation ────────────────────────────────────────────────

# Interesting file extensions
grep -iE '\.(bak|sql|zip|tar\.gz|tgz|7z|rar|gz|dump|db|sqlite|mdb|log|swp|old|orig|backup|cfg|conf|config|env|ini|yml|yaml|json|xml|csv|xls|xlsx)(\?|$)' \
    "$ALL_URLS" | sort -u > "$OUT/interesting_files.txt"

# API / endpoint paths
grep -iE '/api/|/rest/|/graphql|/v[0-9]+/|/ajax/|/json/|/xml/|/soap/|/rpc/|/ws/|/webhook' \
    "$ALL_URLS" | sort -u > "$OUT/api_endpoints.txt"

# Admin / management paths
grep -iE '/admin|/wp-admin|/phpmyadmin|/manager|/dashboard|/panel|/console|/controlpanel|/manage|/webadmin|/sysadmin|/administrator|/backend|/portal' \
    "$ALL_URLS" | sort -u > "$OUT/admin_paths.txt"

# Auth paths
grep -iE '/login|/signin|/auth|/oauth|/sso|/saml|/ldap|/token|/logout|/register|/signup|/forgot|/reset.?password|/mfa|/2fa' \
    "$ALL_URLS" | sort -u > "$OUT/auth_paths.txt"

# Upload / file handling paths
grep -iE '/upload|/download|/file|/attachment|/media|/assets|/static|/public|/storage|/export|/import' \
    "$ALL_URLS" | sort -u > "$OUT/file_paths.txt"

# URLs with parameters (injection-point hints)
grep -E '\?' "$ALL_URLS" | grep -E '=[^&]+' | sort -u > "$OUT/parameterised_urls.txt"

# Extract unique parameter names
grep -oP '(?<=[?&])[^=&]+(?==)' "$OUT/parameterised_urls.txt" | sort | uniq -c | sort -rn \
    | head -50 > "$OUT/parameter_frequency.txt"

# Extract subdomains from URLs not yet in master list
grep -oP 'https?://([^/]+)' "$ALL_URLS" | sed 's|https\?://||' | sort -u > "$OUT/subdomains_in_urls.txt"
if [ -f "$MASTER_SUB" ]; then
    comm -23 <(sort "$OUT/subdomains_in_urls.txt") <(sort "$MASTER_SUB") > "$OUT/new_subdomains_from_wayback.txt"
    NEW_SUBS=$(wc -l < "$OUT/new_subdomains_from_wayback.txt")
    echo "    NEW subdomains discovered via Wayback: $NEW_SUBS" | tee -a "$LOG"
    if [ "$NEW_SUBS" -gt 0 ]; then
        sort -u "$MASTER_SUB" "$OUT/new_subdomains_from_wayback.txt" -o "$MASTER_SUB"
        echo "    → merged into all_master.txt" | tee -a "$LOG"
    fi
fi

# Summary
echo "" | tee -a "$LOG"
echo "[+] Phase 7.7 complete." | tee -a "$LOG"
echo "    Total URLs:           $TOTAL_URLS" | tee -a "$LOG"
echo "    Interesting files:    $(wc -l < $OUT/interesting_files.txt)" | tee -a "$LOG"
echo "    API endpoints:        $(wc -l < $OUT/api_endpoints.txt)" | tee -a "$LOG"
echo "    Admin paths:          $(wc -l < $OUT/admin_paths.txt)" | tee -a "$LOG"
echo "    Auth paths:           $(wc -l < $OUT/auth_paths.txt)" | tee -a "$LOG"
echo "    Parameterised URLs:   $(wc -l < $OUT/parameterised_urls.txt)" | tee -a "$LOG"
echo "    Unique param names:   $(wc -l < $OUT/parameter_frequency.txt)" | tee -a "$LOG"

[ -s "$OUT/interesting_files.txt" ] && echo "    [!] REVIEW: interesting_files.txt — potential data exposure" | tee -a "$LOG"
[ -s "$OUT/admin_paths.txt" ]       && echo "    [!] REVIEW: admin_paths.txt — admin/management panels" | tee -a "$LOG"

log_stats "Phase 7.7 results" \
    "Total archived URLs:${TOTAL_URLS}" \
    "Interesting files (bak/sql/zip):$(wc -l < $OUT/interesting_files.txt)" \
    "API endpoints:$(wc -l < $OUT/api_endpoints.txt)" \
    "Admin paths:$(wc -l < $OUT/admin_paths.txt)" \
    "Auth paths:$(wc -l < $OUT/auth_paths.txt)" \
    "Parameterised URLs:$(wc -l < $OUT/parameterised_urls.txt)"
[ -s "$OUT/interesting_files.txt" ] && log_finding HIGH "Wayback: $(wc -l < $OUT/interesting_files.txt) historically-accessible backup/data files found — review immediately"
[ -s "$OUT/admin_paths.txt" ]       && log_finding NOTABLE "Wayback: $(wc -l < $OUT/admin_paths.txt) historical admin panel paths — check if still live in Phase 7 data"
[ "${NEW_SUBS:-0}" -gt 0 ]          && log_finding NOTABLE "Wayback: $NEW_SUBS subdomains discovered in URL archives not found in any other source"
log_phase_end "7.7" "Wayback crawl complete. $TOTAL_URLS archived URLs processed. Key categories written to wayback_urls/."
