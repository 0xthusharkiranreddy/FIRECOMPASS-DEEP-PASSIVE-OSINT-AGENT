#!/bin/bash
# Phase 9 — IP / ASN / netblock discovery
# Reference: PAT /Methodology and Resources/Network Discovery.md (§ ASN)
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ ASN)
#
# Why: Once you have IPs, the ASN reveals all netblocks owned by the same org.
# This finds additional client-controlled IP space that hosts assets not yet
# discovered (e.g. APIs on other IPs, dev environments).

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/ips"
LOG="$ENGAGEMENT_DIR/logs/09_asn_netblock.log"
RESOLVED="$ENGAGEMENT_DIR/resolved/resolved_ips.txt"
mkdir -p "$OUT"

[ ! -f "$RESOLVED" ] && { echo "Run Phase 7 first"; exit 1; }

echo "[*] Phase 9 — ASN / netblock discovery" | tee "$LOG"

# 9.1 — Bulk ASN lookup via Team Cymru
echo "[9.1] Bulk ASN via Team Cymru" | tee -a "$LOG"
{
    echo "begin"
    echo "verbose"
    cat "$RESOLVED"
    echo "end"
} | nc -w 5 whois.cymru.com 43 > "$OUT/asn_bulk.txt" 2>/dev/null || true

# Parse: AS | IP | BGP_Prefix | CC | Registry | Allocated | AS_Name
echo "    parsing..."
awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}' "$OUT/asn_bulk.txt" | sort -u > "$OUT/asns.txt"

# 9.2 — Get netblocks per ASN
echo "[9.2] Netblocks per ASN" | tee -a "$LOG"
> "$OUT/netblocks.txt"
while read -r ASN; do
    [ -z "$ASN" ] || [ "$ASN" = "AS" ] && continue
    # Use bgp.he.net or whois.radb.net
    whois -h whois.radb.net -- "-i origin AS${ASN}" 2>/dev/null | grep -oE 'route:[ \t]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | awk '{print $2}' | sort -u >> "$OUT/netblocks.txt" || true
done < "$OUT/asns.txt"
sort -u "$OUT/netblocks.txt" -o "$OUT/netblocks.txt"

# Filter out cloud provider ASNs (these are not owned by client)
echo "[9.3] Flagging cloud ASNs (AWS, Azure, GCP, CloudFlare)" | tee -a "$LOG"
grep -iE 'amazon|aws|microsoft|azure|google|cloud|cloudflare|akamai|fastly' "$OUT/asn_bulk.txt" > "$OUT/cloud_asns.txt" 2>/dev/null || true

echo ""
echo "[+] Phase 9 complete." | tee -a "$LOG"
echo "    ASNs: $(wc -l < $OUT/asns.txt)" | tee -a "$LOG"
echo "    Netblocks: $(wc -l < $OUT/netblocks.txt)" | tee -a "$LOG"
echo "    Cloud-provider IPs (likely tenant): $(wc -l < $OUT/cloud_asns.txt)" | tee -a "$LOG"
