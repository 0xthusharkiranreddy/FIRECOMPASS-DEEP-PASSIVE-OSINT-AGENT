#!/bin/bash
# Phase 15 — Mobile app surface (public app store enumeration)
# Reference: HackTricks /src/mobile-pentesting/android-app-pentesting/README.md
# Reference: HackTricks /src/mobile-pentesting/ios-pentesting/README.md
# Reference: PAT /Methodology and Resources/Mobile Application Penetration Testing.md
#
# Why: Mobile apps expose significant attack surface that web recon misses entirely:
#   - APK/IPA names and bundle IDs → confirm org identity + find sister apps
#   - Google Play Store listings → permission lists, developer email, screenshots
#   - Apple App Store listings → bundle ID, support URL, privacy policy URL
#   - Hard-coded API endpoints in app descriptions or "What's new" text
#   - App version history → old deprecated endpoints still running in prod
#   - Associated developer account → other apps by same org (subsidiary discovery)
#   - App permissions (Android) → infer what data/sensors the app accesses
#
# Tools used (all passive — no app download or decompilation here):
#   - iTunes Search API (Apple App Store) — public, no key needed
#   - Google Play unofficial search via apkcombo.com API or web scrape
#   - APKPure / APKCombo search (public HTML scrape)
#   - F-Droid search (open-source Android apps)
#
# Note: Active decompilation (jadx, apktool, MobSF) belongs in the active-scan agent.
# This phase is purely passive enumeration of public app store metadata.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/mobile"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/15_mobile_app_surface.log"
mkdir -p "$OUT"

[ ! -f "$SEEDS" ] && { echo "Run Phase 0 first"; exit 1; }

PRIMARY_DOMAIN=$(head -1 "$SEEDS")
ORG_KEYWORDS=$(awk -F'.' '{print $1}' "$SEEDS" | sort -u | head -5)

echo "[*] Phase 15 — Mobile app surface enumeration" | tee "$LOG"
log_phase_start "15" "Mobile App Surface (App Store Enumeration)"
log_hypothesis \
    "Org has published iOS and/or Android apps that expose bundle IDs, developer accounts, API URL hints, and permission profiles" \
    "Query iTunes Search API (Apple) and scrape Google Play for org keywords; cross-check apple-app-site-association from Phase 7.6 for bundle IDs" \
    "If zero apps found, org may use private enterprise distribution — note as gap; a healthcare/B2B org may have no consumer-facing apps"
echo "    primary domain: $PRIMARY_DOMAIN" | tee -a "$LOG"
echo "    org keywords: $ORG_KEYWORDS" | tee -a "$LOG"

echo -e "store\tapp_id\tapp_name\tdev_name\tdev_email\tbundle_id\tprimary_url\tpermissions_count\tdescription_hint" \
    > "$OUT/app_store_findings.tsv"

echo -e "store\tapp_id\tapp_name\tapi_endpoint_hint" > "$OUT/app_api_hints.tsv"

# ── Apple App Store (iTunes Search API) ──────────────────────────────────────
echo "  [*] Apple App Store search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    ITUNES=$(curl -sk --max-time 20 \
        "https://itunes.apple.com/search?term=${KW}&entity=software&limit=25&country=us" \
        2>/dev/null)

    if echo "$ITUNES" | grep -q '"trackId"'; then
        echo "$ITUNES" | python3 -c "
import json, sys

data = json.load(sys.stdin)
for app in data.get('results', []):
    app_id     = str(app.get('trackId', ''))
    app_name   = app.get('trackName', '').replace('\t', ' ')
    dev_name   = app.get('artistName', '').replace('\t', ' ')
    bundle_id  = app.get('bundleId', '')
    url        = app.get('trackViewUrl', '')
    desc       = app.get('description', '')[:200].replace('\t', ' ').replace('\n', ' ')
    genres     = ', '.join(app.get('genres', []))

    # Look for API endpoint hints in description
    import re
    api_hints = re.findall(r'https?://[^\s\"<>]+api[^\s\"<>]*', desc, re.I)

    print(f'AppStore\t{app_id}\t{app_name}\t{dev_name}\t\t{bundle_id}\t{url}\t\t{desc}')
    for hint in api_hints:
        print(f'HINT\t{app_id}\t{app_name}\t{hint}', file=sys.stderr)
" 2>>"$OUT/app_api_hints_raw.txt" >> "$OUT/app_store_findings.tsv" || true
        echo "    [AppStore] $KW → hits logged" | tee -a "$LOG"
    fi
done

# ── Google Play Store (via gPlayApi / web scrape fallback) ───────────────────
echo "  [*] Google Play Store search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    # Use Google Play web search — extract app IDs from SERP
    GP_HTML=$(curl -sk --max-time 20 \
        -H "User-Agent: Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36" \
        "https://play.google.com/store/search?q=${KW}&c=apps" \
        2>/dev/null)

    if [ -n "$GP_HTML" ]; then
        # Extract package names from Google Play HTML
        APP_IDS=$(echo "$GP_HTML" | grep -oP '(?<=id=)[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+' | sort -u | head -20)
        for APP_ID in $APP_IDS; do
            # Fetch individual app page for metadata
            GP_APP=$(curl -sk --max-time 15 \
                -H "User-Agent: Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36" \
                "https://play.google.com/store/apps/details?id=${APP_ID}&hl=en" \
                2>/dev/null)

            APP_NAME=$(echo "$GP_APP" | grep -oP '(?<=<title>)[^<]+' | head -1 | sed 's/ - Apps on Google Play//')
            DESC_PREVIEW=$(echo "$GP_APP" | grep -oP '(?<="description">)[^<]{20,200}' | head -1 | tr -d '\n')
            DEV_NAME=$(echo "$GP_APP" | grep -oP '(?<=seller":")[^"]+' | head -1)

            echo -e "GooglePlay\t${APP_ID}\t${APP_NAME}\t${DEV_NAME}\t\t${APP_ID}\thttps://play.google.com/store/apps/details?id=${APP_ID}\t\t${DESC_PREVIEW}" \
                >> "$OUT/app_store_findings.tsv"
            echo "    [GooglePlay] $APP_ID → $APP_NAME" | tee -a "$LOG"
        done
    fi
done

# ── APKCombo search (alternative APK index) ──────────────────────────────────
echo "  [*] APKCombo / APKPure search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    APC=$(curl -sk --max-time 15 \
        "https://apkcombo.com/en/search/?q=${KW}" 2>/dev/null)
    if [ -n "$APC" ]; then
        APP_IDS=$(echo "$APC" | grep -oP '(?<=href="/[^/]+/)[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+(?=/)' | sort -u | head -10)
        for AID in $APP_IDS; do
            echo -e "APKCombo\t${AID}\t${KW} result\t\t\t${AID}\thttps://apkcombo.com/search/?q=${AID}\t\t" \
                >> "$OUT/app_store_findings.tsv"
        done
    fi
done

# ── Domain-linked iOS app (apple-app-site-association cross-check) ────────────
# If Phase 7.6 found apple-app-site-association, extract bundle IDs from it
WELLKNOWN="$ENGAGEMENT_DIR/web_surface/wellknown_findings.tsv"
if [ -f "$WELLKNOWN" ]; then
    AASA_ENTRIES=$(grep -i 'apple-app-site-association' "$WELLKNOWN" | cut -f4)
    if [ -n "$AASA_ENTRIES" ]; then
        echo "  [*] Extracting bundle IDs from apple-app-site-association" | tee -a "$LOG"
        echo "$AASA_ENTRIES" | grep -oP '"appID"\s*:\s*"[^"]+"' | sed 's/"appID"\s*:\s*"//' | tr -d '"' | \
        while read -r BUNDLE; do
            echo "    [AASA] bundle ID: $BUNDLE" | tee -a "$LOG"
            echo -e "AASA-linked\t${BUNDLE}\t\t\t\t${BUNDLE}\t\t\t" >> "$OUT/app_store_findings.tsv"
        done
    fi
fi

# ── Build dork URLs for analyst manual review ─────────────────────────────────
DORK_FILE="$OUT/mobile_dork_urls.txt"
> "$DORK_FILE"
for KW in $ORG_KEYWORDS; do
    echo "# $KW" >> "$DORK_FILE"
    echo "https://play.google.com/store/search?q=${KW}&c=apps" >> "$DORK_FILE"
    echo "https://www.apple.com/search/?q=${KW}" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:play.google.com+%22${KW}%22" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:apps.apple.com+%22${KW}%22" >> "$DORK_FILE"
    echo "https://apkcombo.com/search/?q=${KW}" >> "$DORK_FILE"
    echo "" >> "$DORK_FILE"
done

# Dedupe findings
sort -u "$OUT/app_store_findings.tsv" -o "$OUT/app_store_findings.tsv"

TOTAL_APPS=$(($(wc -l < "$OUT/app_store_findings.tsv") - 1))
echo "" | tee -a "$LOG"
echo "[+] Phase 15 complete." | tee -a "$LOG"
echo "    App listings found:  $TOTAL_APPS" | tee -a "$LOG"
echo "    API hints from apps: $(wc -l < $OUT/app_api_hints.tsv 2>/dev/null || echo 0)" | tee -a "$LOG"
echo "    Manual dork URLs:    $(grep -c '^https://' $DORK_FILE 2>/dev/null || echo 0)" | tee -a "$LOG"
[ "$TOTAL_APPS" -gt 0 ] && echo "    [+] Review app_store_findings.tsv for app surface and developer account leaks" | tee -a "$LOG"

log_stats "Phase 15 results" \
    "App listings found:${TOTAL_APPS}" \
    "API hints from app descriptions:$(wc -l < $OUT/app_api_hints.tsv 2>/dev/null || echo 0)" \
    "Manual dork URLs generated:$(grep -c '^https://' $DORK_FILE 2>/dev/null || echo 0)"
[ "$TOTAL_APPS" -gt 0 ] && log_finding NOTABLE "Mobile: $TOTAL_APPS app listings found — review bundle IDs and developer accounts for additional scope"
log_phase_end "15" "Mobile surface enumeration complete. $TOTAL_APPS apps found. Details in mobile/app_store_findings.tsv."
