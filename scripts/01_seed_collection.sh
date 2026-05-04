#!/bin/bash
# Phase 1 — Seed + Related Domain Discovery
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Acquisitions)
# Reference: PAT  /Methodology and Resources/Network Discovery.md
#
# Why: Primary domain is rarely the entire footprint. Companies own dozens of
# domains - acquisitions, regional brands, product domains, tenant clouds. Missing
# these means missing whole subsidiaries.

set -e
: "${ENGAGEMENT_DIR:?Run 00_setup_engagement.sh first or export ENGAGEMENT_DIR}"
: "${PRIMARY_DOMAIN:?export PRIMARY_DOMAIN=...}"
: "${ORG_NAME:?export ORG_NAME=...}"

OUT="$ENGAGEMENT_DIR/seeds"
LOG="$ENGAGEMENT_DIR/logs/01_seed_collection.log"
mkdir -p "$OUT" "$(dirname "$LOG")"

echo "[*] Phase 1 — Seed + Related Domain Discovery for $PRIMARY_DOMAIN" | tee "$LOG"

# 1.1 — WHOIS for the primary
echo "[1.1] WHOIS lookup" | tee -a "$LOG"
whois "$PRIMARY_DOMAIN" 2>/dev/null > "$OUT/whois_$PRIMARY_DOMAIN.txt" || true
grep -iE 'organization|registrant|email' "$OUT/whois_$PRIMARY_DOMAIN.txt" | head -20 | tee -a "$LOG"

# 1.2 — Reverse WHOIS via free APIs
echo "[1.2] Reverse WHOIS (viewdns.info)" | tee -a "$LOG"
curl -sA "Mozilla/5.0" "https://viewdns.info/reversewhois/?q=${ORG_NAME// /+}" 2>/dev/null \
  | grep -oE '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' \
  | sort -u > "$OUT/viewdns_reverse_whois.txt" || true
echo "    found: $(wc -l < $OUT/viewdns_reverse_whois.txt) candidate domains" | tee -a "$LOG"

# 1.3 — ASN lookup for primary IP
echo "[1.3] ASN discovery via Team Cymru" | tee -a "$LOG"
PRIMARY_IP=$(dig +short A "$PRIMARY_DOMAIN" | head -1)
if [ -n "$PRIMARY_IP" ]; then
    echo "    primary IP: $PRIMARY_IP"
    whois -h whois.cymru.com " -v $PRIMARY_IP" 2>/dev/null | tee "$OUT/asn_primary.txt" | tee -a "$LOG"
fi

# 1.4 — Favicon hash (mmh3) for Shodan/Censys cross-search
echo "[1.4] Favicon hash for cross-search" | tee -a "$LOG"
curl -sk "https://$PRIMARY_DOMAIN/favicon.ico" -o "$OUT/favicon.ico" || true
if [ -s "$OUT/favicon.ico" ]; then
    python3 -c "
import mmh3, base64
with open('$OUT/favicon.ico','rb') as f:
    data = base64.encodebytes(f.read())
    print(mmh3.hash(data))
" 2>/dev/null > "$OUT/favicon_hash.txt" || true
    echo "    favicon mmh3: $(cat $OUT/favicon_hash.txt 2>/dev/null)" | tee -a "$LOG"
fi

# 1.5 — Tenant ID lookup (Office365 / Azure)
echo "[1.5] Office365 tenant lookup" | tee -a "$LOG"
curl -s "https://login.microsoftonline.com/getuserrealm.srf?login=any@$PRIMARY_DOMAIN&xml=1" \
    > "$OUT/o365_tenant.xml" 2>/dev/null || true
TENANT=$(grep -oE 'Federated|Managed' "$OUT/o365_tenant.xml" | head -1)
echo "    tenant type: ${TENANT:-not found}" | tee -a "$LOG"

# 1.6 — Common SaaS / vanity domain check
echo "[1.6] Common vanity-domain checks" | tee -a "$LOG"
SLUG="${PRIMARY_DOMAIN%%.*}"
for variant in $SLUG ${SLUG}-corp ${SLUG}-inc ${SLUG}group ${SLUG}global; do
    for tld in com net org io co; do
        host="$variant.$tld"
        if [ "$host" != "$PRIMARY_DOMAIN" ]; then
            ip=$(dig +short A "$host" 2>/dev/null | head -1)
            [ -n "$ip" ] && echo "$host" >> "$OUT/vanity_candidates.txt"
        fi
    done
done
[ -f "$OUT/vanity_candidates.txt" ] && echo "    vanity candidates: $(wc -l < $OUT/vanity_candidates.txt)" | tee -a "$LOG"

# 1.7 — Aggregate seeds
echo "[1.7] Aggregating into seed_roots.txt" | tee -a "$LOG"
cat "$OUT/seed_roots.txt" \
    "$OUT/viewdns_reverse_whois.txt" \
    "$OUT/vanity_candidates.txt" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' | sort -u > "$OUT/seed_roots_master.txt"
mv "$OUT/seed_roots_master.txt" "$OUT/seed_roots.txt"

echo ""
echo "[+] Phase 1 complete. Seeds: $(wc -l < $OUT/seed_roots.txt)" | tee -a "$LOG"
echo "[!] MANUAL REVIEW REQUIRED: $OUT/seed_roots.txt"
echo "    Reverse WHOIS often returns false positives — review and remove unrelated entries."
echo "    Also add: known acquisitions (Crunchbase/Wikipedia), brand-specific domains."
