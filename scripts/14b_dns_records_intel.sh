#!/bin/bash
# Phase 14.5 — DNS records intelligence (MX/SPF/DKIM/DMARC/TXT/NS/SOA)
# Reference: HackTricks /src/network-services-pentesting/pentesting-dns.md
# Reference: PAT /Methodology and Resources/Network Pivoting Techniques.md
#
# Why: DNS records beyond A/AAAA are a goldmine for passive recon:
#   - MX records → email infrastructure (Google Workspace / O365 / on-prem)
#   - SPF records → ALL authorised email senders, often includes: SaaS providers
#     (Salesforce, HubSpot, Mailchimp, SendGrid), cloud infra (aws.amazon.com,
#     spf.protection.outlook.com), and internal mail servers → full SaaS footprint
#   - DKIM → key rotation hygiene, selector naming conventions (brand hints)
#   - DMARC → p=none means no enforcement → phishing risk; also reveals rua/ruf report URLs
#   - TXT records → domain ownership verifications (Google-site-verification,
#     docusign, atlassian-domain-verification, stripe, etc.) → SaaS footprint
#   - NS records → nameserver provider (Route53, Cloudflare, self-hosted)
#   - SOA → primary nameserver + admin email (OPSEC leak — abuse@domain or noc@domain)
#   - CNAME wildcards → potential subdomain takeover surface
#
# This is passive — only DNS queries to public resolvers.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/dns_records"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
MASTER_SUB="$ENGAGEMENT_DIR/subdomains/all_master.txt"
LOG="$ENGAGEMENT_DIR/logs/14b_dns_records_intel.log"
mkdir -p "$OUT"

[ ! -f "$SEEDS" ] && { echo "Run Phase 0 first"; exit 1; }

echo "[*] Phase 14.5 — DNS records intelligence" | tee "$LOG"
log_phase_start "14.5" "DNS Records Intelligence (MX/SPF/DKIM/DMARC/TXT/NS/SOA)"
log_hypothesis \
    "SPF and MX records will reveal the org's full email-sending SaaS footprint; DMARC policy will show whether phishing is currently detectable; TXT verification tokens will surface SaaS integrations not visible from the web" \
    "Run dig for A, AAAA, MX, TXT, NS, SOA, CNAME on every root and key subdomain; parse SPF includes, DMARC policy, DKIM selectors, TXT verification tokens" \
    "If DMARC p=reject and SPF all=-all, email surface is hardened — note but continue; if p=none or missing, flag as critical phishing risk"

# Combined scope: roots + subdomains (capped)
SCOPE="$OUT/dns_scope.txt"
{ cat "$SEEDS"; [ -f "$MASTER_SUB" ] && head -100 "$MASTER_SUB"; } | sort -u > "$SCOPE"
TOTAL=$(wc -l < "$SCOPE")
echo "    scope: $TOTAL domains" | tee -a "$LOG"

# Output files
echo -e "domain\ttype\tvalue" > "$OUT/dns_records.tsv"
echo -e "domain\tmx_record\tpriority\tprovider_hint" > "$OUT/mx_records.tsv"
echo -e "domain\tspf_raw\tinclude_count\tincludes\tip_ranges" > "$OUT/spf_analysis.tsv"
echo -e "domain\tdmarc_policy\trua\truf\tpct\tadkim\taspf" > "$OUT/dmarc_analysis.tsv"
echo -e "domain\tverification_service\ttoken_hint" > "$OUT/txt_verifications.tsv"
> "$OUT/spf_third_parties.txt"

# Helper: identify MX provider
mx_provider() {
    local MX_HOST="$1"
    echo "$MX_HOST" | grep -qi 'google\|gmail'          && echo "Google Workspace" && return
    echo "$MX_HOST" | grep -qi 'outlook\|protection\.microsoft' && echo "Microsoft 365" && return
    echo "$MX_HOST" | grep -qi 'yahoodns\|yahoo'        && echo "Yahoo" && return
    echo "$MX_HOST" | grep -qi 'pphosted\|proofpoint'   && echo "Proofpoint" && return
    echo "$MX_HOST" | grep -qi 'mimecast'               && echo "Mimecast" && return
    echo "$MX_HOST" | grep -qi 'barracuda'              && echo "Barracuda" && return
    echo "$MX_HOST" | grep -qi 'amazonses\|aws'         && echo "Amazon SES" && return
    echo "$MX_HOST" | grep -qi 'sendgrid'               && echo "SendGrid" && return
    echo "$MX_HOST" | grep -qi 'mailchimp\|mandrill'    && echo "Mailchimp/Mandrill" && return
    echo "$MX_HOST" | grep -qi 'zoho'                   && echo "Zoho Mail" && return
    echo "on-prem/unknown"
}

# Helper: parse SPF includes
parse_spf_includes() {
    local SPF="$1"
    echo "$SPF" | grep -oP '(?<=include:)[^\s]+' | sort -u | tr '\n' ',' | sed 's/,$//'
}

while read -r DOMAIN; do
    [ -z "$DOMAIN" ] && continue

    # ── A / AAAA ────────────────────────────────────────────────
    for REC_TYPE in A AAAA; do
        VALS=$(dig +short "$REC_TYPE" "$DOMAIN" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -n "$VALS" ] && echo -e "${DOMAIN}\t${REC_TYPE}\t${VALS}" >> "$OUT/dns_records.tsv"
    done

    # ── CNAME ───────────────────────────────────────────────────
    CNAME=$(dig +short CNAME "$DOMAIN" 2>/dev/null | head -1 | tr -d '\n')
    [ -n "$CNAME" ] && echo -e "${DOMAIN}\tCNAME\t${CNAME}" >> "$OUT/dns_records.tsv"

    # ── NS ──────────────────────────────────────────────────────
    NS_VALS=$(dig +short NS "$DOMAIN" 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//')
    if [ -n "$NS_VALS" ]; then
        echo -e "${DOMAIN}\tNS\t${NS_VALS}" >> "$OUT/dns_records.tsv"
        echo "    [NS] $DOMAIN → $NS_VALS" | tee -a "$LOG"
    fi

    # ── SOA ─────────────────────────────────────────────────────
    SOA=$(dig +short SOA "$DOMAIN" 2>/dev/null | head -1)
    if [ -n "$SOA" ]; then
        echo -e "${DOMAIN}\tSOA\t${SOA}" >> "$OUT/dns_records.tsv"
        SOA_EMAIL=$(echo "$SOA" | awk '{print $2}' | sed 's/\.$/./' | sed 's/\./\@/1')
        echo "    [SOA] $DOMAIN → admin email hint: $SOA_EMAIL" | tee -a "$LOG"
    fi

    # ── MX ──────────────────────────────────────────────────────
    while read -r PRIORITY MX_HOST; do
        [ -z "$MX_HOST" ] && continue
        PROVIDER=$(mx_provider "$MX_HOST")
        echo -e "${DOMAIN}\t${MX_HOST}\t${PRIORITY}\t${PROVIDER}" >> "$OUT/mx_records.tsv"
        echo "    [MX] $DOMAIN → $MX_HOST ($PROVIDER)" | tee -a "$LOG"
    done < <(dig +short MX "$DOMAIN" 2>/dev/null | awk '{print $1, $2}')

    # ── TXT (all records) ────────────────────────────────────────
    TXT_ALL=$(dig +short TXT "$DOMAIN" 2>/dev/null | tr -d '"')
    echo "$TXT_ALL" | while read -r TXT_LINE; do
        [ -z "$TXT_LINE" ] && continue
        echo -e "${DOMAIN}\tTXT\t${TXT_LINE}" >> "$OUT/dns_records.tsv"
    done

    # ── SPF ─────────────────────────────────────────────────────
    SPF_RAW=$(echo "$TXT_ALL" | grep -i '^v=spf1' | head -1)
    if [ -n "$SPF_RAW" ]; then
        INCLUDES=$(parse_spf_includes "$SPF_RAW")
        IP_RANGES=$(echo "$SPF_RAW" | grep -oP 'ip[46]:[^\s]+' | tr '\n' ',' | sed 's/,$//')
        INCLUDE_COUNT=$(echo "$INCLUDES" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)
        echo -e "${DOMAIN}\t${SPF_RAW}\t${INCLUDE_COUNT}\t${INCLUDES}\t${IP_RANGES}" >> "$OUT/spf_analysis.tsv"
        echo "    [SPF] $DOMAIN → $INCLUDE_COUNT includes: $INCLUDES" | tee -a "$LOG"
        # Aggregate third-party services
        echo "$INCLUDES" | tr ',' '\n' | grep -v "^${DOMAIN}" >> "$OUT/spf_third_parties.txt"
    fi

    # ── DMARC ───────────────────────────────────────────────────
    DMARC=$(dig +short TXT "_dmarc.${DOMAIN}" 2>/dev/null | tr -d '"' | grep -i 'v=DMARC1' | head -1)
    if [ -n "$DMARC" ]; then
        POLICY=$(echo "$DMARC" | grep -oP '(?<=p=)[^;]+' | head -1)
        RUA=$(echo "$DMARC" | grep -oP '(?<=rua=)[^;]+' | head -1)
        RUF=$(echo "$DMARC" | grep -oP '(?<=ruf=)[^;]+' | head -1)
        PCT=$(echo "$DMARC" | grep -oP '(?<=pct=)[^;]+' | head -1)
        ADKIM=$(echo "$DMARC" | grep -oP '(?<=adkim=)[^;]+' | head -1)
        ASPF=$(echo "$DMARC" | grep -oP '(?<=aspf=)[^;]+' | head -1)
        echo -e "${DOMAIN}\t${POLICY}\t${RUA}\t${RUF}\t${PCT}\t${ADKIM}\t${ASPF}" >> "$OUT/dmarc_analysis.tsv"
        POLICY_NOTE=""
        [ "$POLICY" = "none" ] && POLICY_NOTE=" [!] p=none → NO enforcement, phishing risk"
        echo "    [DMARC] $DOMAIN → p=$POLICY${POLICY_NOTE}" | tee -a "$LOG"
    else
        echo -e "${DOMAIN}\tNONE\t\t\t\t\t" >> "$OUT/dmarc_analysis.tsv"
        echo "    [DMARC] $DOMAIN → NO DMARC record [!] phishing risk" | tee -a "$LOG"
    fi

    # ── DKIM common selectors ────────────────────────────────────
    for SEL in default google selector1 selector2 dkim mail email k1 smtp \
               s1 s2 mimecast mandrill mailchimp sendgrid amazonses; do
        DKIM=$(dig +short TXT "${SEL}._domainkey.${DOMAIN}" 2>/dev/null | tr -d '"' | grep -i 'v=DKIM1' | head -1)
        if [ -n "$DKIM" ]; then
            echo -e "${DOMAIN}\tDKIM:${SEL}\t${DKIM:0:80}" >> "$OUT/dns_records.tsv"
            echo "    [DKIM] $DOMAIN → selector: $SEL" | tee -a "$LOG"
        fi
    done

    # ── TXT ownership verifications ──────────────────────────────
    echo "$TXT_ALL" | grep -iE 'google-site-verification|docusign|atlassian-domain|stripe|apple-domain|facebook|ms=|adobe-idp|dropbox-domain|sendgrid|mailchimpsso' | \
    while read -r VERIF; do
        SVC=$(echo "$VERIF" | grep -oiP 'google-site-verification|docusign|atlassian-domain|stripe|apple-domain|facebook-domain|ms=|adobe-idp|dropbox-domain|sendgrid|mailchimpsso' | head -1)
        echo -e "${DOMAIN}\t${SVC}\t${VERIF:0:80}" >> "$OUT/txt_verifications.tsv"
        echo "    [TXT-verify] $DOMAIN → $SVC" | tee -a "$LOG"
    done

done < "$SCOPE"

# Dedupe SPF third parties
sort -u "$OUT/spf_third_parties.txt" -o "$OUT/spf_third_parties.txt"

# Summary
echo "" | tee -a "$LOG"
echo "[+] Phase 14.5 complete." | tee -a "$LOG"
echo "    DNS records logged:   $(($(wc -l < $OUT/dns_records.tsv) - 0))" | tee -a "$LOG"
echo "    MX records:           $(($(wc -l < $OUT/mx_records.tsv) - 1))" | tee -a "$LOG"
echo "    SPF records:          $(($(wc -l < $OUT/spf_analysis.tsv) - 1))" | tee -a "$LOG"
echo "    DMARC records:        $(($(wc -l < $OUT/dmarc_analysis.tsv) - 1))" | tee -a "$LOG"
echo "    SPF 3rd parties:      $(wc -l < $OUT/spf_third_parties.txt)" | tee -a "$LOG"
echo "    TXT verifications:    $(($(wc -l < $OUT/txt_verifications.tsv) - 1))" | tee -a "$LOG"
DMARC_GAPS=$(grep -c 'p=none\|NO DMARC' "$LOG" 2>/dev/null || echo 0)
[ "$DMARC_GAPS" -gt 0 ] && echo "    [!] DMARC gaps found — see dmarc_analysis.tsv" | tee -a "$LOG"

SPF_PARTIES=$(wc -l < "$OUT/spf_third_parties.txt")
TXT_VERIF=$(($(wc -l < "$OUT/txt_verifications.tsv") - 1))

log_stats "Phase 14.5 results" \
    "DNS records logged:$(wc -l < $OUT/dns_records.tsv)" \
    "MX records:$(($(wc -l < $OUT/mx_records.tsv) - 1))" \
    "SPF records:$(($(wc -l < $OUT/spf_analysis.tsv) - 1))" \
    "DMARC records:$(($(wc -l < $OUT/dmarc_analysis.tsv) - 1))" \
    "SPF 3rd-party services:${SPF_PARTIES}" \
    "TXT verifications:${TXT_VERIF}" \
    "DMARC gaps (p=none or missing):${DMARC_GAPS}"
[ "$DMARC_GAPS" -gt 0 ] && log_finding HIGH "DNS: $DMARC_GAPS domain(s) have no DMARC enforcement (p=none or missing) — email spoofing/phishing trivially possible"
[ "$SPF_PARTIES" -gt 0 ] && log_finding NOTABLE "DNS: $SPF_PARTIES 3rd-party SaaS services authorised in SPF — full vendor list in dns_records/spf_third_parties.txt"
log_phase_end "14.5" "DNS records intelligence complete. Full data in dns_records/. DMARC gaps: $DMARC_GAPS."
