#!/bin/bash
# Phase 0 — Engagement setup
# Creates the directory structure and writes the engagement metadata file.

set -e

ORG="${1:-}"
DOMAIN="${2:-}"

if [ -z "$ORG" ] || [ -z "$DOMAIN" ]; then
    echo "Usage: $0 \"<Org Name>\" <primary-domain>"
    echo "Example: $0 \"Acme Corp\" acme.com"
    exit 1
fi

SLUG=$(echo "$ORG" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
DATE=$(date +%Y%m%d)
ENGAGEMENT_DIR="/home/kali/engagements/${SLUG}-${DATE}"

echo "[*] Creating engagement directory: $ENGAGEMENT_DIR"
mkdir -p "$ENGAGEMENT_DIR"/{seeds,subdomains,resolved,live,ips,creds,cloud,github,emails_osint,tls,fingerprint,web_surface,wayback_urls,dns_records,mobile,documents,reports,logs}

cat > "$ENGAGEMENT_DIR/engagement.json" <<EOF
{
  "organisation": "$ORG",
  "primary_domain": "$DOMAIN",
  "slug": "$SLUG",
  "start_date": "$(date -Iseconds)",
  "engagement_dir": "$ENGAGEMENT_DIR",
  "phase_status": {
    "0_setup": "complete",
    "0.5_target_visualisation": "pending",
    "1_seeds": "pending",
    "2_wildcard": "pending",
    "3_subdomain_enum": "pending",
    "3.5_tls_cert_inspect": "pending",
    "4_js_mining": "pending",
    "5_google_dork": "pending",
    "6_shodan_hostnames": "pending",
    "7_dns_probe": "pending",
    "7.5_live_app_fingerprint": "pending",
    "7.6_web_surface_harvest": "pending",
    "7.7_wayback_url_crawl": "pending",
    "8_pattern_perm": "pending",
    "9_asn": "pending",
    "10_shodan_ports": "pending",
    "11_creds": "pending",
    "12_github": "pending",
    "12.5_beyond_github_code": "pending",
    "13_buckets": "pending",
    "14_email_osint": "pending",
    "14.5_dns_records_intel": "pending",
    "15_mobile_app_surface": "pending",
    "16_document_metadata": "pending"
  }
}
EOF

# Seed primary domain
echo "$DOMAIN" > "$ENGAGEMENT_DIR/seeds/seed_roots.txt"

# ── Initialize engagement_logs.md ─────────────────────────────────────────────
# This is the persistent, real-time journal of EVERYTHING the agent does.
# It survives Claude conversation compaction because it lives on disk.
# Every phase script appends to it. The agent writes reasoning blocks to it.
# Format: timestamped markdown — readable by the analyst at any point.
cat > "$ENGAGEMENT_DIR/engagement_logs.md" <<LOGEOF
# Engagement Activity Log — ${ORG}

**Primary Domain:** ${DOMAIN}
**Started:** $(date -Iseconds)
**Directory:** ${ENGAGEMENT_DIR}

> This file is the ground truth of everything that happened during this engagement.
> It captures agent reasoning, commands run, outputs observed, decisions made, and
> findings as they were discovered — written in real time throughout the engagement.
> It survives Claude conversation compaction and can be reviewed at any point.

---

## Phase 0 — Engagement Initialised

**Timestamp:** $(date '+%Y-%m-%d %H:%M:%S')

- Organisation: ${ORG}
- Primary domain: ${DOMAIN}
- Engagement directory created: ${ENGAGEMENT_DIR}
- Directories initialised: seeds, subdomains, resolved, live, ips, creds, cloud, github, emails_osint, tls, fingerprint, web_surface, wayback_urls, dns_records, mobile, documents, reports, logs
- engagement.json written with all phase status fields

**Next:** Export ENGAGEMENT_DIR and run Phase 0.5 (Target Visualisation).

---
LOGEOF

echo "[+] Engagement initialised:"
echo "    Org:    $ORG"
echo "    Domain: $DOMAIN"
echo "    Dir:    $ENGAGEMENT_DIR"
echo ""
echo "[*] Export this for downstream phases:"
echo "    export ENGAGEMENT_DIR=$ENGAGEMENT_DIR"
echo "    export PRIMARY_DOMAIN=$DOMAIN"
echo "    export ORG_NAME=\"$ORG\""
echo ""
echo "[*] Live activity log: $ENGAGEMENT_DIR/engagement_logs.md"
