#!/bin/bash
# Phase 12.5 — Beyond-GitHub code & paste search
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Source code leaks)
# Reference: PAT /Methodology and Resources/Passwords and Secrets.md
#
# Why: Source code containing org secrets doesn't only land on GitHub.
# Developers push to GitLab.com, Bitbucket.org, Codeberg.org, Gitea instances,
# and SourceForge. Credentials also leak to Pastebin, Gist, and forum posts.
# Search techniques here:
#   1. GitLab.com — public project search via search API (no key needed)
#   2. Bitbucket.org — repository search via Atlassian REST API (public)
#   3. Codeberg.org — Gitea REST API (public)
#   4. Pastebin search — via Google dork (site:pastebin.com)
#   5. Gist search — via Google dork (site:gist.github.com)
#   6. SourceForge — via search URL
#
# All requests are read-only to public APIs / Google dorking.
# No authentication required for basic searches.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/github"      # re-use same github/ dir for consolidated code leaks
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/12b_beyond_github_code.log"
mkdir -p "$OUT"

[ ! -f "$SEEDS" ] && { echo "Run Phase 0 first"; exit 1; }

# Extract base org keywords from seed roots  (e.g. acme.com → acme)
ORG_KEYWORDS=$(awk -F'.' '{print $1}' "$SEEDS" | sort -u | head -5)
PRIMARY_DOMAIN=$(head -1 "$SEEDS")

echo "[*] Phase 12.5 — Beyond-GitHub code & paste search" | tee "$LOG"
log_phase_start "12.5" "Beyond-GitHub Code & Paste Search (GitLab/Bitbucket/Codeberg/Pastebin)"
log_hypothesis \
    "Developers at any org push code to multiple platforms; credentials leak to pastes; npm/pypi packages may expose internal naming" \
    "Search GitLab.com, Bitbucket.org, Codeberg.org public APIs + generate Google/Bing dorks for pastebin/gist; search npm and pypi for org keywords" \
    "If zero results across all platforms, either org is GitHub-only or uses on-prem git — neither is a gap, but should be noted"
echo "    org keywords: $ORG_KEYWORDS" | tee -a "$LOG"

echo -e "source\turl\ttitle\tmatched_keyword" > "$OUT/beyond_github_hits.tsv"

# ── GitLab.com ──────────────────────────────────────────────────────────────
echo "  [*] GitLab.com search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    # GitLab public project search — returns JSON with namespace/name
    GL_RESP=$(curl -sk --max-time 15 \
        "https://gitlab.com/api/v4/projects?search=${KW}&visibility=public&order_by=last_activity_at&per_page=20" \
        2>/dev/null)
    if echo "$GL_RESP" | grep -q '"id"'; then
        echo "$GL_RESP" | grep -oP '"web_url"\s*:\s*"[^"]+"' | sed 's/"web_url"\s*:\s*"//' | tr -d '"' | \
        while read -r GL_URL; do
            echo -e "GitLab\t${GL_URL}\t${KW} project\t${KW}" >> "$OUT/beyond_github_hits.tsv"
            echo "    [GitLab] $GL_URL" | tee -a "$LOG"
        done
    fi

    # GitLab code search (public blobs containing the domain)
    GL_CODE=$(curl -sk --max-time 15 \
        "https://gitlab.com/api/v4/search?scope=blobs&search=${PRIMARY_DOMAIN}&per_page=10" \
        2>/dev/null)
    if echo "$GL_CODE" | grep -q '"project_id"'; then
        echo "$GL_CODE" | grep -oP '"web_url"\s*:\s*"[^"]+"' | sed 's/"web_url"\s*:\s*"//' | tr -d '"' | \
        while read -r GL_URL; do
            echo -e "GitLab-code\t${GL_URL}\tcode mention\t${PRIMARY_DOMAIN}" >> "$OUT/beyond_github_hits.tsv"
            echo "    [GitLab-code] $GL_URL" | tee -a "$LOG"
        done
    fi
done

# ── Bitbucket.org ────────────────────────────────────────────────────────────
echo "  [*] Bitbucket.org search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    BB_RESP=$(curl -sk --max-time 15 \
        "https://api.bitbucket.org/2.0/repositories?q=name+%7E+%22${KW}%22&pagelen=20" \
        2>/dev/null)
    if echo "$BB_RESP" | grep -q '"full_name"'; then
        echo "$BB_RESP" | grep -oP '"html"\s*:\s*\{[^}]*"href"\s*:\s*"[^"]+"' | \
            grep -oP '"href"\s*:\s*"[^"]+"' | sed 's/"href"\s*:\s*"//' | tr -d '"' | \
        while read -r BB_URL; do
            echo -e "Bitbucket\t${BB_URL}\t${KW} repo\t${KW}" >> "$OUT/beyond_github_hits.tsv"
            echo "    [Bitbucket] $BB_URL" | tee -a "$LOG"
        done
    fi
done

# ── Codeberg.org (Gitea API) ─────────────────────────────────────────────────
echo "  [*] Codeberg.org search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    CB_RESP=$(curl -sk --max-time 15 \
        "https://codeberg.org/api/v1/repos/search?q=${KW}&limit=20&token=" \
        2>/dev/null)
    if echo "$CB_RESP" | grep -q '"full_name"'; then
        echo "$CB_RESP" | grep -oP '"html_url"\s*:\s*"https://codeberg\.org/[^"]+"' | \
            sed 's/"html_url"\s*:\s*"//' | tr -d '"' | \
        while read -r CB_URL; do
            echo -e "Codeberg\t${CB_URL}\t${KW} repo\t${KW}" >> "$OUT/beyond_github_hits.tsv"
            echo "    [Codeberg] $CB_URL" | tee -a "$LOG"
        done
    fi
done

# ── SourceForge ──────────────────────────────────────────────────────────────
echo "  [*] SourceForge search" | tee -a "$LOG"
for KW in $ORG_KEYWORDS; do
    SF_RESP=$(curl -sk --max-time 15 \
        "https://sourceforge.net/directory/?q=${KW}" 2>/dev/null)
    if echo "$SF_RESP" | grep -q 'sourceforge.net/p/'; then
        echo "$SF_RESP" | grep -oP 'href="https://sourceforge\.net/p/[^"]+"' | \
            sed 's/href="//' | tr -d '"' | sort -u | \
        while read -r SF_URL; do
            echo -e "SourceForge\t${SF_URL}\t${KW} project\t${KW}" >> "$OUT/beyond_github_hits.tsv"
            echo "    [SourceForge] $SF_URL" | tee -a "$LOG"
        done
    fi
done

# ── Google Dork: Pastebin + Gist ─────────────────────────────────────────────
# Note: Google dorks here generate search-engine URLs for analyst review —
# we cannot automate Google search, but we generate the exact dork URLs
# to open manually or via a Bing/DuckDuckGo scraper.
echo "  [*] Generating paste/gist dork URLs for analyst review" | tee -a "$LOG"

DORK_FILE="$OUT/paste_dork_urls.txt"
> "$DORK_FILE"

for KW in $ORG_KEYWORDS; do
    echo "# keyword: $KW" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:pastebin.com+%22${KW}%22" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:pastebin.com+%22${PRIMARY_DOMAIN}%22" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:gist.github.com+%22${KW}%22" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:gist.github.com+%22${PRIMARY_DOMAIN}%22" >> "$DORK_FILE"
    echo "https://www.bing.com/search?q=site:pastebin.com+%22${KW}%22" >> "$DORK_FILE"
    echo "https://www.bing.com/search?q=site:pastebin.com+%22${PRIMARY_DOMAIN}%22" >> "$DORK_FILE"
    # Developer forums
    echo "https://www.google.com/search?q=site:stackoverflow.com+%22${PRIMARY_DOMAIN}%22+password" >> "$DORK_FILE"
    echo "https://www.google.com/search?q=site:reddit.com+%22${PRIMARY_DOMAIN}%22+password" >> "$DORK_FILE"
    echo "" >> "$DORK_FILE"
done

DORK_COUNT=$(grep -c '^https://' "$DORK_FILE" 2>/dev/null || echo 0)
echo "    paste/gist dork URLs generated: $DORK_COUNT" | tee -a "$LOG"
echo "    → manual review: $DORK_FILE" | tee -a "$LOG"

# ── Recon-ng style: npmjs / pypi / rubygems (internal package name leaks) ────
echo "  [*] Package registry search (npm/pypi)" | tee -a "$LOG"
PKG_FILE="$OUT/package_registry_hits.txt"
> "$PKG_FILE"
for KW in $ORG_KEYWORDS; do
    NPM=$(curl -sk --max-time 10 "https://registry.npmjs.org/-/v1/search?text=${KW}&size=5" 2>/dev/null)
    if echo "$NPM" | grep -q '"name"'; then
        echo "$NPM" | grep -oP '"name"\s*:\s*"[^"]+"' | head -5 | sed "s/^/[npm] /" >> "$PKG_FILE"
    fi
    PYPI=$(curl -sk --max-time 10 "https://pypi.org/pypi/${KW}/json" 2>/dev/null)
    if echo "$PYPI" | grep -q '"name"'; then
        PKG_NAME=$(echo "$PYPI" | grep -oP '"name"\s*:\s*"[^"]+"' | head -1)
        echo "[pypi] $PKG_NAME" >> "$PKG_FILE"
    fi
done

# Summary
HITS=$(($(wc -l < "$OUT/beyond_github_hits.tsv") - 1))
echo "" | tee -a "$LOG"
echo "[+] Phase 12.5 complete." | tee -a "$LOG"
echo "    Code platform hits:    $HITS" | tee -a "$LOG"
echo "    Paste dork URLs:       $DORK_COUNT (manual review needed)" | tee -a "$LOG"
echo "    Package registry hits: $(wc -l < $PKG_FILE 2>/dev/null || echo 0)" | tee -a "$LOG"
[ "$HITS" -gt 0 ] && echo "    [!] Review beyond_github_hits.tsv for exposed repositories" | tee -a "$LOG"

log_stats "Phase 12.5 results" \
    "Code platform hits:${HITS}" \
    "Paste dork URLs generated:${DORK_COUNT}" \
    "Package registry hits:$(wc -l < $OUT/package_registry_hits.txt 2>/dev/null || echo 0)"
[ "$HITS" -gt 0 ] && log_finding NOTABLE "Code leaks: $HITS public repositories found on non-GitHub platforms — manual review required"
log_phase_end "12.5" "Beyond-GitHub search complete. $HITS hits. Paste dorks in github/paste_dork_urls.txt — open manually to complete this phase."
