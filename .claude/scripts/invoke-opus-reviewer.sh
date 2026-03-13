#!/usr/bin/env bash
set -uo pipefail

# Invokes the Opus reviewer as a completely isolated process
# Reads: .claude/tmp/review-payload.md
# Writes: .claude/tmp/opus-review-[timestamp].md
# Exit 0 = APPROVED, Exit 2 = CHANGES REQUIRED

PAYLOAD_FILE=".claude/tmp/review-payload.md"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
REVIEW_OUTPUT=".claude/tmp/opus-review-${TIMESTAMP}.md"

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
echo "Invoking Opus reviewer with isolated context..."
echo "Payload: $PAYLOAD_FILE ($(wc -l < "$PAYLOAD_FILE") lines)"
echo ""

# Invoke Opus as a completely fresh, isolated process
# No --continue, no --resume, no session flags
# Opus receives ONLY: its system prompt + the review payload
SYSTEM_PROMPT=$(cat .claude/reviewers/opus-system-prompt.md 2>/dev/null || echo "You are an expert code reviewer. Review the code changes and provide a gate decision.")

# Unset CLAUDECODE so claude -p can run from inside a Claude Code session
# (-p is print/pipe mode — non-interactive, safe to run as a subprocess)
unset CLAUDECODE 2>/dev/null || true

PROMPT_FILE=$(mktemp)
printf 'Please review the following code changes:\n\n%s' "$(cat "$PAYLOAD_FILE")" > "$PROMPT_FILE"

REVIEW_RESULT=$(claude -p \
    --model claude-opus-4-6 \
    --system-prompt "$SYSTEM_PROMPT" \
    --allowedTools "Read,Glob,Grep,Bash" \
    < "$PROMPT_FILE" 2>&1)
CLAUDE_EXIT=$?
rm -f "$PROMPT_FILE"

if [[ $CLAUDE_EXIT -ne 0 ]]; then
    echo "WARNING: claude command exited with code $CLAUDE_EXIT" >&2
    echo "$REVIEW_RESULT" > "$REVIEW_OUTPUT"
    echo "$REVIEW_RESULT"
    exit 1
fi

# Save the full review output
echo "$REVIEW_RESULT" > "$REVIEW_OUTPUT"

# Print the full review to stdout (appears in pipeline log)
echo "$REVIEW_RESULT"
echo ""
echo "Review saved to: $REVIEW_OUTPUT"

# Parse the Gate decision
GATE_DECISION=""
if echo "$REVIEW_RESULT" | grep -qiE 'Gate:[[:space:]]*(APPROVED WITH CONDITIONS|APPROVED)'; then
    GATE_DECISION="APPROVED"
elif echo "$REVIEW_RESULT" | grep -qiE 'Gate:[[:space:]]*CHANGES[[:space:]]*REQUIRED'; then
    GATE_DECISION="CHANGES_REQUIRED"
fi

# Parse blocker count
BLOCKER_COUNT=$(echo "$REVIEW_RESULT" | grep -ioE 'Blockers:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1; true)

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " REVIEW RESULT"
echo "═══════════════════════════════════════════════════════════"
echo " Gate decision: ${GATE_DECISION:-UNKNOWN}"
echo " Blocker count: ${BLOCKER_COUNT:-UNKNOWN}"
echo "═══════════════════════════════════════════════════════════"

# Gate: exit 2 if changes required or blockers found
if [[ "$GATE_DECISION" == "CHANGES_REQUIRED" ]]; then
    echo ""
    echo "OPUS REVIEW: CHANGES REQUIRED — blocking issues must be resolved." >&2
    exit 2
fi

if [[ -n "$BLOCKER_COUNT" && "$BLOCKER_COUNT" -gt 0 ]]; then
    echo ""
    echo "OPUS REVIEW: $BLOCKER_COUNT blocking issue(s) found — must be resolved." >&2
    exit 2
fi

if [[ -z "$GATE_DECISION" ]]; then
    echo ""
    echo "WARNING: Could not parse gate decision from Opus review output." >&2
    echo "Manual review of $REVIEW_OUTPUT is recommended." >&2
    exit 1
fi

echo ""
echo "OPUS REVIEW: APPROVED"
exit 0
