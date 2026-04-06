#!/usr/bin/env bash
set -uo pipefail

# Builds the structured review payload that the Opus reviewer receives
# Output: .claude/tmp/review-payload.md

PAYLOAD_FILE=".claude/tmp/review-payload.md"
mkdir -p .claude/tmp

# Helper to safely include a file (truncated)
include_file() {
    local file="$1"
    local label="$2"
    local max_lines="${3:-100}"

    echo ""
    echo "## $label"
    echo ""

    if [[ -f "$file" ]]; then
        echo '```json'
        head -n "$max_lines" "$file"
        local total_lines
        total_lines=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ "$total_lines" -gt "$max_lines" ]]; then
            echo "... (truncated: $total_lines total lines, showing first $max_lines)"
        fi
        echo '```'
    else
        echo "*File not found: $file*"
    fi
}

# Start building the payload
{
    echo "# Code Review Payload"
    echo ""
    echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo ""

    # --- Changed files summary ---
    echo "## Changed Files Summary"
    echo ""
    echo '```'
    if git rev-parse HEAD~1 &>/dev/null; then
        git diff HEAD~1..HEAD --stat 2>/dev/null || echo "No git diff available"
    else
        git diff --stat 2>/dev/null || echo "No git diff available (initial commit or no changes)"
    fi
    echo '```'
    echo ""

    # --- Full diff ---
    echo "## Full Diff"
    echo ""
    echo '```diff'
    if git rev-parse HEAD~1 &>/dev/null; then
        git diff HEAD~1..HEAD 2>/dev/null || echo "No diff available"
    else
        git diff 2>/dev/null || echo "No diff available"
    fi
    echo '```'

    # --- Test results ---
    include_file ".claude/tmp/unit-results.json" "Unit Test Results" 100
    include_file ".claude/tmp/ui-results.json" "UI Test Results" 100
    include_file ".claude/tmp/integration-results.json" "Integration Test Results" 100

    # --- Performance results (optional) ---
    if [[ -f ".claude/tmp/k6-summary.json" ]]; then
        include_file ".claude/tmp/k6-summary.json" "Performance Results" 100
    fi

    # --- Coverage summary ---
    echo ""
    echo "## Coverage Summary"
    echo ""

    # Backend coverage
    if [[ -f ".claude/tmp/backend-coverage.json" ]]; then
        echo "### Backend Coverage"
        echo '```json'
        if command -v jq &>/dev/null; then
            jq '{
                total_statements: .totals.num_statements,
                covered_statements: .totals.covered_lines,
                missing_statements: .totals.missing_lines,
                line_coverage_pct: (.totals.percent_covered | round),
                excluded_lines: .totals.excluded_lines
            }' .claude/tmp/backend-coverage.json 2>/dev/null || head -20 .claude/tmp/backend-coverage.json
        else
            head -50 .claude/tmp/backend-coverage.json
        fi
        echo '```'
    elif [[ -f "backend/coverage.json" ]]; then
        echo "### Backend Coverage"
        echo '```json'
        head -50 backend/coverage.json
        echo '```'
    else
        echo "*No backend coverage data found.*"
    fi

    # Frontend coverage
    if [[ -f "frontend/coverage/coverage-summary.json" ]]; then
        echo ""
        echo "### Frontend Coverage"
        echo '```json'
        if command -v jq &>/dev/null; then
            jq '.total' frontend/coverage/coverage-summary.json 2>/dev/null || head -20 frontend/coverage/coverage-summary.json
        else
            head -50 frontend/coverage/coverage-summary.json
        fi
        echo '```'
    else
        echo ""
        echo "*No frontend coverage data found.*"
    fi

    # --- Enterprise feature context ---
    echo ""
    echo "## Enterprise Feature Context"
    echo ""

    # Include baseline decisions if available
    if [[ -f ".claude/BASELINE.md" ]]; then
        echo "### Approved Baseline Features"
        echo ""
        cat ".claude/BASELINE.md"
        echo ""
    fi

    # Include brief for audience context
    if [[ -f ".claude/brief.md" ]]; then
        echo "### App Brief (audience and scope)"
        echo ""
        # Extract just the key sections, not the whole brief
        head -30 ".claude/brief.md"
        echo ""
    fi

    # Summarize which Tier 1 checks passed/failed in the pipeline
    if [[ -f ".claude/tmp/tier1-results.json" ]]; then
        include_file ".claude/tmp/tier1-results.json" "Tier 1 Pipeline Results" 50
    fi

    # Include security scan results
    if [[ -f ".claude/tmp/security-output.txt" ]]; then
        echo ""
        echo "### Security Scan Results"
        echo ""
        echo '```'
        tail -30 ".claude/tmp/security-output.txt"
        echo '```'
    fi

    # Include lint results if available
    if [[ -f ".claude/tmp/backend-unit-output.txt" ]]; then
        echo ""
        echo "### Backend Test Output (last 30 lines)"
        echo ""
        echo '```'
        tail -30 ".claude/tmp/backend-unit-output.txt"
        echo '```'
    fi

} > "$PAYLOAD_FILE"

echo "Review payload written to $PAYLOAD_FILE"
echo "Payload size: $(wc -l < "$PAYLOAD_FILE") lines, $(wc -c < "$PAYLOAD_FILE" | tr -d ' ') bytes"
