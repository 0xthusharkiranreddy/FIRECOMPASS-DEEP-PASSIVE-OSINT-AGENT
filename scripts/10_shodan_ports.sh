#!/bin/bash
# Phase 10 — Open port enumeration via Shodan (passive — no active scanning)
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Shodan)
#
# Why: Active port scanning during passive phase is out of scope. Shodan's free
# InternetDB API gives a fast list of ports + known CVEs per IP without sending
# any traffic to the target.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/ips"
RESOLVED="$ENGAGEMENT_DIR/resolved/resolved_ips.txt"
LOG="$ENGAGEMENT_DIR/logs/10_shodan_ports.log"

[ ! -f "$RESOLVED" ] && { echo "Run Phase 7 first"; exit 1; }

echo "[*] Phase 10 — Shodan port discovery" | tee "$LOG"

> "$OUT/shodan_ports.jsonl"
COUNT=0
while read -r IP; do
    [ -z "$IP" ] && continue
    DATA=$(curl -s --max-time 8 "https://internetdb.shodan.io/$IP" 2>/dev/null)
    [ -z "$DATA" ] && continue
    echo "$DATA" | jq -c "{ip:\"$IP\", ports:.ports, hostnames:.hostnames, vulns:.vulns, cpes:.cpes}" >> "$OUT/shodan_ports.jsonl" 2>/dev/null || true
    COUNT=$((COUNT+1))
    [ $((COUNT % 25)) -eq 0 ] && echo "    queried $COUNT IPs..." | tee -a "$LOG"
done < "$RESOLVED"

# Summary
TOTAL=$(wc -l < "$OUT/shodan_ports.jsonl")
WITH_PORTS=$(jq -r 'select(.ports | length > 0) | .ip' "$OUT/shodan_ports.jsonl" | wc -l)
WITH_VULNS=$(jq -r 'select(.vulns | length > 0) | .ip' "$OUT/shodan_ports.jsonl" | wc -l)

echo ""
echo "[+] Phase 10 complete." | tee -a "$LOG"
echo "    IPs queried: $TOTAL"  | tee -a "$LOG"
echo "    With open ports: $WITH_PORTS" | tee -a "$LOG"
echo "    With known CVEs: $WITH_VULNS" | tee -a "$LOG"

# Sensitive port summary
echo "" | tee -a "$LOG"
echo "    Sensitive port distribution:" | tee -a "$LOG"
for port in 21 22 23 25 53 110 135 139 161 389 445 1433 1521 3306 3389 5432 5900 6379 8080 8443 9200 9300 27017; do
    n=$(jq -r ".ports[]?" "$OUT/shodan_ports.jsonl" | grep -cE "^${port}$" 2>/dev/null || echo 0)
    [ "$n" -gt 0 ] && echo "        port $port: $n hosts" | tee -a "$LOG"
done
