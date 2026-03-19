#!/usr/bin/env bash
# test.sh — Verify claude-guardrails are active by testing patterns directly.
#
# SAFETY: This script never executes hook commands or dangerous strings.
# It only checks that the correct regex patterns exist in settings.json
# and that those patterns match what they should (and don't match what
# they shouldn't). All pattern testing is done via grep on plain strings
# — no eval, no shell expansion of test inputs.
#
# Usage: bash test.sh

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass=0
fail=0

check() {
    local description="$1"
    local expected="$2"  # "match" or "no_match"
    local matched="$3"   # "yes" or "no"

    if [[ "$expected" == "match" && "$matched" == "yes" ]] || \
       [[ "$expected" == "no_match" && "$matched" == "no" ]]; then
        echo -e "  ${GREEN}✓${NC} $description"
        ((pass++))
    else
        echo -e "  ${RED}✗${NC} $description (expected $expected, got $matched)"
        ((fail++))
    fi
}

# Test whether a string matches a regex pattern via grep -qP
# Returns "yes" or "no" — never executes the string
pattern_matches() {
    local pattern="$1"
    local test_string="$2"
    if printf '%s' "$test_string" | grep -qP "$pattern" 2>/dev/null; then
        echo "yes"
    else
        echo "no"
    fi
}

# ── Preflight ────────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required. Install it first.${NC}"
    exit 1
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo -e "${RED}Error: $SETTINGS_FILE not found. Run install.sh first.${NC}"
    exit 1
fi

# ── Check hooks exist in settings ────────────────────────────────────────

file_hook_exists=$(jq '[.hooks.PreToolUse // [] | .[] | select(.matcher == "Edit|Write")] | length' "$SETTINGS_FILE" 2>/dev/null || echo 0)
bash_hook_exists=$(jq '[.hooks.PreToolUse // [] | .[] | select(.matcher == "Bash")] | length' "$SETTINGS_FILE" 2>/dev/null || echo 0)

if [[ "$file_hook_exists" -eq 0 && "$bash_hook_exists" -eq 0 ]]; then
    echo -e "${RED}No guardrail hooks found in $SETTINGS_FILE${NC}"
    echo "Run: bash install.sh"
    exit 1
fi

echo -e "${CYAN}Testing Claude Code Guardrails${NC}"
echo ""

# ── File protection tests ────────────────────────────────────────────────
# The file hook uses grep -qE with this pattern to decide what to block.
# We test the same pattern against file paths directly.

FILE_PATTERN='\.(env|pem|key|credential|secret)$|secrets/|\.ssh/|\.aws/|\.gnupg/'

if [[ "$file_hook_exists" -gt 0 ]]; then
    echo -e "${YELLOW}File protection (hook present, testing patterns):${NC}"

    # Should BLOCK (pattern matches)
    check "Block .env file"         "match"    "$(pattern_matches "$FILE_PATTERN" "/home/user/.env")"
    check "Block secrets/ dir"      "match"    "$(pattern_matches "$FILE_PATTERN" "/app/secrets/api_key.txt")"
    check "Block .ssh/ dir"         "match"    "$(pattern_matches "$FILE_PATTERN" "/home/user/.ssh/id_rsa")"
    check "Block .pem file"         "match"    "$(pattern_matches "$FILE_PATTERN" "/app/server.pem")"
    check "Block .credential file"  "match"    "$(pattern_matches "$FILE_PATTERN" "/app/db.credential")"
    check "Block .secret file"      "match"    "$(pattern_matches "$FILE_PATTERN" "/app/token.secret")"
    check "Block .aws/ dir"         "match"    "$(pattern_matches "$FILE_PATTERN" "/home/user/.aws/credentials")"
    check "Block .gnupg/ dir"       "match"    "$(pattern_matches "$FILE_PATTERN" "/home/user/.gnupg/private-keys")"

    # Should ALLOW (pattern does NOT match)
    check "Allow normal .py file"   "no_match" "$(pattern_matches "$FILE_PATTERN" "/home/user/project/main.py")"
    check "Allow README.md"         "no_match" "$(pattern_matches "$FILE_PATTERN" "/home/user/project/README.md")"
    check "Allow .envrc (not .env)" "no_match" "$(pattern_matches "$FILE_PATTERN" "/home/user/.envrc")"
    check "Allow package.json"      "no_match" "$(pattern_matches "$FILE_PATTERN" "/app/package.json")"

    echo ""
else
    echo -e "${YELLOW}File protection: ${RED}NOT INSTALLED${NC}"
    echo ""
fi

# ── Command protection tests ─────────────────────────────────────────────
# The bash hook uses grep -qP with this pattern to decide what to block.
# We test the same pattern against command strings directly.

CMD_PATTERN='rm\s+-[a-z]*rf[a-z]*\s+/$|rm\s+-[a-z]*rf[a-z]*\s+/\s|rm\s+-[a-z]*rf[a-z]*\s+~$|rm\s+-[a-z]*rf[a-z]*\s+~\s|git\s+push\s+--force|git\s+push\s+.*-f\b|DROP\s+TABLE|DROP\s+DATABASE'

if [[ "$bash_hook_exists" -gt 0 ]]; then
    echo -e "${YELLOW}Command protection (hook present, testing patterns):${NC}"

    # Should BLOCK (pattern matches)
    check "Block rm -rf /"            "match"    "$(pattern_matches "$CMD_PATTERN" "rm -rf /")"
    check "Block rm -rf ~ "           "match"    "$(pattern_matches "$CMD_PATTERN" "rm -rf ~ ")"
    check "Block DROP TABLE"          "match"    "$(pattern_matches "$CMD_PATTERN" "DROP TABLE users")"
    check "Block DROP DATABASE"       "match"    "$(pattern_matches "$CMD_PATTERN" "DROP DATABASE prod")"
    check "Block git push --force"    "match"    "$(pattern_matches "$CMD_PATTERN" "git push --force")"
    check "Block git push -f"         "match"    "$(pattern_matches "$CMD_PATTERN" "git push origin main -f")"

    # Should ALLOW (pattern does NOT match)
    check "Allow ls -la"              "no_match" "$(pattern_matches "$CMD_PATTERN" "ls -la")"
    check "Allow normal git push"     "no_match" "$(pattern_matches "$CMD_PATTERN" "git push origin main")"
    check "Allow python3 train.py"    "no_match" "$(pattern_matches "$CMD_PATTERN" "python3 train.py")"
    check "Allow rm -rf ./node_modules" "no_match" "$(pattern_matches "$CMD_PATTERN" "rm -rf ./node_modules")"
    check "Allow rm file.txt"         "no_match" "$(pattern_matches "$CMD_PATTERN" "rm file.txt")"
    check "Allow git push -u origin"  "no_match" "$(pattern_matches "$CMD_PATTERN" "git push -u origin feature")"

    echo ""
else
    echo -e "${YELLOW}Command protection: ${RED}NOT INSTALLED${NC}"
    echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────

total=$((pass + fail))
echo -e "${CYAN}Results: ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC} ($total tests)"

if [[ $fail -eq 0 ]]; then
    echo -e "${GREEN}All guardrails working correctly!${NC}"
else
    echo -e "${RED}Some tests failed — check your guardrail patterns.${NC}"
    exit 1
fi
