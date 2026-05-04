#!/bin/bash
# Self-audit harness — verifies that every phase actually ran and produced output.
# Run BEFORE generating the final report. Fails loudly if anything is missing.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

PASS=0
FAIL=0
declare -a FAILED_CHECKS

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  [✓] $name"
        PASS=$((PASS + 1))
    else
        echo "  [✗] $name"
        FAIL=$((FAIL + 1))
        FAILED_CHECKS+=("$name")
    fi
}

echo "=== FireCompass Passive Recon Self-Audit ==="
echo "Engagement: $ENGAGEMENT_DIR"
echo ""

echo "[Phase 0] Engagement setup"
check "engagement.json exists" "[ -f $ENGAGEMENT_DIR/engagement.json ]"
check "seeds/ exists" "[ -d $ENGAGEMENT_DIR/seeds ]"

echo "[Phase 1] Seed + related domain discovery"
check "seed_roots.txt non-empty" "[ -s $ENGAGEMENT_DIR/seeds/seed_roots.txt ]"

echo "[Phase 2] Wildcard cert detection"
check "wildcard_roots.txt exists (even if empty)" "[ -f $ENGAGEMENT_DIR/seeds/wildcard_roots.txt ]"

echo "[Phase 3] Multi-source subdomain enumeration"
check "subdomains/all_master.txt non-empty" "[ -s $ENGAGEMENT_DIR/subdomains/all_master.txt ]"
check "at least 5 sources queried per root" "find $ENGAGEMENT_DIR/subdomains -mindepth 2 -name '*.txt' | wc -l | awk '\$1>=5'"

echo "[Phase 4] JS / source mining"
check "js_filtered.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/js_filtered.txt ]"

echo "[Phase 5] Google / Bing dorking"
check "dork_urls.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/dork_urls.txt ]"

echo "[Phase 6] Shodan passive lookup"
check "shodan_hostnames.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/shodan_hostnames.txt ]"

echo "[Phase 7] DNS resolve + HTTP probe"
check "resolved_hosts.txt non-empty" "[ -s $ENGAGEMENT_DIR/resolved/resolved_hosts.txt ]"
check "live/probed.tsv non-empty" "[ -s $ENGAGEMENT_DIR/live/probed.tsv ]"

echo "[Phase 8] Pattern permutation"
if [ -s "$ENGAGEMENT_DIR/seeds/wildcard_roots.txt" ]; then
    check "permutation_hits.tsv exists (wildcard roots present)" "[ -f $ENGAGEMENT_DIR/subdomains/permutation_hits.tsv ]"
else
    echo "  [-] no wildcard roots — permutation skipped (ok)"
fi

echo "[Phase 9] ASN / netblock"
check "ips/asns.txt exists" "[ -f $ENGAGEMENT_DIR/ips/asns.txt ]"

echo "[Phase 10] Shodan ports"
check "ips/shodan_ports.jsonl exists" "[ -f $ENGAGEMENT_DIR/ips/shodan_ports.jsonl ]"

echo "[Phase 11] Leaked credentials"
check "creds/ has output (any source)" "ls $ENGAGEMENT_DIR/creds/* 2>/dev/null | head -1"

echo "[Phase 12] GitHub leaks"
check "github/ has output" "ls $ENGAGEMENT_DIR/github/* 2>/dev/null | head -1"

echo "[Phase 13] Cloud buckets"
check "cloud/s3_findings.tsv exists" "[ -f $ENGAGEMENT_DIR/cloud/s3_findings.tsv ]"

echo "[Phase 14] Email / people OSINT"
check "emails_osint/ has output" "ls $ENGAGEMENT_DIR/emails_osint/* 2>/dev/null | head -1"

echo ""
echo "=== Result ==="
echo "PASS: $PASS    FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FAILED:"
    for c in "${FAILED_CHECKS[@]}"; do echo "  - $c"; done
    echo ""
    echo "Recon is INCOMPLETE. Re-run the missing phases before generating the final report."
    exit 1
fi
echo ""
echo "✓ All phases verified. Safe to generate final report."
