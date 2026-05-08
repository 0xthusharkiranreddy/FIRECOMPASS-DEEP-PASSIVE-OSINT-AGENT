#!/bin/bash
# scripts/99_self_audit.sh — Mandatory pre-report completeness gate
#
# PURPOSE: Passive recon gaps are detectable in under 60 seconds by running this script.
# Self-reported "complete" without machine verification has caused missed findings.
# This script makes "complete" a machine-verified state, not a self-assessment.
#
# USAGE:
#   export ENGAGEMENT_DIR=/home/kali/engagements/<org>-passive-recon
#   bash scripts/99_self_audit.sh
#
# EXIT CODE: 0 = all checks passed. Non-zero = one or more checks FAILED.
# The agent MUST NOT declare the engagement complete until exit code is 0.
#
# METHODOLOGY: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md
# Every check maps to a known passive-recon failure mode documented in LESSONS_LEARNED.md.

set -uo pipefail
: "${ENGAGEMENT_DIR:?Set ENGAGEMENT_DIR first. Example: export ENGAGEMENT_DIR=/home/kali/engagements/org-date}"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0
WARN=0
ISSUES=()

_pass() { echo -e "${GRN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); ISSUES+=("FAIL: $1"); }
_warn() { echo -e "${YLW}[WARN]${NC} $1"; WARN=$((WARN+1)); ISSUES+=("WARN: $1"); }
_head() { echo -e "\n${BOLD}${BLU}══ $1 ══${NC}"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   FireCompass Passive Recon — Self-Audit Gate        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo "Engagement dir: $ENGAGEMENT_DIR"
echo "Timestamp:      $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 1: Engagement Directory Structure"
# ─────────────────────────────────────────────────────────────────────────────

for DIR in seeds subdomains resolved ips; do
    if [ -d "$ENGAGEMENT_DIR/$DIR" ]; then
        _pass "Directory exists: $DIR/"
    else
        _fail "Directory missing: $DIR/ — phase scripts may not have run"
    fi
done

for FILE in engagement_logs.md; do
    if [ -f "$ENGAGEMENT_DIR/$FILE" ]; then
        LINES=$(wc -l < "$ENGAGEMENT_DIR/$FILE")
        if [ "$LINES" -gt 20 ]; then
            _pass "$FILE exists ($LINES lines)"
        else
            _warn "$FILE exists but only $LINES lines — likely incomplete logging"
        fi
    else
        _fail "$FILE missing — engagement logging was not running"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 2: Seed Roots Coverage"
# ─────────────────────────────────────────────────────────────────────────────

SEED_FILE="$ENGAGEMENT_DIR/seeds/seed_roots.txt"
if [ ! -f "$SEED_FILE" ]; then
    _fail "seeds/seed_roots.txt missing — Phase 1 did not run"
else
    SEED_COUNT=$(wc -l < "$SEED_FILE")
    _pass "seeds/seed_roots.txt exists ($SEED_COUNT roots)"

    # Check: every root that appears in any subdomain source must be in seed_roots
    # If we found subdomains for related.example.com but seed_roots only has example.com,
    # the related-domain enumeration loop was incomplete.
    ALL_ROOTS_FOUND=$(find "$ENGAGEMENT_DIR/subdomains/" -mindepth 1 -maxdepth 1 -type d \
        | xargs -I{} basename {} 2>/dev/null | sort -u)

    for ROOT in $ALL_ROOTS_FOUND; do
        if grep -qx "$ROOT" "$SEED_FILE" 2>/dev/null; then
            _pass "Subdomain root $ROOT is in seed_roots.txt"
        else
            _fail "Subdomain root $ROOT has an enumeration folder but is NOT in seed_roots.txt — enumeration ran but root was not seeded. Were all related domains captured?"
        fi
    done

    # Reverse: every root in seed_roots must have a subdomain folder
    while IFS= read -r ROOT; do
        [ -z "$ROOT" ] && continue
        if [ -d "$ENGAGEMENT_DIR/subdomains/$ROOT" ]; then
            _pass "seed_roots root $ROOT has subdomain folder"
        else
            _fail "seed_roots root $ROOT has NO subdomain folder — Phase 3 was never run on this root"
        fi
    done < "$SEED_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 3: Per-Source File Audit (0-result diagnosis)"
# ─────────────────────────────────────────────────────────────────────────────
# Failure mode: crtsh.txt was 0 (rate-limited), otx.txt was 0, anubis.txt was 0
# — none were diagnosed. A 0-result file is only acceptable if the REASON is
# documented in decision_log.md.

SOURCES=(subfinder assetfinder crtsh rapiddns urlscan wayback otx anubis hackertarget)

while IFS= read -r ROOT; do
    [ -z "$ROOT" ] && continue
    echo ""
    echo "  Root: $ROOT"
    ROOT_DIR="$ENGAGEMENT_DIR/subdomains/$ROOT"

    if [ ! -d "$ROOT_DIR" ]; then
        _fail "$ROOT — subdomain directory does not exist"
        continue
    fi

    for SRC in "${SOURCES[@]}"; do
        SRC_FILE="$ROOT_DIR/${SRC}.txt"
        if [ ! -f "$SRC_FILE" ]; then
            _warn "$ROOT/$SRC.txt — file does not exist (source never queried)"
        else
            COUNT=$(wc -l < "$SRC_FILE" | tr -d ' ')
            if [ "$COUNT" -eq 0 ]; then
                # Zero is only acceptable if documented in decision_log.md
                DECISION_LOG="$ENGAGEMENT_DIR/reports/decision_log.md"
                if [ -f "$DECISION_LOG" ] && grep -qi "$SRC.*zero\|$SRC.*empty\|$SRC.*rate.limit\|$SRC.*0 result\|$SRC.*wildcard" "$DECISION_LOG" 2>/dev/null; then
                    _warn "$ROOT/$SRC.txt — 0 results (documented in decision_log.md — acceptable)"
                else
                    _fail "$ROOT/$SRC.txt — 0 results AND no diagnosis in decision_log.md. Was it rate-limited? Did it silently fail? This MUST be investigated before reporting complete."
                fi
            else
                _pass "$ROOT/$SRC.txt — $COUNT results"
            fi
        fi
    done

done < "$SEED_FILE"

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 4: all_master.txt vs Individual Sources"
# ─────────────────────────────────────────────────────────────────────────────
# This catches the case where a subdomain appears in one per-source file but not
# in all_master.txt — happens when the dedup/merge step ran before a source completed.

MASTER="$ENGAGEMENT_DIR/subdomains/all_master.txt"
if [ ! -f "$MASTER" ]; then
    _fail "subdomains/all_master.txt missing — merge was never run"
else
    MASTER_COUNT=$(wc -l < "$MASTER")
    _pass "all_master.txt exists ($MASTER_COUNT entries)"

    # Check: every entry in every per-root source file must be in master
    # (unless it's a domain outside the target org, which is a false positive from passive sources)
    MISSING_FROM_MASTER=0

    while IFS= read -r ROOT; do
        [ -z "$ROOT" ] && continue
        ROOT_DIR="$ENGAGEMENT_DIR/subdomains/$ROOT"
        [ ! -d "$ROOT_DIR" ] && continue

        for SRC_FILE in "$ROOT_DIR"/*.txt; do
            [ ! -f "$SRC_FILE" ] && continue
            while IFS= read -r ENTRY; do
                [ -z "$ENTRY" ] && continue
                # Normalise: strip wildcards, lowercase
                NORM=$(echo "$ENTRY" | sed 's/^\*\.//' | tr '[:upper:]' '[:lower:]' | tr -d '\r')
                # Only check entries that are actually subdomains of a known root
                if echo "$NORM" | grep -q "\.$ROOT$\|^$ROOT$"; then
                    if ! grep -qx "$NORM" "$MASTER" 2>/dev/null; then
                        echo -e "  ${RED}[MISSING]${NC} $NORM (from $(basename $SRC_FILE)) not in all_master.txt"
                        MISSING_FROM_MASTER=$((MISSING_FROM_MASTER+1))
                    fi
                fi
            done < "$SRC_FILE"
        done

    done < "$SEED_FILE"

    if [ "$MISSING_FROM_MASTER" -eq 0 ]; then
        _pass "all_master.txt is a superset of all per-root source files"
    else
        _fail "all_master.txt is MISSING $MISSING_FROM_MASTER entries that appear in per-source files. Re-run the merge: cat subdomains/*/all_unique.txt | sort -u > subdomains/all_master.txt"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 5: DNS Resolution Was Run"
# ─────────────────────────────────────────────────────────────────────────────

RESOLVED="$ENGAGEMENT_DIR/resolved/resolved_hosts.txt"
if [ ! -f "$RESOLVED" ]; then
    _fail "resolved/resolved_hosts.txt missing — Phase 7 DNS resolution did not run"
else
    RESOLVED_COUNT=$(wc -l < "$RESOLVED")
    MASTER_COUNT=$(wc -l < "$MASTER" 2>/dev/null || echo 0)
    if [ "$MASTER_COUNT" -gt 0 ]; then
        RATIO=$((RESOLVED_COUNT * 100 / MASTER_COUNT))
        if [ "$RATIO" -lt 10 ] && [ "$MASTER_COUNT" -gt 10 ]; then
            _warn "Only $RESOLVED_COUNT/$MASTER_COUNT candidates resolved ($RATIO%). Very low. Either most are historical (acceptable) or DNS resolution was incomplete."
        else
            _pass "DNS resolution: $RESOLVED_COUNT/$MASTER_COUNT resolved ($RATIO%)"
        fi
    fi
fi

# Check: resolved IPs file
RESOLVED_IPS="$ENGAGEMENT_DIR/resolved/resolved_ips.txt"
if [ ! -f "$RESOLVED_IPS" ] || [ ! -s "$RESOLVED_IPS" ]; then
    _fail "resolved/resolved_ips.txt missing or empty — IP extraction did not run"
else
    _pass "resolved_ips.txt exists ($(wc -l < $RESOLVED_IPS) IPs)"
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 6: Wildcard Cert Check Was Run"
# ─────────────────────────────────────────────────────────────────────────────
# The #1 failure mode (LESSONS_LEARNED.md #1)

WILDCARD_FILE="$ENGAGEMENT_DIR/seeds/wildcard_roots.txt"
if [ ! -f "$WILDCARD_FILE" ]; then
    _fail "seeds/wildcard_roots.txt missing — Phase 2 wildcard cert check never ran. This is CRITICAL. CT-log tools return 0 silently on wildcard domains. Run: bash scripts/02_wildcard_check.sh"
else
    WC_COUNT=$(wc -l < "$WILDCARD_FILE")
    if [ "$WC_COUNT" -eq 0 ]; then
        _pass "Wildcard check ran, no wildcard certs detected (empty file = checked and clean)"
    else
        echo -e "  ${YLW}Wildcard roots detected:${NC}"
        cat "$WILDCARD_FILE" | while read R; do echo "    - $R"; done
        # Check that pattern permutation ran for each wildcard root
        PERMUTATION_LOG=$(find "$ENGAGEMENT_DIR" -name "*permut*" -o -name "*pattern*" 2>/dev/null | head -1)
        if [ -n "$PERMUTATION_LOG" ]; then
            _pass "Wildcard cert(s) detected AND pattern permutation files found"
        else
            _fail "Wildcard cert(s) detected but NO pattern permutation output found. Phase 8 must run on every wildcard root before reporting complete."
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 7: Related Domain Enumeration Completeness"
# ─────────────────────────────────────────────────────────────────────────────
# Related domains found in Phase 1 (brand variants, subsidiaries) must have the
# same subdomain enumeration depth as the primary domain — not skipped or partial.

if [ -f "$SEED_FILE" ]; then
    PRIMARY_DOMAIN=$(head -1 "$SEED_FILE")
    RELATED_COUNT=$(($(wc -l < "$SEED_FILE") - 1))

    if [ "$RELATED_COUNT" -eq 0 ]; then
        _warn "Only 1 root in seed_roots.txt (the primary domain). Did Phase 1 related-domain discovery actually run? For most orgs, there are sister TLDs, regional variants, or subsidiary domains. If genuinely none exist, document this in decision_log.md."
    else
        _pass "$RELATED_COUNT related domains in seed_roots.txt (beyond primary)"

        # For each related domain root: check subdomain enumeration was run with the SAME sources as the primary
        PRIMARY_SOURCES=$(ls "$ENGAGEMENT_DIR/subdomains/$PRIMARY_DOMAIN/" 2>/dev/null | sort)
        while IFS= read -r ROOT; do
            [ -z "$ROOT" ] || [ "$ROOT" = "$PRIMARY_DOMAIN" ] && continue
            ROOT_DIR="$ENGAGEMENT_DIR/subdomains/$ROOT"
            if [ ! -d "$ROOT_DIR" ]; then
                _fail "Related domain $ROOT has NO subdomain enumeration folder. Phase 3 was not run on this root."
                continue
            fi
            RELATED_SOURCES=$(ls "$ROOT_DIR/" 2>/dev/null | sort)
            MISSING_SOURCES=$(comm -23 <(echo "$PRIMARY_SOURCES") <(echo "$RELATED_SOURCES") | grep -v "^all_unique")
            if [ -n "$MISSING_SOURCES" ]; then
                _warn "Related domain $ROOT missing some source files vs primary: $(echo $MISSING_SOURCES | tr '\n' ' '). Partial enumeration."
            else
                _pass "Related domain $ROOT has matching source coverage"
            fi
        done < "$SEED_FILE"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 8: GitHub / Cloud / Creds Phase Outputs"
# ─────────────────────────────────────────────────────────────────────────────

for PHASE_DIR in github leaks cloud; do
    if [ -d "$ENGAGEMENT_DIR/$PHASE_DIR" ]; then
        FILE_COUNT=$(find "$ENGAGEMENT_DIR/$PHASE_DIR" -type f | wc -l)
        if [ "$FILE_COUNT" -eq 0 ]; then
            _warn "$PHASE_DIR/ directory empty — phase either did not run or produced zero output. Must be documented in decision_log.md."
        else
            _pass "$PHASE_DIR/ has $FILE_COUNT output files"
        fi
    else
        _warn "$PHASE_DIR/ directory missing — phase did not run"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 9: Final Report Exists and Has Minimum Content"
# ─────────────────────────────────────────────────────────────────────────────

PRIMARY_DOMAIN=$(head -1 "$SEED_FILE" 2>/dev/null | awk -F'.' '{print $1}')
REPORT=$(find "$ENGAGEMENT_DIR" -maxdepth 1 -name "passive-recon-output-*.md" | head -1)

if [ -z "$REPORT" ]; then
    _fail "passive-recon-output-*.md not found in engagement root — 99_generate_report.py has not run"
else
    REPORT_LINES=$(wc -l < "$REPORT")
    if [ "$REPORT_LINES" -lt 100 ]; then
        _fail "Report exists but only $REPORT_LINES lines — suspiciously short. Expected 200+ lines for a complete engagement."
    else
        _pass "Report found: $(basename $REPORT) ($REPORT_LINES lines)"
    fi

    # Check required sections exist
    for SECTION in "Executive Summary\|executive summary" "Subdomain\|subdomain" "DNS Records\|dns records" "IP.*ASN\|ip.*asn" "Risk.*Finding\|finding"; do
        if grep -qi "$SECTION" "$REPORT"; then
            _pass "Report contains section: $(echo $SECTION | cut -d'\\' -f1)"
        else
            _warn "Report may be missing section: $(echo $SECTION | cut -d'\\' -f1)"
        fi
    done
fi

# ─────────────────────────────────────────────────────────────────────────────
_head "CHECK GROUP 10: Decision Log / Self-Critique Exists"
# ─────────────────────────────────────────────────────────────────────────────

DECISION_LOG="$ENGAGEMENT_DIR/reports/decision_log.md"
if [ ! -f "$DECISION_LOG" ]; then
    _warn "reports/decision_log.md missing — phase-by-phase reasoning was not recorded. This makes the work unauditable."
else
    DL_LINES=$(wc -l < "$DECISION_LOG")
    _pass "decision_log.md exists ($DL_LINES lines)"
    # Must contain self-critique sections
    if grep -qi "What an Expert\|Self-critique\|What I Ruled Out\|Expert Would" "$DECISION_LOG"; then
        _pass "decision_log.md contains self-critique sections"
    else
        _warn "decision_log.md does not contain 'What an Expert Would Also Do' self-critique sections"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# FINAL VERDICT
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}SELF-AUDIT RESULT${NC}"
echo -e "  ${GRN}PASS:${NC} $PASS"
echo -e "  ${YLW}WARN:${NC} $WARN"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo ""

if [ ${#ISSUES[@]} -gt 0 ]; then
    echo -e "${BOLD}Issues to resolve:${NC}"
    for ISSUE in "${ISSUES[@]}"; do
        echo "  - $ISSUE"
    done
    echo ""
fi

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}${BOLD}VERDICT: BLOCKED — $FAIL check(s) FAILED.${NC}"
    echo -e "${RED}DO NOT declare engagement complete. Fix the above FAIL items and re-run this script.${NC}"
    echo ""
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YLW}${BOLD}VERDICT: PASS WITH WARNINGS — $WARN item(s) require documentation.${NC}"
    echo -e "${YLW}Each WARN must appear in decision_log.md before the final report is delivered.${NC}"
    echo ""
    exit 0
else
    echo -e "${GRN}${BOLD}VERDICT: ALL CHECKS PASSED ✓${NC}"
    echo -e "${GRN}Engagement is verified complete. Proceed to final report.${NC}"
    echo ""
    exit 0
fi
