#!/bin/bash
# Phase 14 — Email / people OSINT
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Emails)
#
# Why: Names + emails define the phishing simulation scope, identify named admin
# accounts, and surface shared mailboxes worth flagging in the report.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/emails_osint"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/14_email_osint.log"
mkdir -p "$OUT"

echo "[*] Phase 14 — Email / people OSINT" | tee "$LOG"

# 14.1 — theHarvester
if command -v theHarvester &> /dev/null; then
    while read -r ROOT; do
        echo "    [+] theHarvester: $ROOT" | tee -a "$LOG"
        theHarvester -d "$ROOT" -b crtsh,bing,duckduckgo,otx,certspotter -l 500 \
            -f "$OUT/theharvester_${ROOT}" 2>/dev/null > "$OUT/theharvester_${ROOT}.log" || true
    done < "$SEEDS"
fi

# 14.2 — Hunter.io (requires API key)
if [ -n "$HUNTER_API_KEY" ]; then
    while read -r ROOT; do
        echo "    [+] hunter.io: $ROOT" | tee -a "$LOG"
        curl -s "https://api.hunter.io/v2/domain-search?domain=$ROOT&api_key=$HUNTER_API_KEY&limit=100" \
            > "$OUT/hunter_${ROOT}.json" 2>/dev/null || true
    done < "$SEEDS"
else
    echo "    [-] HUNTER_API_KEY not set — skipping" | tee -a "$LOG"
fi

# 14.3 — Email pattern inference
echo "    [+] inferring email format from collected emails" | tee -a "$LOG"
> "$OUT/all_emails.txt"
for f in "$OUT"/*.json "$OUT"/theharvester_*.xml; do
    [ -f "$f" ] || continue
    grep -oiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$f" 2>/dev/null >> "$OUT/all_emails.txt" || true
done

# Filter to in-scope domains
> "$OUT/in_scope_emails.txt"
while read -r ROOT; do
    grep -iE "@${ROOT//./\\.}$" "$OUT/all_emails.txt" 2>/dev/null >> "$OUT/in_scope_emails.txt"
done < "$SEEDS"
sort -u "$OUT/in_scope_emails.txt" -o "$OUT/in_scope_emails.txt"

# Flag named admin accounts and shared mailboxes
echo "    [+] flagging admin / shared mailbox patterns" | tee -a "$LOG"
grep -iE '^(admin|root|administrator|sysadmin|netadmin|dba|it|security|soc|noc|helpdesk|support|info|sales|hr|payroll|finance|legal|noreply|no-reply|donotreply|webmaster|hostmaster|postmaster|abuse)' \
    "$OUT/in_scope_emails.txt" > "$OUT/sensitive_mailboxes.txt" 2>/dev/null || true

echo ""
echo "[+] Phase 14 complete." | tee -a "$LOG"
echo "    Total in-scope emails: $(wc -l < $OUT/in_scope_emails.txt)" | tee -a "$LOG"
echo "    Sensitive mailboxes flagged: $(wc -l < $OUT/sensitive_mailboxes.txt)" | tee -a "$LOG"
