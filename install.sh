#!/usr/bin/env bash
# install.sh — Install Claude Code guardrails into ~/.claude/settings.json
#
# Merges PreToolUse hooks into your existing settings without overwriting
# anything else. Safe to run multiple times (idempotent).
#
# Usage:
#   bash install.sh          # install guardrails
#   bash install.sh --check  # dry-run, show what would change
#   bash install.sh --remove # remove guardrails

set -euo pipefail

SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARDRAILS_FILE="$SCRIPT_DIR/guardrails.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Preflight ────────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt install jq"
    echo "  Fedora: sudo dnf install jq"
    exit 1
fi

if [[ ! -f "$GUARDRAILS_FILE" ]]; then
    echo -e "${RED}Error: guardrails.json not found at $GUARDRAILS_FILE${NC}"
    exit 1
fi

# ── Functions ────────────────────────────────────────────────────────────

show_guardrails() {
    echo -e "${CYAN}Claude Code Guardrails${NC}"
    echo ""
    echo -e "  ${GREEN}File protection${NC} — blocks writes to:"
    echo "    .env, .pem, .key, .credential, .secret"
    echo "    secrets/, .ssh/, .aws/, .gnupg/"
    echo ""
    echo -e "  ${GREEN}Command protection${NC} — blocks:"
    echo "    rm -rf / or ~    (filesystem nuke)"
    echo "    git push --force (force push)"
    echo "    DROP TABLE/DB    (database destruction)"
    echo "    fork bombs       (:(){ :|:& };:)"
    echo ""
}

backup_settings() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        local backup="$SETTINGS_FILE.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_FILE" "$backup"
        echo -e "${YELLOW}Backed up existing settings to:${NC}"
        echo "  $backup"
    fi
}

merge_guardrails() {
    mkdir -p "$SETTINGS_DIR"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        # No existing settings — just copy guardrails as the settings
        cp "$GUARDRAILS_FILE" "$SETTINGS_FILE"
        echo -e "${GREEN}Created $SETTINGS_FILE with guardrails.${NC}"
        return
    fi

    # Merge: add our hooks without removing existing ones
    local merged
    merged=$(jq -s '
        # Start with existing settings
        .[0] as $existing |
        .[1] as $new |

        # Get existing hooks or empty
        ($existing.hooks // {}) as $eh |
        ($new.hooks // {}) as $nh |

        # For each hook type in new, append entries that do not already exist
        reduce ($nh | keys[]) as $event (
            $existing;
            .hooks[$event] = (
                ($eh[$event] // []) +
                [($nh[$event] // [])[] |
                 select(. as $entry |
                    ($eh[$event] // []) |
                    all(.matcher != $entry.matcher or .hooks != $entry.hooks)
                 )]
            )
        )
    ' "$SETTINGS_FILE" "$GUARDRAILS_FILE")

    echo "$merged" | jq '.' > "$SETTINGS_FILE"
    echo -e "${GREEN}Merged guardrails into $SETTINGS_FILE.${NC}"
}

remove_guardrails() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo -e "${YELLOW}No settings file found — nothing to remove.${NC}"
        return
    fi

    backup_settings

    # Remove PreToolUse hooks that match our guardrails patterns
    local cleaned
    cleaned=$(jq '
        if .hooks.PreToolUse then
            .hooks.PreToolUse = [
                .hooks.PreToolUse[] |
                select(
                    (.hooks[0].command | test("Protected file|Dangerous command blocked")) | not
                )
            ] |
            if (.hooks.PreToolUse | length) == 0 then
                del(.hooks.PreToolUse)
            else . end
        else . end |
        if .hooks and (.hooks | keys | length) == 0 then
            del(.hooks)
        else . end
    ' "$SETTINGS_FILE")

    echo "$cleaned" | jq '.' > "$SETTINGS_FILE"
    echo -e "${GREEN}Removed guardrails from $SETTINGS_FILE.${NC}"
}

check_installed() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo -e "${YELLOW}Not installed${NC} — no settings file found."
        return
    fi

    local has_file_guard has_cmd_guard
    has_file_guard=$(jq '[.hooks.PreToolUse // [] | .[] | select(.matcher == "Edit|Write")] | length' "$SETTINGS_FILE" 2>/dev/null || echo 0)
    has_cmd_guard=$(jq '[.hooks.PreToolUse // [] | .[] | select(.matcher == "Bash")] | length' "$SETTINGS_FILE" 2>/dev/null || echo 0)

    if [[ "$has_file_guard" -gt 0 && "$has_cmd_guard" -gt 0 ]]; then
        echo -e "${GREEN}Installed${NC} — both guardrails active."
    elif [[ "$has_file_guard" -gt 0 ]]; then
        echo -e "${YELLOW}Partial${NC} — file protection active, command protection missing."
    elif [[ "$has_cmd_guard" -gt 0 ]]; then
        echo -e "${YELLOW}Partial${NC} — command protection active, file protection missing."
    else
        echo -e "${RED}Not installed${NC} — no guardrails found in settings."
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────

case "${1:-}" in
    --check)
        show_guardrails
        check_installed
        ;;
    --remove)
        echo -e "${CYAN}Removing Claude Code guardrails...${NC}"
        remove_guardrails
        echo -e "${GREEN}Done.${NC}"
        ;;
    --help|-h)
        echo "Usage: install.sh [--check|--remove|--help]"
        echo ""
        echo "  (no args)  Install guardrails (merges into existing settings)"
        echo "  --check    Show status without changing anything"
        echo "  --remove   Remove guardrails from settings"
        echo "  --help     Show this help"
        ;;
    *)
        show_guardrails
        echo -e "${CYAN}Installing Claude Code guardrails...${NC}"
        echo ""
        backup_settings
        merge_guardrails
        echo ""
        echo -e "${GREEN}Done!${NC} Guardrails are now active."
        echo ""
        echo "These hooks run automatically when Claude Code uses bypass permissions."
        echo "No restart needed — they take effect on the next tool call."
        echo ""
        echo "Run 'bash install.sh --check' to verify, or '--remove' to uninstall."
        ;;
esac
