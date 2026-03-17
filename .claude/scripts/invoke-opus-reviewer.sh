#!/usr/bin/env bash
set -uo pipefail

# Invokes the Opus reviewer as a completely isolated process
# Reads: .claude/tmp/review-payload.md
# Writes: .claude/tmp/opus-review-[timestamp].md
# Exit 0 = APPROVED, Exit 2 = CHANGES REQUIRED

PAYLOAD_FILE=".claude/tmp/review-payload.md"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
REVIEW_OUTPUT=".claude/tmp/opus-review-${TIMESTAMP}.md"
TIMEOUT_SECS="${OPUS_TIMEOUT:-300}"

# Verify payload exists
if [[ ! -f "$PAYLOAD_FILE" ]]; then
    echo "ERROR: Review payload not found at $PAYLOAD_FILE" >&2
    echo "Run build-review-payload.sh first." >&2
    exit 1
fi

# Verify claude CLI is available
if ! command -v claude &>/dev/null; then
    echo "ERROR: claude CLI not found. Install Claude Code to run the Opus reviewer." >&2
    exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo " OPUS CODE REVIEW — $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Payload: $PAYLOAD_FILE ($(wc -l < "$PAYLOAD_FILE") lines)"
echo "Timeout: ${TIMEOUT_SECS}s"
echo ""

# Build system prompt
SYSTEM_PROMPT=$(cat .claude/reviewers/opus-system-prompt.md 2>/dev/null || echo "You are an expert code reviewer. Review the code changes and provide a gate decision.")

# Unset CLAUDECODE so claude -p can run from inside a Claude Code session
unset CLAUDECODE 2>/dev/null || true

PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT
cat > "$PROMPT_FILE" << 'PROMPT_HEADER'
Please review the following code changes.

IMPORTANT: At the end of your review, include a machine-parseable gate decision line in this exact format:
<!-- GATE: APPROVED -->
or
<!-- GATE: CHANGES_REQUIRED, BLOCKERS: <number> -->

This line must appear on its own line at the end of your review.

PROMPT_HEADER
cat "$PAYLOAD_FILE" >> "$PROMPT_FILE"

# Build allowed tools argument — only add if claude supports it
TOOLS_ARG=""
if claude --help 2>&1 | grep -q -- '--allowedTools\|--allowed-tools'; then
    TOOLS_ARG="--allowedTools Read,Glob,Grep,Bash"
fi

if command -v timeout &>/dev/null; then
    REVIEW_RESULT=$(timeout "$TIMEOUT_SECS" claude -p \
        --model claude-opus-4-6 \
        --system-prompt "$SYSTEM_PROMPT" \
        $TOOLS_ARG \
        < "$PROMPT_FILE" 2>&1)
else
    REVIEW_RESULT=$(claude -p \
        --model claude-opus-4-6 \
        --system-prompt "$SYSTEM_PROMPT" \
        $TOOLS_ARG \
        < "$PROMPT_FILE" 2>&1)
fi
CLAUDE_EXIT=$?

if [[ $CLAUDE_EXIT -eq 124 ]]; then
    echo "WARNING: Opus review timed out after ${TIMEOUT_SECS}s" >&2
    echo "Timeout after ${TIMEOUT_SECS}s" > "$REVIEW_OUTPUT"
    exit 1
fi

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "WARNING: claude command exited with code $CLAUDE_EXIT" >&2
    echo "$REVIEW_RESULT" > "$REVIEW_OUTPUT"
    echo "$REVIEW_RESULT"
    exit 1
fi

# Save and display review
echo "$REVIEW_RESULT" > "$REVIEW_OUTPUT"
echo "$REVIEW_RESULT"
echo ""
echo "Review saved to: $REVIEW_OUTPUT"

# Parse gate decision — structured format first, then regex fallback
GATE_DECISION=""

# Try structured HTML comment format first (machine-parseable)
if echo "$REVIEW_RESULT" | grep -qE '<!--\s*GATE:\s*APPROVED\s*-->'; then
    GATE_DECISION="APPROVED"
elif echo "$REVIEW_RESULT" | grep -qE '<!--\s*GATE:\s*CHANGES_REQUIRED'; then
    GATE_DECISION="CHANGES_REQUIRED"
fi

# Fallback to original regex parsing
if [[ -z "$GATE_DECISION" ]]; then
    if echo "$REVIEW_RESULT" | grep -qiE 'Gate:[[:space:]]*(APPROVED WITH CONDITIONS|APPROVED)'; then
        GATE_DECISION="APPROVED"
    elif echo "$REVIEW_RESULT" | grep -qiE 'Gate:[[:space:]]*CHANGES[[:space:]]*REQUIRED'; then
        GATE_DECISION="CHANGES_REQUIRED"
    fi
fi

BLOCKER_COUNT=$(echo "$REVIEW_RESULT" | grep -ioE 'BLOCKERS:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
if [[ -z "$BLOCKER_COUNT" ]]; then
    BLOCKER_COUNT=$(echo "$REVIEW_RESULT" | grep -ioE 'Blockers:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Gate: ${GATE_DECISION:-UNKNOWN} | Blockers: ${BLOCKER_COUNT:-0}"
echo "═══════════════════════════════════════════════════════════"

if [[ "$GATE_DECISION" == "CHANGES_REQUIRED" ]]; then
    echo "OPUS REVIEW: CHANGES REQUIRED" >&2
    exit 2
fi

if [[ -n "$BLOCKER_COUNT" && "$BLOCKER_COUNT" -gt 0 ]]; then
    echo "OPUS REVIEW: $BLOCKER_COUNT blocker(s) found" >&2
    exit 2
fi

# Fail-safe: if we can't parse the decision, default to CHANGES_REQUIRED
if [[ -z "$GATE_DECISION" ]]; then
    echo "WARNING: Could not parse gate decision — defaulting to CHANGES REQUIRED (fail-safe)." >&2
    exit 2
fi

echo "OPUS REVIEW: APPROVED"
exit 0
