#!/bin/bash
# Phase 7.5 — Live application fingerprinting (passive header analysis)
# Reference: HackTricks /src/network-services-pentesting/pentesting-web/README.md (§ Web Server Identification)
# Reference: PAT      /Methodology and Resources/Web Attack Surface.md
#
# Why: Knowing what tech stack each live app runs is essential for active-test
# prioritisation. CMS (WordPress/Drupal/Joomla), framework (Laravel/Django/Rails),
# server (Apache/IIS/nginx), CDN (Cloudflare/Akamai/Fastly), WAF (Cloudflare/AWS WAF/F5)
# all change the active-test playbook.
#
# This is passive — only inspects HTTP response headers and HTML content from a
# single GET we already did in Phase 7. No active fuzzing.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/fingerprint"
PROBED="$ENGAGEMENT_DIR/live/probed.tsv"
LOG="$ENGAGEMENT_DIR/logs/07b_live_app_fingerprint.log"
mkdir -p "$OUT"

[ ! -f "$PROBED" ] && { echo "Run Phase 7 first"; exit 1; }

echo "[*] Phase 7.5 — Live app fingerprinting" | tee "$LOG"
log_phase_start "7.5b" "Live Application Fingerprinting (Header Analysis)"
log_hypothesis \
    "Response headers and first 50KB of HTML body reveal server, framework, CDN, WAF, and CMS without active probing" \
    "Single curl GET per live host — parse Server, X-Powered-By, Set-Cookie, CF-Ray, and HTML body patterns" \
    "If all hosts return minimal/stripped headers, a WAF or CDN is aggressively removing them — note as finding"

# Extract live HTTP 200 hosts
LIVE_HOSTS="$OUT/live_hosts.txt"
awk -F'\t' 'NR>1 && $3==200 {print $2"://"$1}' "$PROBED" | sort -u > "$LIVE_HOSTS"
COUNT=$(wc -l < "$LIVE_HOSTS")
echo "    targets: $COUNT live hosts" | tee -a "$LOG"

> "$OUT/headers_raw.tsv"
echo -e "url\tserver\tx_powered_by\tcdn\twaf\tframework\tcms\tcookies_hint" > "$OUT/headers_raw.tsv"

while read -r URL; do
    [ -z "$URL" ] && continue
    HEADERS=$(curl -skI -L --max-time 8 "$URL" 2>/dev/null)
    BODY=$(curl -sk -L --max-time 8 -r 0-50000 "$URL" 2>/dev/null)

    SERVER=$(echo "$HEADERS"      | grep -i '^server:'       | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
    POWERED=$(echo "$HEADERS"     | grep -i '^x-powered-by:' | head -1 | cut -d: -f2- | tr -d '\r' | xargs)
    COOKIES=$(echo "$HEADERS"     | grep -i '^set-cookie:'   | head -3 | cut -d: -f2- | tr -d '\r' | tr '\n' ';' | head -c 150)

    # CDN detection
    CDN=""
    echo "$HEADERS" | grep -qi 'cf-ray\|cloudflare'        && CDN="Cloudflare"
    echo "$HEADERS" | grep -qi 'akamai\|x-akamai'          && CDN="Akamai"
    echo "$HEADERS" | grep -qi 'fastly'                    && CDN="Fastly"
    echo "$HEADERS" | grep -qi 'x-cdn:.*aws\|cloudfront'   && CDN="CloudFront"
    echo "$HEADERS" | grep -qi 'x-azure-ref\|azureedge'    && CDN="Azure CDN"
    echo "$HEADERS" | grep -qi 'x-served-by.*fastly'       && CDN="Fastly"

    # WAF detection
    WAF=""
    echo "$HEADERS" | grep -qi 'cf-ray'                    && WAF="Cloudflare"
    echo "$HEADERS" | grep -qi 'x-sucuri\|sucuri'          && WAF="Sucuri"
    echo "$HEADERS" | grep -qi 'x-amz-cf-id.*waf\|x-amzn-waf' && WAF="AWS WAF"
    echo "$HEADERS" | grep -qi 'x-iinfo'                   && WAF="Imperva Incapsula"
    echo "$HEADERS" | grep -qi 'x-distil'                  && WAF="Distil"
    echo "$HEADERS" | grep -qi 'big-ip\|f5'                && WAF="F5 BIG-IP"

    # Framework / language hints
    FW=""
    echo "$HEADERS" | grep -qi 'x-powered-by:.*php'              && FW="PHP"
    echo "$HEADERS" | grep -qi 'x-aspnet-version\|asp.net'       && FW="ASP.NET"
    echo "$HEADERS" | grep -qi 'x-rack-cache\|x-runtime\|rails'  && FW="Rails"
    echo "$HEADERS" | grep -qi 'django'                          && FW="Django"
    echo "$HEADERS" | grep -qi 'express'                         && FW="Express"
    echo "$HEADERS" | grep -qi 'laravel_session' && FW="Laravel"
    echo "$BODY"    | grep -qi 'csrf-token.*name="_token"'       && FW="${FW:+$FW;}Laravel"

    # CMS detection
    CMS=""
    echo "$BODY" | grep -qi '/wp-content/\|/wp-includes/'        && CMS="WordPress"
    echo "$BODY" | grep -qi 'drupal-settings\|drupal\.org'       && CMS="Drupal"
    echo "$BODY" | grep -qi 'joomla\|/components/com_'           && CMS="Joomla"
    echo "$BODY" | grep -qi 'shopify\.com\|cdn\.shopify'         && CMS="Shopify"
    echo "$BODY" | grep -qi 'squarespace'                        && CMS="Squarespace"
    echo "$BODY" | grep -qi 'wix\.com'                           && CMS="Wix"
    echo "$BODY" | grep -qi 'magento'                            && CMS="Magento"
    echo "$BODY" | grep -qi 'sitecore'                           && CMS="Sitecore"
    echo "$BODY" | grep -qi 'sharepoint'                         && CMS="SharePoint"
    echo "$BODY" | grep -qi 'tomcat\|coyote'                     && CMS="${CMS:+$CMS;}Tomcat"
    echo "$BODY" | grep -qi 'jenkins'                            && CMS="${CMS:+$CMS;}Jenkins"
    echo "$BODY" | grep -qi 'gitlab\|gitlab-runner'              && CMS="${CMS:+$CMS;}GitLab"
    echo "$BODY" | grep -qi 'jira\|atlassian'                    && CMS="${CMS:+$CMS;}Jira/Atlassian"
    echo "$BODY" | grep -qi 'confluence'                         && CMS="${CMS:+$CMS;}Confluence"
    echo "$BODY" | grep -qi 'wazuh'                              && CMS="${CMS:+$CMS;}Wazuh-SIEM"
    echo "$BODY" | grep -qi 'splunk'                             && CMS="${CMS:+$CMS;}Splunk"
    echo "$BODY" | grep -qi 'grafana'                            && CMS="${CMS:+$CMS;}Grafana"
    echo "$BODY" | grep -qi 'kibana'                             && CMS="${CMS:+$CMS;}Kibana"
    echo "$BODY" | grep -qi 'filecloud'                          && CMS="${CMS:+$CMS;}FileCloud"
    echo "$BODY" | grep -qi 'nextcloud'                          && CMS="${CMS:+$CMS;}Nextcloud"
    echo "$BODY" | grep -qi 'owncloud'                           && CMS="${CMS:+$CMS;}ownCloud"

    echo -e "${URL}\t${SERVER}\t${POWERED}\t${CDN}\t${WAF}\t${FW}\t${CMS}\t${COOKIES}" >> "$OUT/headers_raw.tsv"

    # Flag interesting hits in real time
    [ -n "$CMS" ]    && echo "    [+] $URL → CMS: $CMS" | tee -a "$LOG"
    [ -n "$WAF" ]    && echo "    [+] $URL → WAF: $WAF" | tee -a "$LOG"

    # Write to engagement log for anything notable
    [ -n "$CMS" ]    && log_finding NOTABLE "Fingerprint: $URL → CMS: $CMS (tech-stack confirmed passively)"
    [ -n "$WAF" ]    && log_finding NOTABLE "Fingerprint: $URL → WAF: $WAF (active scan must account for WAF evasion)"
    echo "$CMS" | grep -qiE 'Jenkins|Wazuh|Splunk|Grafana|Kibana|GitLab' && \
        log_finding HIGH "EXPOSED INTERNAL TOOL: $URL → $CMS — security/DevOps tooling should not be public-facing"
done < "$LIVE_HOSTS"

FINGERPRINTED=$(($(wc -l < "$OUT/headers_raw.tsv") - 1))
SERVERS=$(awk -F'\t' 'NR>1 && $2!="" {print $2}' "$OUT/headers_raw.tsv" | sort -u | wc -l)
CDNS=$(awk -F'\t' 'NR>1 && $4!="" {print $4}' "$OUT/headers_raw.tsv" | sort -u | wc -l)
WAFS=$(awk -F'\t' 'NR>1 && $5!="" {print $5}' "$OUT/headers_raw.tsv" | sort -u | wc -l)
CMS_HITS=$(awk -F'\t' 'NR>1 && $7!="" {print $1}' "$OUT/headers_raw.tsv" | wc -l)

# Build summary
echo "" | tee -a "$LOG"
echo "[+] Phase 7.5 complete." | tee -a "$LOG"
echo "    Hosts fingerprinted: $FINGERPRINTED" | tee -a "$LOG"
echo "    Servers seen: $SERVERS" | tee -a "$LOG"
echo "    CDNs seen: $CDNS" | tee -a "$LOG"
echo "    WAFs seen: $WAFS" | tee -a "$LOG"
echo "    Apps with CMS detection: $CMS_HITS" | tee -a "$LOG"

log_stats "Phase 7.5b results" \
    "Hosts fingerprinted:${FINGERPRINTED}" \
    "Unique server software:${SERVERS}" \
    "CDN providers seen:${CDNS}" \
    "WAF solutions detected:${WAFS}" \
    "CMS/app identifications:${CMS_HITS}"
log_phase_end "7.5b" "Fingerprinting complete. $FINGERPRINTED hosts profiled. Full detail in fingerprint/headers_raw.tsv."
