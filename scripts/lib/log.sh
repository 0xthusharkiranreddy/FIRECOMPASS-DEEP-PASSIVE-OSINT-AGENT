#!/bin/bash
# lib/log.sh — engagement_logs.md writer
# Source this in every phase script: source "$(dirname "$0")/lib/log.sh"
#
# Why: Claude conversations get compacted — all agent reasoning, findings,
# and decisions visible in the terminal disappear from context. engagement_logs.md
# is the permanent on-disk record that survives compaction and can be reviewed
# at any point during or after the engagement.

# Path to the master engagement log
ENGAGEMENT_LOG="${ENGAGEMENT_DIR}/engagement_logs.md"

# ── log_phase_start <phase_id> <phase_name> ──────────────────────────────────
# Call at the top of each phase script to write the phase header + timestamp.
log_phase_start() {
    local PHASE_ID="$1"
    local PHASE_NAME="$2"
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    cat >> "$ENGAGEMENT_LOG" <<EOF

---

## Phase ${PHASE_ID} — ${PHASE_NAME}

**Timestamp:** ${TS}
**Script:** $(basename "$0")

EOF
}

# ── log_hypothesis <text> ────────────────────────────────────────────────────
# Write a Hypothesis / Action / Falsifier block before running a technique.
log_hypothesis() {
    local HYPOTHESIS="$1"
    local ACTION="$2"
    local FALSIFIER="$3"
    cat >> "$ENGAGEMENT_LOG" <<EOF
**Hypothesis:** ${HYPOTHESIS}
**Action:** ${ACTION}
**Falsifier:** ${FALSIFIER}

EOF
}

# ── log_finding <severity> <text> ───────────────────────────────────────────
# severity: INFO | NOTABLE | HIGH | CRITICAL
log_finding() {
    local SEVERITY="$1"
    shift
    local TEXT="$*"
    local TS
    TS=$(date '+%H:%M:%S')
    local PREFIX
    case "$SEVERITY" in
        CRITICAL) PREFIX="🔴 **[CRITICAL]**" ;;
        HIGH)     PREFIX="🟠 **[HIGH]**" ;;
        NOTABLE)  PREFIX="🟡 **[NOTABLE]**" ;;
        *)        PREFIX="ℹ️  [INFO]" ;;
    esac
    echo "- \`${TS}\` ${PREFIX} ${TEXT}" >> "$ENGAGEMENT_LOG"
}

# ── log_command <description> <command_string> ───────────────────────────────
# Log a command that was run with its purpose.
log_command() {
    local DESC="$1"
    local CMD="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF
**Running:** ${DESC}
\`\`\`bash
${CMD}
\`\`\`
EOF
}

# ── log_output_block <label> <content> ──────────────────────────────────────
# Log a block of output (first 50 lines if large).
log_output_block() {
    local LABEL="$1"
    local CONTENT="$2"
    local LINE_COUNT
    LINE_COUNT=$(echo "$CONTENT" | wc -l)
    local PREVIEW
    PREVIEW=$(echo "$CONTENT" | head -50)
    cat >> "$ENGAGEMENT_LOG" <<EOF
**Output — ${LABEL}** (${LINE_COUNT} lines):
\`\`\`
${PREVIEW}
$([ "$LINE_COUNT" -gt 50 ] && echo "... [truncated — see output file]")
\`\`\`
EOF
}

# ── log_stats <label> <value_pairs...> ──────────────────────────────────────
# Log phase summary statistics as a table row.
# Usage: log_stats "Phase 3 stats" "Subdomains found:89" "Sources queried:6"
log_stats() {
    local LABEL="$1"
    shift
    echo "" >> "$ENGAGEMENT_LOG"
    echo "**${LABEL}:**" >> "$ENGAGEMENT_LOG"
    for PAIR in "$@"; do
        local KEY="${PAIR%%:*}"
        local VAL="${PAIR#*:}"
        echo "- ${KEY}: \`${VAL}\`" >> "$ENGAGEMENT_LOG"
    done
    echo "" >> "$ENGAGEMENT_LOG"
}

# ── log_decision <decision> <rationale> ─────────────────────────────────────
# Log a decision point — why one approach was chosen over another.
log_decision() {
    local DECISION="$1"
    local RATIONALE="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF
> **Decision:** ${DECISION}
> **Rationale:** ${RATIONALE}

EOF
}

# ── log_phase_end <phase_id> <summary_line> ─────────────────────────────────
# Call at the bottom of each phase script to close out the section.
log_phase_end() {
    local PHASE_ID="$1"
    local SUMMARY="$2"
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    cat >> "$ENGAGEMENT_LOG" <<EOF

**Phase ${PHASE_ID} complete at ${TS}.**
${SUMMARY}

EOF
}
