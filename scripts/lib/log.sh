#!/bin/bash
# lib/log.sh — engagement_logs.md writer
# Source this in every phase script: source "$(dirname "$0")/lib/log.sh"
#
# Why this exists:
#   Claude conversations get compacted. Every explanation Claude wrote, every
#   command that ran, every line of output, every decision — all of it visible
#   in the CLI — disappears from context when compaction happens.
#   engagement_logs.md is the permanent on-disk record. The analyst can open
#   it at any time and read it like a full session transcript with no gaps.
#
# This file handles the SHELL LAYER of that log — the structured entries from
# bash/python phase scripts. The AGENT LAYER (Claude's own reasoning text,
# tool call results, interpretations) is written by the agent directly using
# log_agent_response() and log_cmd_with_output().
#
# Two-layer architecture:
#   Shell layer  → log_phase_start, log_hypothesis, log_finding, log_stats, etc.
#   Agent layer  → log_agent_response, log_cmd_with_output, log_read_result, log_checkpoint

ENGAGEMENT_LOG="${ENGAGEMENT_DIR}/engagement_logs.md"

_log_ts()    { date '+%Y-%m-%d %H:%M:%S'; }
_log_ts_hm() { date '+%H:%M:%S'; }

# ════════════════════════════════════════════════════════════════════════════
# SHELL LAYER — called from bash/python phase scripts
# ════════════════════════════════════════════════════════════════════════════

# ── log_phase_start <phase_id> <phase_name> ──────────────────────────────────
log_phase_start() {
    local PHASE_ID="$1"
    local PHASE_NAME="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF

---

## Phase ${PHASE_ID} — ${PHASE_NAME}

**Timestamp:** $(_log_ts)
**Script:** $(basename "$0")

EOF
}

# ── log_hypothesis <hypothesis> <action> <falsifier> ────────────────────────
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
    local PREFIX
    case "$SEVERITY" in
        CRITICAL) PREFIX="🔴 **[CRITICAL]**" ;;
        HIGH)     PREFIX="🟠 **[HIGH]**" ;;
        NOTABLE)  PREFIX="🟡 **[NOTABLE]**" ;;
        *)        PREFIX="ℹ️  [INFO]" ;;
    esac
    echo "- \`$(_log_ts_hm)\` ${PREFIX} ${TEXT}" >> "$ENGAGEMENT_LOG"
}

# ── log_command <description> <command_string> ───────────────────────────────
# Log a command about to be run (call BEFORE running).
log_command() {
    local DESC="$1"
    local CMD="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF

### ⚡ Command — $(_log_ts)
**Purpose:** ${DESC}
\`\`\`bash
${CMD}
\`\`\`
EOF
}

# ── log_output_file <label> <filepath> ──────────────────────────────────────
# Log the contents of an output file after a command runs (first 200 lines).
log_output_file() {
    local LABEL="$1"
    local FILEPATH="$2"
    local LINE_COUNT=0
    [ -f "$FILEPATH" ] && LINE_COUNT=$(wc -l < "$FILEPATH")
    cat >> "$ENGAGEMENT_LOG" <<EOF
**Output — ${LABEL}** (${LINE_COUNT} lines total):
\`\`\`
EOF
    if [ -f "$FILEPATH" ] && [ "$LINE_COUNT" -gt 0 ]; then
        head -200 "$FILEPATH" >> "$ENGAGEMENT_LOG"
        [ "$LINE_COUNT" -gt 200 ] && echo "... [truncated at 200 — full output: ${FILEPATH}]" >> "$ENGAGEMENT_LOG"
    else
        echo "(empty — zero results)" >> "$ENGAGEMENT_LOG"
    fi
    echo '```' >> "$ENGAGEMENT_LOG"
    echo "" >> "$ENGAGEMENT_LOG"
}

# ── log_output_block <label> <content_string> ────────────────────────────────
# Log an inline output string (not a file). Use for short captured outputs.
log_output_block() {
    local LABEL="$1"
    local CONTENT="$2"
    local LINE_COUNT
    LINE_COUNT=$(echo "$CONTENT" | wc -l)
    cat >> "$ENGAGEMENT_LOG" <<EOF
**Output — ${LABEL}** (${LINE_COUNT} lines):
\`\`\`
$(echo "$CONTENT" | head -200)
$([ "$LINE_COUNT" -gt 200 ] && echo "... [truncated]")
\`\`\`
EOF
    echo "" >> "$ENGAGEMENT_LOG"
}

# ── log_stats <label> <key:value pairs...> ───────────────────────────────────
# Usage: log_stats "Phase 3 results" "subfinder:89" "crt.sh:142" "total:183"
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

# ── log_decision <decision> <rationale> ──────────────────────────────────────
log_decision() {
    local DECISION="$1"
    local RATIONALE="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF
> **Decision:** ${DECISION}
> **Rationale:** ${RATIONALE}

EOF
}

# ── log_phase_end <phase_id> <summary> ───────────────────────────────────────
log_phase_end() {
    local PHASE_ID="$1"
    local SUMMARY="$2"
    cat >> "$ENGAGEMENT_LOG" <<EOF

**Phase ${PHASE_ID} complete — $(_log_ts)**
${SUMMARY}

EOF
}

# ════════════════════════════════════════════════════════════════════════════
# AGENT LAYER — called by the Claude agent to capture everything it says/does
# These are the entries that make the log a full CLI transcript.
# ════════════════════════════════════════════════════════════════════════════

# ── log_agent_response <text> ────────────────────────────────────────────────
# THE MOST IMPORTANT FUNCTION.
# Call this after EVERY response Claude writes to the analyst.
# Paste the full response text verbatim — not a summary.
# This is what makes the log readable as a session transcript.
#
# Usage:
#   log_agent_response "Phase 2 found a wildcard cert on acme-internal.com.
#   This means crt.sh and all CT-log tools are blind to individual subdomains
#   on this domain. The 0 results from subfinder for acme-internal.com confirm
#   this — it is not a gap in methodology, it is the expected behaviour.
#   I am pivoting to Phase 8 pattern permutation on acme-internal.com now."
#
log_agent_response() {
    local TEXT="$1"
    cat >> "$ENGAGEMENT_LOG" <<EOF

---
### 🤖 Agent — $(_log_ts)

${TEXT}

EOF
}

# ── log_cmd_with_output <purpose> <command> <output> ─────────────────────────
# Log a command + its full output together as a single block.
# Use this for commands the agent runs directly (not via phase scripts).
# <output> = the captured stdout from the Bash tool result.
#
# Usage:
#   OUTPUT=$(cat $ENGAGEMENT_DIR/subdomains/subfinder.txt)
#   log_cmd_with_output \
#     "subfinder passive enum — Phase 3" \
#     "subfinder -d acme.com -all -silent" \
#     "$OUTPUT"
#
log_cmd_with_output() {
    local PURPOSE="$1"
    local CMD="$2"
    local OUTPUT="$3"
    local LINE_COUNT
    LINE_COUNT=$(echo "$OUTPUT" | wc -l)
    cat >> "$ENGAGEMENT_LOG" <<EOF

---
### ⚡ Command — $(_log_ts)
**Purpose:** ${PURPOSE}
\`\`\`bash
${CMD}
\`\`\`
**Output** (${LINE_COUNT} lines):
\`\`\`
$(echo "$OUTPUT" | head -200)
$([ "$LINE_COUNT" -gt 200 ] && echo "... [truncated at 200 lines — full output in engagement dir]")
\`\`\`

EOF
    # Auto-log if empty
    if [ -z "$OUTPUT" ] || [ "$LINE_COUNT" -eq 0 ]; then
        echo "**Note:** Zero output returned. This is information — document interpretation above." >> "$ENGAGEMENT_LOG"
        echo "" >> "$ENGAGEMENT_LOG"
    fi
}

# ── log_read_result <filepath> <key_observations> ────────────────────────────
# Log when Claude reads a file and what it observed.
# <key_observations> = what the content told you — the interpretation, not just a count.
#
# Usage:
#   log_read_result \
#     "$ENGAGEMENT_DIR/subdomains/all_master.txt" \
#     "183 unique subdomains. Notable: dev, staging, vpn, mail present.
#      No api.* — unusual for this org size, worth checking Phase 4 JS mining.
#      acme-internal.com shows 0 entries — wildcard blindness confirmed."
#
log_read_result() {
    local FILEPATH="$1"
    local OBSERVATIONS="$2"
    local LINE_COUNT=0
    [ -f "$FILEPATH" ] && LINE_COUNT=$(wc -l < "$FILEPATH")
    cat >> "$ENGAGEMENT_LOG" <<EOF

---
### 📄 Read — $(_log_ts)
**File:** ${FILEPATH} (${LINE_COUNT} lines)
**Key observations:**
${OBSERVATIONS}

EOF
}

# ── log_checkpoint <number> <presented_to_analyst> <analyst_response> <decision> ──
# Log every supervised checkpoint — what was shown, what the analyst said, what was decided.
#
log_checkpoint() {
    local NUM="$1"
    local PRESENTED="$2"
    local ANALYST_RESPONSE="$3"
    local DECISION="$4"
    cat >> "$ENGAGEMENT_LOG" <<EOF

---
### 🛑 Checkpoint ${NUM} — $(_log_ts)

**Presented to analyst:**
${PRESENTED}

**Analyst response:**
${ANALYST_RESPONSE}

**Decision / next action:**
${DECISION}

EOF
}
