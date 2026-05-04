#!/bin/bash
# Phase 12 — GitHub / pastebin / public source code leaks
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/github-leaked-secrets.md
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/wide-source-code-search.md
# Reference: PAT      /Methodology and Resources/Source Code Management.md
#
# Why: Developers leak secrets — API keys, passwords, internal hostnames — into
# public repos. Even if not credentials, internal hostnames in JS/config files
# are a passive recon goldmine that bypass wildcard cert blindness.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/github"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/12_github_leaks.log"
mkdir -p "$OUT"

echo "[*] Phase 12 — GitHub / source leaks" | tee "$LOG"

# 12.1 — GitHub code search (requires PAT for higher rate)
if [ -n "$GITHUB_TOKEN" ]; then
    while read -r ROOT; do
        echo "    [+] github code search: $ROOT" | tee -a "$LOG"
        for query in "$ROOT" "${ROOT}+password" "${ROOT}+api_key" "${ROOT}+secret"; do
            qf=$(echo "$query" | tr '+' '_' | tr -d ':"')
            curl -s -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/search/code?q=${query}&per_page=50" 2>/dev/null \
              | jq -r '.items[]? | "\(.html_url)\t\(.path)"' >> "$OUT/github_${ROOT}_${qf}.tsv" 2>/dev/null || true
            sleep 6  # github search rate limit
        done
    done < "$SEEDS"
else
    echo "    [-] GITHUB_TOKEN not set — skipping API search; use trufflehog only" | tee -a "$LOG"
fi

# 12.2 — trufflehog org-wide scan
if command -v trufflehog &> /dev/null; then
    while read -r ROOT; do
        ORG_GUESS="${ROOT%.*}"  # acme.com -> acme
        echo "    [+] trufflehog github org=$ORG_GUESS" | tee -a "$LOG"
        trufflehog github --org="$ORG_GUESS" --no-update --json --no-verification 2>/dev/null \
            > "$OUT/trufflehog_${ORG_GUESS}.json" || true
    done < "$SEEDS"
fi

# 12.3 — Manual dork URLs for browser
DORKS="$OUT/github_dork_urls.txt"
> "$DORKS"
while read -r ROOT; do
    cat >> "$DORKS" <<EOF
# === $ROOT ===
https://github.com/search?q=${ROOT}&type=code
https://github.com/search?q=%22${ROOT}%22+password&type=code
https://github.com/search?q=%22${ROOT}%22+api_key&type=code
https://github.com/search?q=%22${ROOT}%22+aws_secret&type=code
https://github.com/search?q=%22${ROOT}%22+filename%3A.env&type=code
https://gitlab.com/search?search=${ROOT}
https://bitbucket.org/search?search=${ROOT}
EOF
done < "$SEEDS"

# 12.4 — Internal-hostname extraction from any retrieved repos
echo "    [+] extracting hostname references from github results" | tee -a "$LOG"
> "$OUT/github_hostnames.txt"
for f in "$OUT"/*.tsv "$OUT"/*.json; do
    [ -f "$f" ] || continue
    grep -oE '[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}' "$f" 2>/dev/null >> "$OUT/github_hostnames.txt" || true
done

# Filter to in-scope domains
> "$OUT/github_filtered.txt"
while read -r ROOT; do
    grep -E "\.${ROOT//./\\.}$" "$OUT/github_hostnames.txt" 2>/dev/null >> "$OUT/github_filtered.txt"
done < "$SEEDS"
sort -u "$OUT/github_filtered.txt" -o "$OUT/github_filtered.txt"

NEW=$(comm -23 "$OUT/github_filtered.txt" "$ENGAGEMENT_DIR/subdomains/all_master.txt" 2>/dev/null | wc -l)
echo ""
echo "[+] Phase 12 complete." | tee -a "$LOG"
echo "    GitHub-found in-scope hostnames: $(wc -l < $OUT/github_filtered.txt)" | tee -a "$LOG"
echo "    NEW: $NEW" | tee -a "$LOG"

[ -n "$NEW" ] && [ "$NEW" -gt 0 ] && \
    sort -u "$ENGAGEMENT_DIR/subdomains/all_master.txt" "$OUT/github_filtered.txt" \
        -o "$ENGAGEMENT_DIR/subdomains/all_master.txt"
