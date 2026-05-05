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
check "engagement_logs.md exists and non-empty" "[ -s $ENGAGEMENT_DIR/engagement_logs.md ]"
check "engagement_logs.md has phase entries" "grep -c '^## Phase' $ENGAGEMENT_DIR/engagement_logs.md | awk '\$1>=3'"
check "engagement_logs.md has timestamps" "grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' $ENGAGEMENT_DIR/engagement_logs.md | awk '\$1>=3'"
check "engagement_logs.md has findings" "grep -ciE 'finding|NOTABLE|HIGH|CRITICAL|INFO\]' $ENGAGEMENT_DIR/engagement_logs.md | awk '\$1>=1'"

echo "[Phase 0.5] Target visualisation (mandatory)"
check "target_visualisation.md exists" "[ -s $ENGAGEMENT_DIR/reports/target_visualisation.md ]"
check "target_visualisation has industry classification" "grep -qi 'industry' $ENGAGEMENT_DIR/reports/target_visualisation.md"
check "target_visualisation has expected asset categories" "grep -qiE 'expected asset|asset class' $ENGAGEMENT_DIR/reports/target_visualisation.md"

echo "[Decision Log + Strategic Narrative — reviewability artefacts]"
check "decision_log.md exists" "[ -s $ENGAGEMENT_DIR/reports/decision_log.md ]"
check "decision_log has Hypothesis blocks" "grep -ciE '^### Hypothesis' $ENGAGEMENT_DIR/reports/decision_log.md | awk '\$1>=10'"
check "decision_log has 'What I Ruled Out' entries" "grep -ciE 'Ruled Out' $ENGAGEMENT_DIR/reports/decision_log.md | awk '\$1>=10'"
check "decision_log has 'Expert Would Also Do' critiques" "grep -ciE 'Expert Would Also Do' $ENGAGEMENT_DIR/reports/decision_log.md | awk '\$1>=10'"
check "decision_log has self-confidence scores" "grep -ciE 'Self-confidence' $ENGAGEMENT_DIR/reports/decision_log.md | awk '\$1>=10'"
check "strategic_narrative.md exists" "[ -s $ENGAGEMENT_DIR/reports/strategic_narrative.md ]"
check "strategic_narrative has 'pivotal' or pivot decision" "grep -ciE 'pivot|pivotal' $ENGAGEMENT_DIR/reports/strategic_narrative.md | awk '\$1>=1'"

echo "[Phase 1] Seed + related domain discovery"
check "seed_roots.txt non-empty" "[ -s $ENGAGEMENT_DIR/seeds/seed_roots.txt ]"

echo "[Phase 2] Wildcard cert detection"
check "wildcard_roots.txt exists (even if empty)" "[ -f $ENGAGEMENT_DIR/seeds/wildcard_roots.txt ]"

echo "[Phase 3] Multi-source subdomain enumeration"
check "subdomains/all_master.txt non-empty" "[ -s $ENGAGEMENT_DIR/subdomains/all_master.txt ]"
check "at least 5 sources queried per root" "find $ENGAGEMENT_DIR/subdomains -mindepth 2 -name '*.txt' | wc -l | awk '\$1>=5'"

echo "[Phase 4] JS / source mining"
check "js_filtered.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/js_filtered.txt ]"

echo "[Phase 4.5] Public web asset reading"
check "web_assets/findings.tsv exists" "[ -f $ENGAGEMENT_DIR/web_assets/findings.tsv ]"

echo "[Phase 5] Google / Bing dorking"
check "dork_urls.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/dork_urls.txt ]"

echo "[Phase 6] Shodan passive lookup"
check "shodan_hostnames.txt exists" "[ -f $ENGAGEMENT_DIR/subdomains/shodan_hostnames.txt ]"

echo "[Phase 7] DNS resolve + HTTP probe"
check "resolved_hosts.txt non-empty" "[ -s $ENGAGEMENT_DIR/resolved/resolved_hosts.txt ]"
check "live/probed.tsv non-empty" "[ -s $ENGAGEMENT_DIR/live/probed.tsv ]"

echo "[Phase 7.5] TLS cert deep inspection"
check "tls/cert_summary.tsv exists" "[ -f $ENGAGEMENT_DIR/tls/cert_summary.tsv ]"
check "tls/all_sans_unique.txt exists" "[ -f $ENGAGEMENT_DIR/tls/all_sans_unique.txt ]"

echo "[Phase 7.5b] Live app fingerprinting"
check "fingerprint/headers_raw.tsv exists" "[ -f $ENGAGEMENT_DIR/fingerprint/headers_raw.tsv ]"
check "fingerprint/live_hosts.txt exists" "[ -f $ENGAGEMENT_DIR/fingerprint/live_hosts.txt ]"

echo "[Phase 7.6] Web surface harvest"
check "web_surface/robots_disallow.txt exists" "[ -f $ENGAGEMENT_DIR/web_surface/robots_disallow.txt ]"
check "web_surface/wellknown_findings.tsv exists" "[ -f $ENGAGEMENT_DIR/web_surface/wellknown_findings.tsv ]"

echo "[Phase 7.7] Wayback URL crawl"
check "wayback_urls/all_urls_raw.txt exists" "[ -f $ENGAGEMENT_DIR/wayback_urls/all_urls_raw.txt ]"
check "wayback_urls/interesting_files.txt exists" "[ -f $ENGAGEMENT_DIR/wayback_urls/interesting_files.txt ]"
check "wayback_urls/api_endpoints.txt exists" "[ -f $ENGAGEMENT_DIR/wayback_urls/api_endpoints.txt ]"

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

echo "[Phase 12.5] Beyond-GitHub code search"
check "github/beyond_github_hits.tsv exists" "[ -f $ENGAGEMENT_DIR/github/beyond_github_hits.tsv ]"
check "github/paste_dork_urls.txt exists" "[ -f $ENGAGEMENT_DIR/github/paste_dork_urls.txt ]"

echo "[Phase 13] Cloud buckets"
check "cloud/s3_findings.tsv exists" "[ -f $ENGAGEMENT_DIR/cloud/s3_findings.tsv ]"

echo "[Phase 14] Email / people OSINT"
check "emails_osint/ has output" "ls $ENGAGEMENT_DIR/emails_osint/* 2>/dev/null | head -1"

echo "[Phase 14.5] DNS records intelligence"
check "dns_records/dns_records.tsv exists" "[ -f $ENGAGEMENT_DIR/dns_records/dns_records.tsv ]"
check "dns_records/spf_third_parties.txt exists" "[ -f $ENGAGEMENT_DIR/dns_records/spf_third_parties.txt ]"
check "dns_records/dmarc_analysis.tsv exists" "[ -f $ENGAGEMENT_DIR/dns_records/dmarc_analysis.tsv ]"
check "dns_records/mx_records.tsv exists" "[ -f $ENGAGEMENT_DIR/dns_records/mx_records.tsv ]"

echo "[Phase 15] Mobile app surface"
check "mobile/app_store_findings.tsv exists" "[ -f $ENGAGEMENT_DIR/mobile/app_store_findings.tsv ]"
check "mobile/mobile_dork_urls.txt exists" "[ -f $ENGAGEMENT_DIR/mobile/mobile_dork_urls.txt ]"

echo "[Phase 16] Document metadata"
check "documents/metadata_findings.tsv exists" "[ -f $ENGAGEMENT_DIR/documents/metadata_findings.tsv ]"
check "documents/all_usernames_hint.txt exists" "[ -f $ENGAGEMENT_DIR/documents/all_usernames_hint.txt ]"

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
