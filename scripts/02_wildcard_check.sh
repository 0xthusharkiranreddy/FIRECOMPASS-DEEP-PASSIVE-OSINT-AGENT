#!/bin/bash
# Phase 2 — Wildcard Certificate Detection (CRITICAL — never skip)
# Reference: Internal lesson (LESSONS_LEARNED.md #1) — wildcard cert blindness
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md
#
# Why: CT-log-based passive subdomain tools (subfinder, amass, crt.sh, certspotter)
# only see ONE entry for a wildcard cert. Individual subdomains under a wildcard
# cert are INVISIBLE to passive enumeration. This is the #1 cause of missed
# assets in real engagements. Without this check, recon is unreliable on any
# organisation that uses wildcard certs (most do).

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/seeds"
LOG="$ENGAGEMENT_DIR/logs/02_wildcard_check.log"
WILDCARD_LIST="$OUT/wildcard_roots.txt"
> "$WILDCARD_LIST"

echo "[*] Phase 2 — Wildcard Certificate Detection" | tee "$LOG"

while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    echo "[2.x] Checking $ROOT" | tee -a "$LOG"

    # Get the cert SANs
    SANS=$(timeout 8 bash -c "echo | openssl s_client -connect ${ROOT}:443 -servername ${ROOT} 2>/dev/null" \
           | openssl x509 -noout -text 2>/dev/null \
           | grep -oP 'DNS:[^,]+' | sort -u | tr '\n' ' ')

    if [ -z "$SANS" ]; then
        echo "    no SSL on 443 (skip)" | tee -a "$LOG"
        continue
    fi

    echo "    SANs: $SANS" | tee -a "$LOG"

    if echo "$SANS" | grep -qE "DNS:\*\.${ROOT//./\\.}"; then
        echo "    [!] WILDCARD CERT DETECTED — pattern permutation required in Phase 8"
        echo "$ROOT" >> "$WILDCARD_LIST"
    fi

    # Also check for wildcard DNS (random name resolves)
    RANDOM_NAME="xyzdoesnotexist$RANDOM.$ROOT"
    if dig +short A "$RANDOM_NAME" 2>/dev/null | grep -qE '^[0-9]'; then
        echo "    [!] WILDCARD DNS detected — all enumeration must filter wildcard IPs"
        echo "$ROOT" >> "$WILDCARD_LIST"
    fi
done < "$OUT/seed_roots.txt"

sort -u "$WILDCARD_LIST" -o "$WILDCARD_LIST"

echo ""
echo "[+] Phase 2 complete." | tee -a "$LOG"
echo "    Wildcard-flagged roots: $(wc -l < $WILDCARD_LIST)" | tee -a "$LOG"
[ -s "$WILDCARD_LIST" ] && cat "$WILDCARD_LIST" | tee -a "$LOG"
