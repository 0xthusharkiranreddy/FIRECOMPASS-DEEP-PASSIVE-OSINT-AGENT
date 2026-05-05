#!/bin/bash
# Phase 7.6 — Web surface harvesting (passive meta-files)
# Reference: HackTricks /src/network-services-pentesting/pentesting-web/README.md (§ robots.txt / sitemap.xml)
# Reference: PAT /Methodology and Resources/Web Attack Surface.md
#
# Why: robots.txt, sitemap.xml, security.txt, humans.txt, and .well-known/ entries
# are intentionally published by the target and reveal:
#   - robots.txt  → Disallow paths = things they don't want crawled = attack surface
#   - sitemap.xml → All public URL paths they admit to having
#   - security.txt → Bug bounty scope, security contact, responsible disclosure policy
#   - humans.txt  → Team members, tech stack hints
#   - /.well-known/openid-configuration → OAuth2/OIDC IdP endpoints
#   - /.well-known/apple-app-site-association → iOS universal link domains
#   - /.well-known/assetlinks.json → Android app associations
#   - /.well-known/change-password → Password change endpoint (auth-surface hint)
#
# This is passive — only fetches publicly accessible meta-files at known paths.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/web_surface"
LIVE_PROBED="$ENGAGEMENT_DIR/live/probed.tsv"
LOG="$ENGAGEMENT_DIR/logs/07c_web_surface_harvest.log"
mkdir -p "$OUT"

[ ! -f "$LIVE_PROBED" ] && { echo "Run Phase 7 first (needs live/probed.tsv)"; exit 1; }

echo "[*] Phase 7.6 — Web surface harvesting" | tee "$LOG"
log_phase_start "7.6" "Web Surface Harvest (robots.txt / sitemap / security.txt / .well-known)"
log_hypothesis \
    "Publicly served meta-files reveal Disallow paths, published URL structure, security contacts, and OIDC/OAuth endpoints" \
    "Fetch robots.txt, sitemap.xml, security.txt, humans.txt, and 11 .well-known/ paths on every live host" \
    "If robots.txt returns 404 everywhere, org has no crawl policy published — note as gap, not a failure"

# Extract live HTTP 200 base URLs
LIVE_HOSTS="$OUT/live_bases.txt"
awk -F'\t' 'NR>1 && $3==200 {print $2"://"$1}' "$LIVE_PROBED" | sort -u > "$LIVE_HOSTS"
COUNT=$(wc -l < "$LIVE_HOSTS")
echo "    targets: $COUNT live hosts" | tee -a "$LOG"

# Output files
ROBOTS_OUT="$OUT/robots_disallow.txt"
SITEMAP_OUT="$OUT/sitemap_urls.txt"
SECURITY_OUT="$OUT/security_txt_findings.tsv"
WELLKNOWN_OUT="$OUT/wellknown_findings.tsv"

> "$ROBOTS_OUT"
> "$SITEMAP_OUT"
echo -e "url\tcontact\tencryption\tbug_bounty_policy\tscope_hint\texpires" > "$SECURITY_OUT"
echo -e "url\tpath\tstatus\tcontent_preview" > "$WELLKNOWN_OUT"

WELL_KNOWN_PATHS=(
    "/.well-known/openid-configuration"
    "/.well-known/oauth-authorization-server"
    "/.well-known/apple-app-site-association"
    "/.well-known/assetlinks.json"
    "/.well-known/change-password"
    "/.well-known/security.txt"
    "/.well-known/dnt-policy.txt"
    "/.well-known/host-meta"
    "/.well-known/webfinger"
    "/.well-known/caldav"
    "/.well-known/carddav"
)

while read -r BASE_URL; do
    [ -z "$BASE_URL" ] && continue
    HOST=$(echo "$BASE_URL" | sed 's|https\?://||')

    # ── robots.txt ──────────────────────────────────────────────
    ROBOTS=$(curl -sk -L --max-time 8 "${BASE_URL}/robots.txt" 2>/dev/null)
    if echo "$ROBOTS" | grep -qi 'user-agent\|disallow\|allow'; then
        DISALLOWS=$(echo "$ROBOTS" | grep -i '^Disallow:' | sed 's/Disallow:\s*//' | tr -d '\r' | head -30)
        if [ -n "$DISALLOWS" ]; then
            echo "# $BASE_URL" >> "$ROBOTS_OUT"
            echo "$DISALLOWS" | sed "s|^|${BASE_URL}|" >> "$ROBOTS_OUT"
            echo "" >> "$ROBOTS_OUT"
            DCOUNT=$(echo "$DISALLOWS" | grep -c .)
            echo "    [+] $HOST → robots.txt: $DCOUNT Disallow entries" | tee -a "$LOG"
        fi

        # Extract sitemap references from robots.txt
        SITEMAP_REFS=$(echo "$ROBOTS" | grep -i '^Sitemap:' | sed 's/Sitemap:\s*//' | tr -d '\r')
        for SM_URL in $SITEMAP_REFS; do
            SM_CONTENT=$(curl -sk -L --max-time 10 "$SM_URL" 2>/dev/null)
            if [ -n "$SM_CONTENT" ]; then
                echo "$SM_CONTENT" | grep -oP '(?<=<loc>)[^<]+' >> "$SITEMAP_OUT"
                echo "    [+] $HOST → sitemap from robots.txt: $SM_URL" | tee -a "$LOG"
            fi
        done
    fi

    # ── sitemap.xml (fallback if not in robots.txt) ──────────────
    SITEMAP=$(curl -sk -L --max-time 10 "${BASE_URL}/sitemap.xml" 2>/dev/null)
    if echo "$SITEMAP" | grep -qi '<url>\|<loc>'; then
        echo "$SITEMAP" | grep -oP '(?<=<loc>)[^<]+' >> "$SITEMAP_OUT"
        SM_COUNT=$(echo "$SITEMAP" | grep -c '<loc>')
        echo "    [+] $HOST → sitemap.xml: $SM_COUNT URLs" | tee -a "$LOG"
    fi

    # ── sitemap_index.xml ─────────────────────────────────────────
    SITEMAP_IDX=$(curl -sk -L --max-time 10 "${BASE_URL}/sitemap_index.xml" 2>/dev/null)
    if echo "$SITEMAP_IDX" | grep -qi '<sitemapindex\|<sitemap>'; then
        SUB_MAPS=$(echo "$SITEMAP_IDX" | grep -oP '(?<=<loc>)[^<]+')
        for SM in $SUB_MAPS; do
            SUB_CONTENT=$(curl -sk -L --max-time 10 "$SM" 2>/dev/null)
            echo "$SUB_CONTENT" | grep -oP '(?<=<loc>)[^<]+' >> "$SITEMAP_OUT"
        done
        echo "    [+] $HOST → sitemap_index.xml found" | tee -a "$LOG"
    fi

    # ── security.txt ──────────────────────────────────────────────
    for SEC_PATH in "/security.txt" "/.well-known/security.txt"; do
        SEC_CONTENT=$(curl -sk -L --max-time 8 "${BASE_URL}${SEC_PATH}" 2>/dev/null)
        if echo "$SEC_CONTENT" | grep -qi 'Contact:\|Encryption:\|Policy:'; then
            CONTACT=$(echo "$SEC_CONTENT" | grep -i '^Contact:'     | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
            ENCRYPT=$(echo "$SEC_CONTENT" | grep -i '^Encryption:'  | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
            POLICY=$(echo "$SEC_CONTENT"  | grep -i '^Policy:'      | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
            SCOPE=$(echo "$SEC_CONTENT"   | grep -i '^Scope:\|Hiring\|Bug' | head -1 | tr -d '\r' | head -c 120)
            EXPIRES=$(echo "$SEC_CONTENT" | grep -i '^Expires:'     | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
            echo -e "${BASE_URL}\t${CONTACT}\t${ENCRYPT}\t${POLICY}\t${SCOPE}\t${EXPIRES}" >> "$SECURITY_OUT"
            echo "    [+] $HOST → security.txt found at $SEC_PATH" | tee -a "$LOG"
            break
        fi
    done

    # ── humans.txt ────────────────────────────────────────────────
    HUMANS=$(curl -sk -L --max-time 8 "${BASE_URL}/humans.txt" 2>/dev/null)
    if echo "$HUMANS" | grep -qi 'team\|author\|developer\|twitter\|github'; then
        echo "    [+] $HOST → humans.txt found (team/tech hints)" | tee -a "$LOG"
        echo "# $BASE_URL" >> "$OUT/humans_txt_raw.txt"
        echo "$HUMANS" | head -40 >> "$OUT/humans_txt_raw.txt"
        echo "" >> "$OUT/humans_txt_raw.txt"
    fi

    # ── .well-known/ paths ────────────────────────────────────────
    for WKP in "${WELL_KNOWN_PATHS[@]}"; do
        WK_RESP=$(curl -sk -L -w '\n__STATUS__%{http_code}' --max-time 8 "${BASE_URL}${WKP}" 2>/dev/null)
        STATUS=$(echo "$WK_RESP" | grep -oP '(?<=__STATUS__)\d+')
        CONTENT=$(echo "$WK_RESP" | sed 's/__STATUS__[0-9]*//')

        if [[ "$STATUS" == "200" ]]; then
            PREVIEW=$(echo "$CONTENT" | tr -d '\n' | head -c 180)
            echo -e "${BASE_URL}\t${WKP}\t${STATUS}\t${PREVIEW}" >> "$WELLKNOWN_OUT"
            echo "    [+] $HOST → ${WKP} → HTTP 200" | tee -a "$LOG"

            # Special: extract OIDC issuer / auth endpoints
            if echo "$WKP" | grep -q 'openid-configuration'; then
                ISSUER=$(echo "$CONTENT" | grep -oP '"issuer"\s*:\s*"[^"]+"' | head -1)
                AUTH_EP=$(echo "$CONTENT" | grep -oP '"authorization_endpoint"\s*:\s*"[^"]+"' | head -1)
                TOKEN_EP=$(echo "$CONTENT" | grep -oP '"token_endpoint"\s*:\s*"[^"]+"' | head -1)
                echo "        OIDC issuer: $ISSUER" | tee -a "$LOG"
                echo "        auth_ep:     $AUTH_EP" | tee -a "$LOG"
                echo "        token_ep:    $TOKEN_EP" | tee -a "$LOG"
            fi
        fi
    done

done < "$LIVE_HOSTS"

# Dedupe sitemap URLs
if [ -s "$SITEMAP_OUT" ]; then
    sort -u "$SITEMAP_OUT" -o "$SITEMAP_OUT"
fi

# Summary
ROBOTS_COUNT=$(grep -c '^http' "$ROBOTS_OUT" 2>/dev/null || echo 0)
SITEMAP_COUNT=$(wc -l < "$SITEMAP_OUT" 2>/dev/null || echo 0)
SEC_COUNT=$(($(wc -l < "$SECURITY_OUT") - 1))
WK_COUNT=$(($(wc -l < "$WELLKNOWN_OUT") - 1))

echo "" | tee -a "$LOG"
echo "[+] Phase 7.6 complete." | tee -a "$LOG"
echo "    Hosts processed:         $COUNT" | tee -a "$LOG"
echo "    Robots.txt disallows:    $ROBOTS_COUNT" | tee -a "$LOG"
echo "    Sitemap URLs collected:  $SITEMAP_COUNT" | tee -a "$LOG"
echo "    security.txt found:      $SEC_COUNT" | tee -a "$LOG"
echo "    .well-known 200s:        $WK_COUNT" | tee -a "$LOG"

log_stats "Phase 7.6 results" \
    "Hosts processed:${COUNT}" \
    "robots.txt Disallow entries:${ROBOTS_COUNT}" \
    "Sitemap URLs:${SITEMAP_COUNT}" \
    "security.txt files:${SEC_COUNT}" \
    ".well-known 200 responses:${WK_COUNT}"
[ "$WK_COUNT" -gt 0 ] && log_finding NOTABLE "Phase 7.6: $WK_COUNT .well-known endpoints live — check wellknown_findings.tsv for OIDC/OAuth/app-association details"
[ "$ROBOTS_COUNT" -gt 0 ] && log_finding INFO "Phase 7.6: $ROBOTS_COUNT robots.txt Disallow paths collected — review for hidden attack surface"
log_phase_end "7.6" "Web surface harvest complete. Full data in web_surface/."
