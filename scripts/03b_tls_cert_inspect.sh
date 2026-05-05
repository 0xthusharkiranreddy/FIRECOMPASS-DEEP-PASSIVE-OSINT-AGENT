#!/bin/bash
# Phase 3.5 — TLS certificate deep inspection
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Certificate Transparency / SSL Certificates)
#
# Why: Beyond just "wildcard or not" (Phase 2), the cert reveals:
#   - All SANs explicitly listed (additional in-scope subdomains)
#   - Issuer (e.g. internal CA hints at private PKI; Let's Encrypt suggests automation)
#   - Subject org info (cross-validates org identity)
#   - Cert expiry (near-expiry on prod = ops-quality signal)
#   - Cert transparency log entries via CT chain
#
# This is passive — only fetching certs from public TLS handshake on port 443.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/tls"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
RESOLVED="$ENGAGEMENT_DIR/resolved/resolved_hosts.txt"
LOG="$ENGAGEMENT_DIR/logs/03b_tls_cert_inspect.log"
mkdir -p "$OUT"

echo "[*] Phase 3.5 — TLS certificate deep inspection" | tee "$LOG"
log_phase_start "3.5" "TLS Certificate Deep Inspection"
log_hypothesis \
    "Each root domain and resolved host has a TLS cert that may list additional SANs not captured by CT-log tools" \
    "Fetch live TLS handshake on port 443 per host, extract full SAN list, check issuer and expiry" \
    "If all SAN counts are 1 and match the hostname exactly, certs are per-host — no new subdomain signal"

# Combine roots + resolved hosts (cap to avoid overload)
HOST_LIST="$OUT/inspect_targets.txt"
{ cat "$SEEDS"; [ -f "$RESOLVED" ] && head -100 "$RESOLVED"; } | sort -u > "$HOST_LIST"
TOTAL=$(wc -l < "$HOST_LIST")
echo "    targets: $TOTAL hosts" | tee -a "$LOG"

> "$OUT/cert_summary.tsv"
echo -e "host\tissuer\tsubject_org\tsubject_cn\tnot_after\tdays_to_expiry\tsan_count\tsans_sample" >> "$OUT/cert_summary.tsv"

> "$OUT/all_sans.txt"

while read -r HOST; do
    [ -z "$HOST" ] && continue
    CERT=$(timeout 8 bash -c "echo | openssl s_client -connect ${HOST}:443 -servername ${HOST} 2>/dev/null" \
           | openssl x509 -noout -text 2>/dev/null)
    [ -z "$CERT" ] && continue

    ISSUER=$(echo "$CERT" | grep -oP 'Issuer:.*' | head -1 | sed 's/Issuer:\s*//' | head -c 100)
    SUB_O=$(echo "$CERT" | grep -oP 'Subject:.*O\s*=\s*[^,]+' | head -1 | sed 's/.*O\s*=\s*//' | head -c 60)
    SUB_CN=$(echo "$CERT" | grep -oP 'CN\s*=\s*[^,]+' | tail -1 | sed 's/CN\s*=\s*//' | head -c 80)
    NOT_AFTER=$(echo "$CERT" | grep -oP 'Not After\s*:\s*.*' | sed 's/Not After\s*:\s*//')
    SANS=$(echo "$CERT" | grep -oP 'DNS:[^,]+' | sed 's/DNS://g' | tr '\n' ',' | sed 's/,$//')
    SAN_COUNT=$(echo "$SANS" | tr ',' '\n' | grep -c .)

    # Days to expiry
    DAYS=""
    if [ -n "$NOT_AFTER" ]; then
        EXP_TS=$(date -d "$NOT_AFTER" +%s 2>/dev/null)
        NOW_TS=$(date +%s)
        [ -n "$EXP_TS" ] && DAYS=$(( (EXP_TS - NOW_TS) / 86400 ))
    fi

    SAN_SAMPLE=$(echo "$SANS" | cut -c1-100)
    echo -e "${HOST}\t${ISSUER}\t${SUB_O}\t${SUB_CN}\t${NOT_AFTER}\t${DAYS}\t${SAN_COUNT}\t${SAN_SAMPLE}" >> "$OUT/cert_summary.tsv"

    # Aggregate every SAN — a goldmine of new subdomains
    echo "$SANS" | tr ',' '\n' | grep -E '\.[a-z]{2,}$' >> "$OUT/all_sans.txt"

    # Flag near-expiry (<14 days) and internal CAs
    if [ -n "$DAYS" ] && [ "$DAYS" -lt 14 ]; then
        echo "[!] near-expiry $HOST → $DAYS days" | tee -a "$LOG"
    fi
    if echo "$ISSUER" | grep -qiE 'internal|private|corporate|self.?signed'; then
        echo "[!] internal CA $HOST → $ISSUER" | tee -a "$LOG"
    fi
done < "$HOST_LIST"

# Dedupe and lowercase SANs; cross-check against existing master subdomain list
sort -u "$OUT/all_sans.txt" | tr '[:upper:]' '[:lower:]' | grep -v '^\*' > "$OUT/all_sans_unique.txt"

# Identify new subdomains found via SAN inspection (not in master)
MASTER="$ENGAGEMENT_DIR/subdomains/all_master.txt"
if [ -f "$MASTER" ]; then
    comm -23 "$OUT/all_sans_unique.txt" <(sort "$MASTER") > "$OUT/new_from_sans.txt"
    NEW=$(wc -l < "$OUT/new_from_sans.txt")
    echo "    NEW subdomains discovered via SAN extraction: $NEW" | tee -a "$LOG"
    [ "$NEW" -gt 0 ] && sort -u "$MASTER" "$OUT/new_from_sans.txt" -o "$MASTER"
fi

CERTS_INSPECTED=$(($(wc -l < "$OUT/cert_summary.tsv") - 1))
SANS_UNIQUE=$(wc -l < "$OUT/all_sans_unique.txt")
NEW_SUBS_COUNT=$([ -f "$OUT/new_from_sans.txt" ] && wc -l < "$OUT/new_from_sans.txt" || echo 0)

echo ""
echo "[+] Phase 3.5 complete." | tee -a "$LOG"
echo "    Certs inspected:        $CERTS_INSPECTED" | tee -a "$LOG"
echo "    Unique SANs aggregated: $SANS_UNIQUE" | tee -a "$LOG"

log_stats "Phase 3.5 results" \
    "Certs inspected:${CERTS_INSPECTED}" \
    "Unique SANs:${SANS_UNIQUE}" \
    "New subdomains from SANs:${NEW_SUBS_COUNT}"
[ "$NEW_SUBS_COUNT" -gt 0 ] && log_finding NOTABLE "Phase 3.5: $NEW_SUBS_COUNT new subdomains discovered via SAN extraction (not in CT-log results)"
log_phase_end "3.5" "TLS inspection complete. $CERTS_INSPECTED certs, $SANS_UNIQUE SANs, $NEW_SUBS_COUNT new subdomains merged into all_master.txt."
