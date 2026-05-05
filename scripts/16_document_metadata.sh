#!/bin/bash
# Phase 16 — Public document metadata extraction
# Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ Metadata)
# Reference: PAT /Methodology and Resources/Information Gathering.md
#
# Why: PDFs, Word docs, Excel sheets, and PowerPoints published on the target's
# web presence embed metadata that reveals:
#   - Author names → real internal usernames (often = AD/LDAP login format)
#   - Creator software + version → tech stack fingerprint
#   - Company name → cross-validates org identity, reveals subsidiaries
#   - Last-saved-by user → may differ from author (IT support = privileged user)
#   - Creation timestamps → when the document was first created (data governance hints)
#   - Template paths (Word) → often reveal internal UNC paths (\\SERVER\share)
#     which leak hostnames, domain names, and share structures
#   - Email addresses in metadata → phishing targets
#   - GPS coordinates in images → physical location (for photos accidentally published)
#
# Tools: exiftool (pre-installed on Kali), curl
# Sources: Google dork for filetype:pdf/docx/xlsx on target domain,
#          sitemap.xml URLs from Phase 7.6, direct download from live hosts.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"

OUT="$ENGAGEMENT_DIR/documents"
SEEDS="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
SITEMAP_URLS="$ENGAGEMENT_DIR/web_surface/sitemap_urls.txt"
LOG="$ENGAGEMENT_DIR/logs/16_document_metadata.log"
mkdir -p "$OUT/downloaded"

[ ! -f "$SEEDS" ] && { echo "Run Phase 0 first"; exit 1; }

PRIMARY_DOMAIN=$(head -1 "$SEEDS")
ORG_KEYWORDS=$(awk -F'.' '{print $1}' "$SEEDS" | sort -u | head -3)

echo "[*] Phase 16 — Public document metadata extraction" | tee "$LOG"
log_phase_start "16" "Public Document Metadata Extraction (exiftool)"
log_hypothesis \
    "PDFs and Office documents published on the target's web presence embed author names, last-saved-by users, company names, internal UNC paths, and email addresses in metadata" \
    "Collect document URLs from sitemap (Phase 7.6) + direct probe of common paths; download and run exiftool on each; extract usernames, emails, UNC paths" \
    "If all documents have stripped metadata, IT policy or PDF normalisation is in place — note as security hygiene positive"
echo "    primary domain: $PRIMARY_DOMAIN" | tee -a "$LOG"

# Check exiftool available
if ! command -v exiftool &>/dev/null; then
    echo "[!] exiftool not found. Install: apt-get install -y libimage-exiftool-perl" | tee -a "$LOG"
    exit 1
fi

echo -e "source_url\tfile_type\tauthor\tlast_saved_by\tcompany\tcreator_tool\tcreated\tmodified\ttemplate_path\temail_hints" \
    > "$OUT/metadata_findings.tsv"

# ── Build document URL list ───────────────────────────────────────────────────
DOC_URLS="$OUT/doc_urls.txt"
> "$DOC_URLS"

# From sitemap URLs (Phase 7.6 output)
if [ -f "$SITEMAP_URLS" ]; then
    grep -iE '\.(pdf|docx?|xlsx?|pptx?|odt|ods|odp|rtf)(\?|$)' "$SITEMAP_URLS" >> "$DOC_URLS" || true
    echo "    from sitemap: $(wc -l < $DOC_URLS) docs" | tee -a "$LOG"
fi

# Google dork URLs for analyst (cannot automate Google) — generate for manual use
DORK_FILE="$OUT/document_dork_urls.txt"
> "$DORK_FILE"
for EXT in pdf docx xlsx pptx doc xls; do
    echo "https://www.google.com/search?q=site:${PRIMARY_DOMAIN}+filetype:${EXT}" >> "$DORK_FILE"
    echo "https://www.bing.com/search?q=site:${PRIMARY_DOMAIN}+filetype:${EXT}" >> "$DORK_FILE"
done
echo "    Dork URLs written to: $DORK_FILE (open manually in browser)" | tee -a "$LOG"

# Common document paths to probe directly on live hosts
LIVE_HOSTS_FILE="$ENGAGEMENT_DIR/web_surface/live_bases.txt"
[ ! -f "$LIVE_HOSTS_FILE" ] && \
    awk -F'\t' 'NR>1 && $3==200 {print $2"://"$1}' "$ENGAGEMENT_DIR/live/probed.tsv" 2>/dev/null \
    | sort -u > "$OUT/live_tmp.txt" && LIVE_HOSTS_FILE="$OUT/live_tmp.txt"

COMMON_DOC_PATHS=(
    "/documents/"
    "/files/"
    "/downloads/"
    "/resources/"
    "/media/"
    "/assets/docs/"
    "/public/docs/"
    "/wp-content/uploads/"
    "/sitemap.pdf"
    "/brochure.pdf"
    "/whitepaper.pdf"
    "/annual-report.pdf"
    "/security-policy.pdf"
    "/privacy-policy.pdf"
)

if [ -f "$LIVE_HOSTS_FILE" ]; then
    while read -r BASE_URL; do
        [ -z "$BASE_URL" ] && continue
        for DOC_PATH in "${COMMON_DOC_PATHS[@]}"; do
            RESP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "${BASE_URL}${DOC_PATH}" 2>/dev/null)
            if [[ "$RESP_CODE" == "200" ]]; then
                CT=$(curl -sk -L --max-time 8 -I "${BASE_URL}${DOC_PATH}" 2>/dev/null | \
                     grep -i 'content-type' | head -1 | tr -d '\r')
                if echo "$CT" | grep -qiE 'pdf|word|excel|powerpoint|officedocument|opendocument'; then
                    echo "${BASE_URL}${DOC_PATH}" >> "$DOC_URLS"
                fi
            fi
        done
    done < <(head -10 "$LIVE_HOSTS_FILE")
fi

# Dedupe doc URLs
sort -u "$DOC_URLS" -o "$DOC_URLS"
DOC_COUNT=$(wc -l < "$DOC_URLS")
echo "    document URLs to inspect: $DOC_COUNT" | tee -a "$LOG"

# ── Download and extract metadata ─────────────────────────────────────────────
DOWNLOADED=0
while read -r DOC_URL; do
    [ -z "$DOC_URL" ] && continue

    # Derive filename from URL
    FNAME=$(echo "$DOC_URL" | sed 's|.*/||' | sed 's/[?&].*//' | head -c 80)
    [ -z "$FNAME" ] && FNAME="doc_$(date +%s%N)"
    LOCAL_PATH="$OUT/downloaded/${FNAME}"

    # Download (cap at 5MB — we only need metadata, not full file)
    HTTP_CODE=$(curl -sk -L --max-time 20 -r 0-5000000 -w '%{http_code}' \
        -o "$LOCAL_PATH" "$DOC_URL" 2>/dev/null)

    if [[ "$HTTP_CODE" == "200" ]] && [ -s "$LOCAL_PATH" ]; then
        DOWNLOADED=$((DOWNLOADED + 1))

        # Extract metadata with exiftool
        EXIF_OUT=$(exiftool -j "$LOCAL_PATH" 2>/dev/null | python3 -c "
import json, sys

data = json.load(sys.stdin)
if not data:
    sys.exit(0)
m = data[0]

author      = m.get('Author', m.get('Creator', ''))
last_saved  = m.get('LastSavedBy', m.get('LastModifiedBy', ''))
company     = m.get('Company', m.get('Organization', ''))
creator_app = m.get('CreatorTool', m.get('Software', m.get('Application', '')))
created     = m.get('CreateDate', m.get('DateCreated', ''))
modified    = m.get('ModifyDate', m.get('MetadataDate', ''))
template    = m.get('Template', '')
file_type   = m.get('FileType', '')

# Scrape email-like strings from all values
import re
all_vals = ' '.join(str(v) for v in m.values())
emails = re.findall(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', all_vals)
email_str = ';'.join(set(emails))

fields = [author, last_saved, company, creator_app, created, modified, template, email_str]
print('\t'.join(str(f).replace('\t',' ') for f in fields))
" 2>/dev/null)

        if [ -n "$EXIF_OUT" ]; then
            FILE_TYPE=$(exiftool -FileType -s3 "$LOCAL_PATH" 2>/dev/null)
            echo -e "${DOC_URL}\t${FILE_TYPE}\t${EXIF_OUT}" >> "$OUT/metadata_findings.tsv"

            # Flag internal UNC paths (huge finding)
            if echo "$EXIF_OUT" | grep -qE '\\\\[A-Za-z0-9_-]+\\'; then
                echo "    [!!!] UNC path in metadata: $DOC_URL → $EXIF_OUT" | tee -a "$LOG"
            fi

            # Flag emails in metadata
            EMAIL_COUNT=$(echo "$EXIF_OUT" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | wc -l)
            [ "$EMAIL_COUNT" -gt 0 ] && echo "    [+] $FNAME → $EMAIL_COUNT email(s) in metadata" | tee -a "$LOG"
        fi
    fi

    # Cap downloads at 50 to avoid excessive bandwidth
    [ "$DOWNLOADED" -ge 50 ] && break
done < "$DOC_URLS"

# ── Build unique author/username list ─────────────────────────────────────────
awk -F'\t' 'NR>1 && $3!="" {print $3}' "$OUT/metadata_findings.tsv" | sort -u \
    > "$OUT/author_names.txt"
awk -F'\t' 'NR>1 && $4!="" {print $4}' "$OUT/metadata_findings.tsv" | sort -u \
    > "$OUT/last_saved_by.txt"
cat "$OUT/author_names.txt" "$OUT/last_saved_by.txt" | sort -u > "$OUT/all_usernames_hint.txt"
awk -F'\t' 'NR>1 {print $9}' "$OUT/metadata_findings.tsv" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | \
    sort -u > "$OUT/emails_from_metadata.txt"

# Merge emails into main email OSINT
EMAIL_MASTER="$ENGAGEMENT_DIR/emails_osint/emails_master.txt"
if [ -s "$OUT/emails_from_metadata.txt" ] && [ -d "$ENGAGEMENT_DIR/emails_osint" ]; then
    cat "$OUT/emails_from_metadata.txt" >> "$EMAIL_MASTER"
    sort -u "$EMAIL_MASTER" -o "$EMAIL_MASTER"
fi

# Summary
echo "" | tee -a "$LOG"
echo "[+] Phase 16 complete." | tee -a "$LOG"
echo "    Documents downloaded:  $DOWNLOADED" | tee -a "$LOG"
echo "    Metadata records:      $(($(wc -l < $OUT/metadata_findings.tsv) - 1))" | tee -a "$LOG"
echo "    Unique author names:   $(wc -l < $OUT/author_names.txt)" | tee -a "$LOG"
echo "    Last-saved-by users:   $(wc -l < $OUT/last_saved_by.txt)" | tee -a "$LOG"
echo "    Emails from metadata:  $(wc -l < $OUT/emails_from_metadata.txt)" | tee -a "$LOG"
UNC_COUNT=$(grep -c 'UNC path' "$LOG" 2>/dev/null || echo 0)
[ "$UNC_COUNT" -gt 0 ] && echo "    [!!!] UNC paths found — check metadata_findings.tsv immediately" | tee -a "$LOG"

AUTH_COUNT=$(wc -l < "$OUT/author_names.txt")
EMAIL_COUNT=$(wc -l < "$OUT/emails_from_metadata.txt")

log_stats "Phase 16 results" \
    "Documents downloaded:${DOWNLOADED}" \
    "Metadata records extracted:$(($(wc -l < $OUT/metadata_findings.tsv) - 1))" \
    "Unique author names:${AUTH_COUNT}" \
    "Last-saved-by users:$(wc -l < $OUT/last_saved_by.txt)" \
    "Emails in metadata:${EMAIL_COUNT}" \
    "Internal UNC paths:${UNC_COUNT}"
[ "$UNC_COUNT" -gt 0 ] && log_finding CRITICAL "Document metadata: $UNC_COUNT documents contain internal UNC paths (\\\\server\\share format) — reveals internal hostnames and AD structure"
[ "$EMAIL_COUNT" -gt 0 ] && log_finding NOTABLE "Document metadata: $EMAIL_COUNT email addresses extracted — added to emails_osint/emails_master.txt"
[ "$AUTH_COUNT" -gt 0 ] && log_finding NOTABLE "Document metadata: $AUTH_COUNT unique author usernames — potential AD username format hints in documents/all_usernames_hint.txt"
log_phase_end "16" "Document metadata extraction complete. $DOWNLOADED docs processed. Key data in documents/."
