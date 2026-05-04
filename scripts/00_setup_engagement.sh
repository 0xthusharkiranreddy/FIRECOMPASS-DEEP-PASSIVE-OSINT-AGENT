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
mkdir -p "$ENGAGEMENT_DIR"/{seeds,subdomains,resolved,live,ips,creds,cloud,github,emails_osint,reports,logs}

cat > "$ENGAGEMENT_DIR/engagement.json" <<EOF
{
  "organisation": "$ORG",
  "primary_domain": "$DOMAIN",
  "slug": "$SLUG",
  "start_date": "$(date -Iseconds)",
  "engagement_dir": "$ENGAGEMENT_DIR",
  "phase_status": {
    "0_setup": "complete",
    "1_seeds": "pending",
    "2_wildcard": "pending",
    "3_subdomain_enum": "pending",
    "4_js_mining": "pending",
    "5_google_dork": "pending",
    "6_shodan": "pending",
    "7_dns_probe": "pending",
    "8_pattern_perm": "pending",
    "9_asn": "pending",
    "10_ports": "pending",
    "11_creds": "pending",
    "12_github": "pending",
    "13_buckets": "pending",
    "14_email_osint": "pending"
  }
}
EOF

# Seed primary domain
echo "$DOMAIN" > "$ENGAGEMENT_DIR/seeds/seed_roots.txt"

echo "[+] Engagement initialised:"
echo "    Org:    $ORG"
echo "    Domain: $DOMAIN"
echo "    Dir:    $ENGAGEMENT_DIR"
echo ""
echo "[*] Export this for downstream phases:"
echo "    export ENGAGEMENT_DIR=$ENGAGEMENT_DIR"
echo "    export PRIMARY_DOMAIN=$DOMAIN"
echo "    export ORG_NAME=\"$ORG\""
