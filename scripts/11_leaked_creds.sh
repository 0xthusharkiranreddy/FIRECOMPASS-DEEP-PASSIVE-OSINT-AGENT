#!/bin/bash
# Phase 11 — Leaked credential discovery
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/database-leaks.md
#
# Why: Public breach data often contains employee creds reusable against the
# client's external apps. This is the #1 actionable finding clients care about
# because it is immediately exploitable and demonstrates real risk.
#
# Sources used:
#   - HaveIBeenPwned (domain search requires API key, breach search per email is free)
#   - DeHashed       (API key required)
#   - IntelX         (registration required for full results)
#   - Public paste-site dorks (Google search)

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/creds"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/11_leaked_creds.log"
mkdir -p "$OUT"

echo "[*] Phase 11 — Leaked credential discovery" | tee "$LOG"

# 11.1 — HaveIBeenPwned domain search (requires API key)
if [ -n "$HIBP_API_KEY" ]; then
    while read -r ROOT; do
        echo "    [+] HIBP domain search: $ROOT" | tee -a "$LOG"
        curl -s -H "hibp-api-key: $HIBP_API_KEY" -A "FireCompass POC" \
            "https://haveibeenpwned.com/api/v3/breacheddomain/$ROOT" \
            > "$OUT/hibp_${ROOT}.json" 2>/dev/null || true
    done < "$SEEDS"
else
    echo "    [-] HIBP_API_KEY not set — skipping HIBP domain search" | tee -a "$LOG"
fi

# 11.2 — DeHashed (free tier limited)
if [ -n "$DEHASHED_API_KEY" ] && [ -n "$DEHASHED_USERNAME" ]; then
    while read -r ROOT; do
        echo "    [+] DeHashed: $ROOT" | tee -a "$LOG"
        curl -s -u "$DEHASHED_USERNAME:$DEHASHED_API_KEY" \
            "https://api.dehashed.com/search?query=domain:$ROOT&size=100" \
            -H "Accept: application/json" > "$OUT/dehashed_${ROOT}.json" 2>/dev/null || true
    done < "$SEEDS"
else
    echo "    [-] DEHASHED creds not set — skipping" | tee -a "$LOG"
fi

# 11.3 — IntelX (requires registration)
if [ -n "$INTELX_API_KEY" ]; then
    while read -r ROOT; do
        echo "    [+] IntelX: $ROOT" | tee -a "$LOG"
        curl -s -H "x-key: $INTELX_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"term\":\"$ROOT\",\"maxresults\":100,\"media\":0,\"sort\":4,\"terminate\":[]}" \
            "https://2.intelx.io/intelligent/search" > "$OUT/intelx_${ROOT}.json" 2>/dev/null || true
    done < "$SEEDS"
else
    echo "    [-] INTELX_API_KEY not set — skipping" | tee -a "$LOG"
fi

# 11.4 — Manual paste-site dork URLs (analyst opens these in browser)
PASTE_DORKS="$OUT/paste_dork_urls.txt"
> "$PASTE_DORKS"
while read -r ROOT; do
    cat >> "$PASTE_DORKS" <<EOF
# === $ROOT ===
https://www.google.com/search?q=intext%3A%22%40${ROOT}%22+%22password%22
https://www.google.com/search?q=intext%3A%22%40${ROOT}%22+inurl%3Apastebin
https://www.google.com/search?q=intext%3A%22%40${ROOT}%22+inurl%3Aghostbin
https://www.google.com/search?q=intext%3A%22%40${ROOT}%22+inurl%3Atrumpet
https://www.google.com/search?q=intext%3A%22%40${ROOT}%22+inurl%3Aanonfile
https://www.google.com/search?q=intext%3A%22${ROOT%.*}%22+%22password%22+%22%40${ROOT}%22
EOF
done < "$SEEDS"

# 11.5 — local breach DB scan (if you have one)
if [ -d /opt/breach-data ]; then
    echo "[+] Scanning local breach DB at /opt/breach-data" | tee -a "$LOG"
    while read -r ROOT; do
        grep -hr "@${ROOT}" /opt/breach-data 2>/dev/null > "$OUT/local_breach_${ROOT}.txt" || true
    done < "$SEEDS"
fi

echo ""
echo "[+] Phase 11 complete." | tee -a "$LOG"
echo "[!] MANUAL STEPS:"
echo "    1. Open URLs in $PASTE_DORKS in a browser to catch paste-site leaks"
echo "    2. Review JSON outputs in $OUT/ for credential count + earliest/latest breach dates"
echo "    3. Flag named admin accounts (admin@, root@, it@) and shared mailboxes (support@, info@)"
