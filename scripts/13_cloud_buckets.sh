#!/bin/bash
# Phase 13 — Cloud bucket discovery (S3, GCS, Azure)
# Reference: hacktricks-cloud /src/pentesting-cloud/aws-security/aws-unauthenticated-enum-access/README.md
# Reference: PAT      /Methodology and Resources/Cloud - AWS Pentest.md
#
# Why: Misconfigured S3/GCS/Azure buckets are a top breach vector. Bucket names
# follow predictable patterns (org name + environment). HTTP 200 = public,
# 403 = exists but listing denied (still a finding), 404 = doesn't exist.

set -e
: "${ENGAGEMENT_DIR:?export ENGAGEMENT_DIR}"
: "${ORG_NAME:?export ORG_NAME=...}"

OUT="$ENGAGEMENT_DIR/cloud"
LOG="$ENGAGEMENT_DIR/logs/13_cloud_buckets.log"
mkdir -p "$OUT"

# Build org slug variants (lowercase, no spaces, plus simple variants)
SLUG=$(echo "$ORG_NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
SLUG2=$(echo "$ORG_NAME" | tr '[:upper:] ' '[:lower:]' | tr -cd 'a-z0-9')

# Read variant template
HERE="$(dirname "$(readlink -f "$0")")/.."
VARIANT_TEMPLATE="$HERE/wordlists/cloud-bucket-variants.txt"

# Generate full list
> "$OUT/bucket_candidates.txt"
for s in "$SLUG" "$SLUG2"; do
    while read -r line; do
        [ -z "$line" ] || [ "${line:0:1}" = "#" ] && continue
        echo "${line//__ORG__/$s}" >> "$OUT/bucket_candidates.txt"
    done < "$VARIANT_TEMPLATE"
done
sort -u "$OUT/bucket_candidates.txt" -o "$OUT/bucket_candidates.txt"

echo "[*] Phase 13 — Cloud bucket discovery" | tee "$LOG"
echo "    candidates: $(wc -l < $OUT/bucket_candidates.txt)" | tee -a "$LOG"

# Probe S3 (us-east-1 + region-specific)
> "$OUT/s3_findings.tsv"
echo -e "name\tregion\tstatus" > "$OUT/s3_findings.tsv"

while read -r name; do
    [ -z "$name" ] && continue
    # Global S3
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://${name}.s3.amazonaws.com/" 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "403" ]; then
        echo -e "${name}\tglobal\t${code}" >> "$OUT/s3_findings.tsv"
        echo "    [s3] ${name} -> $code" | tee -a "$LOG"
    fi
done < "$OUT/bucket_candidates.txt"

# GCS
> "$OUT/gcs_findings.tsv"
echo -e "name\tstatus" > "$OUT/gcs_findings.tsv"
while read -r name; do
    [ -z "$name" ] && continue
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://storage.googleapis.com/${name}/" 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "403" ]; then
        echo -e "${name}\t${code}" >> "$OUT/gcs_findings.tsv"
        echo "    [gcs] ${name} -> $code" | tee -a "$LOG"
    fi
done < "$OUT/bucket_candidates.txt"

# Azure Blob
> "$OUT/azure_findings.tsv"
echo -e "name\tstatus" > "$OUT/azure_findings.tsv"
while read -r name; do
    [ -z "$name" ] && continue
    azname=$(echo "$name" | tr -d '-' | cut -c1-24)
    [ -z "$azname" ] && continue
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://${azname}.blob.core.windows.net/?comp=list" 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "400" ] || [ "$code" = "403" ]; then
        echo -e "${azname}\t${code}" >> "$OUT/azure_findings.tsv"
        echo "    [azure] ${azname} -> $code" | tee -a "$LOG"
    fi
done < "$OUT/bucket_candidates.txt"

S3_HITS=$(($(wc -l < "$OUT/s3_findings.tsv") - 1))
GCS_HITS=$(($(wc -l < "$OUT/gcs_findings.tsv") - 1))
AZ_HITS=$(($(wc -l < "$OUT/azure_findings.tsv") - 1))

echo ""
echo "[+] Phase 13 complete." | tee -a "$LOG"
echo "    S3 hits: $S3_HITS    GCS hits: $GCS_HITS    Azure hits: $AZ_HITS" | tee -a "$LOG"
echo "    HTTP 200 = public listing (CRITICAL); 403 = exists private (HIGH)" | tee -a "$LOG"
