#!/bin/bash
# Phase 7.5 — DNS records + tech fingerprint + CDN/WAF identification
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ DNS)
# Reference: RFC 7208 (SPF), RFC 6376 (DKIM), RFC 7489 (DMARC)
#
# Why: SPF and MX records reveal every 3rd-party SaaS the org uses. CDN/WAF
# identification changes engagement strategy. Tech-stack fingerprinting from
# response headers reveals targets without aggressive probing.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/ips"
HEADERS_OUT="$ENGAGEMENT_DIR/live/headers"
LIVE="$ENGAGEMENT_DIR/live/probed.tsv"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/07_5_dns_and_fingerprint.log"
mkdir -p "$OUT" "$HEADERS_OUT"

echo "[*] Phase 7.5 — DNS records + tech fingerprint" | tee "$LOG"

# 7.5.a — DNS records per root
echo "[7.5.a] Fetching DNS records per root domain" | tee -a "$LOG"
> "$OUT/dns_records.tsv"
echo -e "domain\ttype\tvalue" > "$OUT/dns_records.tsv"

while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    for type in A AAAA MX TXT NS CNAME SOA CAA SRV; do
        dig +short "$type" "$ROOT" 2>/dev/null | while read -r value; do
            [ -n "$value" ] && echo -e "$ROOT\t$type\t$value" >> "$OUT/dns_records.tsv"
        done
    done
done < "$SEEDS"

# Parse SPF — extract include: directives = 3rd-party SaaS authorised to send email
echo "[7.5.b] Extracting 3rd-party SaaS from SPF" | tee -a "$LOG"
grep -P 'TXT.*v=spf1' "$OUT/dns_records.tsv" \
  | grep -oP 'include:\K[^\s"]+' \
  | sort -u > "$OUT/spf_third_parties.txt"

# Parse DMARC
> "$OUT/dmarc_records.tsv"
while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    record=$(dig +short TXT "_dmarc.$ROOT" 2>/dev/null | head -1)
    [ -n "$record" ] && echo -e "$ROOT\t$record" >> "$OUT/dmarc_records.tsv"
done < "$SEEDS"

# DKIM selector enumeration
echo "[7.5.c] DKIM selector enumeration" | tee -a "$LOG"
> "$OUT/dkim_selectors.tsv"
SELECTORS=(default google selector1 selector2 mail dkim k1 k2 s1 s2 mandrill mailchimp mxvault)
while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    for sel in "${SELECTORS[@]}"; do
        record=$(dig +short TXT "${sel}._domainkey.$ROOT" 2>/dev/null | head -1)
        [ -n "$record" ] && echo -e "$ROOT\t$sel\t$record" >> "$OUT/dkim_selectors.tsv"
    done
done < "$SEEDS"

# 7.5.d — Tech fingerprint via response headers
echo "[7.5.d] Tech fingerprint via response headers (live 200 hosts)" | tee -a "$LOG"
> "$ENGAGEMENT_DIR/live/tech_fingerprint.tsv"
echo -e "host\tserver\tx_powered_by\tcdn\twaf\thsts\tcsp_internal_hosts" > "$ENGAGEMENT_DIR/live/tech_fingerprint.tsv"

if [ -f "$LIVE" ]; then
    awk -F'\t' 'NR>1 && $3=="200" {print $1"\t"$2}' "$LIVE" | while IFS=$'\t' read -r host scheme; do
        [ -z "$host" ] && continue
        headers=$(curl -skI --max-time 8 "$scheme://$host/" 2>/dev/null)
        echo "$headers" > "$HEADERS_OUT/${host}.txt"

        server=$(echo "$headers"      | grep -i '^Server:'             | awk '{print $2}' | tr -d '\r')
        powered=$(echo "$headers"     | grep -i '^X-Powered-By:'       | cut -d':' -f2-   | sed 's/^ //; s/\r//')
        cdn=""
        echo "$headers" | grep -qi 'CF-Ray\|CF-Cache-Status'           && cdn="Cloudflare"
        echo "$headers" | grep -qi 'X-Akamai\|akamai'                  && cdn="${cdn:+$cdn,}Akamai"
        echo "$headers" | grep -qi 'X-Served-By:.*fastly\|X-Cache.*fastly' && cdn="${cdn:+$cdn,}Fastly"
        echo "$headers" | grep -qi 'Server:.*cloudfront\|X-Amz-Cf-Id'  && cdn="${cdn:+$cdn,}CloudFront"

        waf=""
        echo "$headers" | grep -qi 'X-Sucuri\|sucuri'                  && waf="Sucuri"
        echo "$headers" | grep -qi 'X-Mod-Security\|mod_security'      && waf="${waf:+$waf,}ModSecurity"
        echo "$headers" | grep -qi 'X-Imperva\|incapsula'              && waf="${waf:+$waf,}Imperva"
        echo "$headers" | grep -qi 'AWSALB\|x-amzn-RequestId'          && waf="${waf:+$waf,}AWS-WAF"

        hsts=$(echo "$headers" | grep -qi '^Strict-Transport-Security' && echo "yes" || echo "no")

        # CSP internal host extraction
        csp_internal=$(echo "$headers" | grep -i '^Content-Security-Policy:' \
                       | grep -oP '(connect-src|script-src|frame-src)[^;]+' \
                       | grep -oP 'https?://[\w\-\.]+' | tr '\n' ',' | sed 's/,$//')

        echo -e "$host\t$server\t$powered\t$cdn\t$waf\t$hsts\t$csp_internal" >> "$ENGAGEMENT_DIR/live/tech_fingerprint.tsv"
    done
fi

# Summary
THIRD_PARTIES=$(wc -l < "$OUT/spf_third_parties.txt")
DKIM_FOUND=$(($(wc -l < "$OUT/dkim_selectors.tsv")))
TECH_HOSTS=$(($(wc -l < "$ENGAGEMENT_DIR/live/tech_fingerprint.tsv") - 1))

echo ""
echo "[+] Phase 7.5 complete." | tee -a "$LOG"
echo "    DNS records collected: $(wc -l < $OUT/dns_records.tsv)" | tee -a "$LOG"
echo "    3rd-party SaaS via SPF: $THIRD_PARTIES" | tee -a "$LOG"
echo "    DKIM selectors found: $DKIM_FOUND" | tee -a "$LOG"
echo "    Live hosts fingerprinted: $TECH_HOSTS" | tee -a "$LOG"
