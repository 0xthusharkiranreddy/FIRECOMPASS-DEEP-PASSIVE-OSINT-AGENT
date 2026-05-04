#!/bin/bash
# Phase 6 — Shodan / Censys hostname discovery
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Shodan)
#
# Why: Shodan's crawler records every SSL cert and HTTP Host header it sees,
# regardless of CT logs. Free InternetDB (no key) gives a fast hostname dump per
# IP. With a paid key, can search by SSL cert subject CN to enumerate all hosts
# under a wildcard cert.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/subdomains"
IPS_OUT="$ENGAGEMENT_DIR/ips"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/06_shodan_lookup.log"
mkdir -p "$IPS_OUT"

echo "[*] Phase 6 — Shodan / Censys passive lookup" | tee "$LOG"

# 6.1 — Shodan InternetDB on every resolved IP from Phase 7 (or resolve seeds inline)
RESOLVED_IPS="$ENGAGEMENT_DIR/resolved/resolved_ips.txt"
if [ ! -f "$RESOLVED_IPS" ]; then
    echo "    Phase 7 not yet run — resolving seed IPs inline" | tee -a "$LOG"
    while read -r ROOT; do
        dig +short A "$ROOT" 2>/dev/null
        dig +short A "www.$ROOT" 2>/dev/null
    done < "$SEEDS" | grep -E '^[0-9]' | sort -u > "$IPS_OUT/seed_ips.txt"
    RESOLVED_IPS="$IPS_OUT/seed_ips.txt"
fi

# Query Shodan InternetDB (free, no API key)
SHODAN_HOSTNAMES="$OUT/shodan_hostnames.txt"
> "$SHODAN_HOSTNAMES"
COUNT=0

while read -r IP; do
    [ -z "$IP" ] && continue
    COUNT=$((COUNT+1))
    DATA=$(curl -s --max-time 8 "https://internetdb.shodan.io/$IP" 2>/dev/null)
    [ -z "$DATA" ] && continue
    echo "$DATA" | jq -r '.hostnames[]?' 2>/dev/null >> "$SHODAN_HOSTNAMES" || true
    [ $((COUNT % 20)) -eq 0 ] && echo "    queried $COUNT IPs..." | tee -a "$LOG"
done < "$RESOLVED_IPS"

# Filter to in-scope domains
> "$OUT/shodan_filtered.txt"
while read -r ROOT; do
    grep -E "\.${ROOT//./\\.}$" "$SHODAN_HOSTNAMES" 2>/dev/null >> "$OUT/shodan_filtered.txt"
done < "$SEEDS"
sort -u "$OUT/shodan_filtered.txt" -o "$OUT/shodan_filtered.txt"

# 6.2 — Shodan API (if key set)
if [ -n "$SHODAN_API_KEY" ]; then
    echo "    [+] using Shodan API key" | tee -a "$LOG"
    while read -r ROOT; do
        curl -s --max-time 30 "https://api.shodan.io/shodan/host/search?key=$SHODAN_API_KEY&query=ssl.cert.subject.cn:*.${ROOT}&limit=100" 2>/dev/null \
          | jq -r '.matches[].hostnames[]?' 2>/dev/null \
          | grep -E "\.${ROOT//./\\.}$" >> "$OUT/shodan_filtered.txt" || true
    done < "$SEEDS"
    sort -u "$OUT/shodan_filtered.txt" -o "$OUT/shodan_filtered.txt"
fi

NEW=$(comm -23 "$OUT/shodan_filtered.txt" "$OUT/all_master.txt" 2>/dev/null | wc -l)
echo ""
echo "[+] Phase 6 complete." | tee -a "$LOG"
echo "    Shodan-found hostnames: $(wc -l < $OUT/shodan_filtered.txt)" | tee -a "$LOG"
echo "    NEW: $NEW" | tee -a "$LOG"
sort -u "$OUT/all_master.txt" "$OUT/shodan_filtered.txt" -o "$OUT/all_master.txt"
