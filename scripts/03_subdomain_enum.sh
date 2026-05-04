#!/bin/bash
# Phase 3 — Multi-source passive subdomain enumeration
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Subdomains)
# Reference: PAT      /Methodology and Resources/Network Discovery.md (§ DNS)
#
# Why: No single source has full coverage. crt.sh has CT logs. urlscan has real
# browser captures. RapidDNS has historical DNS. OTX has threat intel. Aggregating
# 10+ sources maximises the chance of finding a given subdomain. Cross-checking
# also reveals gaps (e.g. urlscan finds it but crt.sh doesn't = no cert issued).

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

OUT="$ENGAGEMENT_DIR/subdomains"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
LOG="$ENGAGEMENT_DIR/logs/03_subdomain_enum.log"
mkdir -p "$OUT"

echo "[*] Phase 3 — Multi-source subdomain enumeration" | tee "$LOG"

while read -r ROOT; do
    [ -z "$ROOT" ] && continue
    mkdir -p "$OUT/$ROOT"
    echo "[3.x] $ROOT" | tee -a "$LOG"

    # Run sources in parallel
    (
        # subfinder
        command -v subfinder &>/dev/null && \
            subfinder -d "$ROOT" -all -silent 2>/dev/null > "$OUT/$ROOT/subfinder.txt" &

        # amass passive
        command -v amass &>/dev/null && \
            amass enum -passive -d "$ROOT" -silent 2>/dev/null > "$OUT/$ROOT/amass.txt" &

        # assetfinder
        command -v assetfinder &>/dev/null && \
            assetfinder --subs-only "$ROOT" 2>/dev/null > "$OUT/$ROOT/assetfinder.txt" &

        # crt.sh
        curl -s --max-time 30 "https://crt.sh/?q=%25.${ROOT}&output=json" 2>/dev/null \
          | jq -r '.[].name_value' 2>/dev/null \
          | tr '\n' '\n' | grep -E "\.${ROOT}$" | sort -u > "$OUT/$ROOT/crtsh.txt" &

        # hackertarget
        curl -s --max-time 20 "https://api.hackertarget.com/hostsearch/?q=${ROOT}" 2>/dev/null \
          | cut -d, -f1 | grep -E "\.${ROOT}$" | sort -u > "$OUT/$ROOT/hackertarget.txt" &

        # rapiddns
        curl -sA "Mozilla/5.0" --max-time 30 "https://rapiddns.io/subdomain/${ROOT}?full=1" 2>/dev/null \
          | grep -oE "[a-zA-Z0-9._-]+\.${ROOT//./\\.}" | sort -u > "$OUT/$ROOT/rapiddns.txt" &

        # anubis-jldc
        curl -s --max-time 20 "https://jldc.me/anubis/subdomains/${ROOT}" 2>/dev/null \
          | jq -r '.[]' 2>/dev/null > "$OUT/$ROOT/anubis.txt" &

        # OTX AlienVault
        curl -s --max-time 20 "https://otx.alienvault.com/api/v1/indicators/domain/${ROOT}/passive_dns" 2>/dev/null \
          | jq -r '.passive_dns[].hostname' 2>/dev/null | sort -u > "$OUT/$ROOT/otx.txt" &

        # urlscan.io
        curl -s --max-time 30 "https://urlscan.io/api/v1/search/?q=page.domain:${ROOT}&size=200" 2>/dev/null \
          | jq -r '.results[].page.domain' 2>/dev/null | sort -u > "$OUT/$ROOT/urlscan.txt" &

        # Wayback CDX
        curl -s --max-time 60 "http://web.archive.org/cdx/search/cdx?url=*.${ROOT}&output=text&fl=original&collapse=urlkey&limit=2000" 2>/dev/null \
          | grep -oE 'https?://[^/]+' | sed 's|https\?://||' | grep -E "\.${ROOT}$" | sort -u > "$OUT/$ROOT/wayback.txt" &

        # certspotter
        curl -s --max-time 20 "https://api.certspotter.com/v1/issuances?domain=${ROOT}&include_subdomains=true&expand=dns_names" 2>/dev/null \
          | jq -r '.[].dns_names[]' 2>/dev/null | grep -E "\.${ROOT}$" | sort -u > "$OUT/$ROOT/certspotter.txt" &

        wait
    )

    # Aggregate
    cat "$OUT/$ROOT"/*.txt 2>/dev/null \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/^\*\.//; s/^[*.]*//;' \
      | grep -E "\.${ROOT}$" \
      | sort -u > "$OUT/$ROOT/all_unique.txt"

    COUNT=$(wc -l < "$OUT/$ROOT/all_unique.txt")
    echo "    aggregated $COUNT unique subdomains" | tee -a "$LOG"

    # Per-source diagnostics
    for f in "$OUT/$ROOT"/*.txt; do
        [ "$(basename $f)" = "all_unique.txt" ] && continue
        echo "    $(basename $f .txt): $(wc -l < $f)" | tee -a "$LOG"
    done
done < "$SEEDS"

# Master aggregate across all roots
cat "$OUT"/*/all_unique.txt 2>/dev/null | sort -u > "$OUT/all_master.txt"
echo ""
echo "[+] Phase 3 complete. Total unique subdomain candidates: $(wc -l < $OUT/all_master.txt)" | tee -a "$LOG"
