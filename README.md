# Claude Code Guardrails

Lightweight safety hooks for Claude Code's bypass permissions mode. Not a container. Not a VM. Just the guardrails.

## What it does

Two PreToolUse hooks that run in <1ms before every tool call:

**File protection** — blocks writes to:
- `.env`, `.pem`, `.key`, `.credential`, `.secret`
- `secrets/`, `.ssh/`, `.aws/`, `.gnupg/`

**Command protection** — blocks:
- `rm -rf /` or `rm -rf ~` (filesystem nuke)
- `git push --force` (force push)
- `DROP TABLE` / `DROP DATABASE` (database destruction)
- Fork bombs (`:(){ :|:& };:`)

## Install

```bash
git clone https://github.com/danfu09/claude-guardrails.git
cd claude-guardrails
bash install.sh
```

Or one-liner:

```bash
bash <(curl -sL https://raw.githubusercontent.com/danfu09/claude-guardrails/main/install.sh)
```

## Commands

```bash
bash install.sh          # Install (merges into existing settings)
bash install.sh --check  # Show status without changing anything
bash install.sh --remove # Remove guardrails
```

## Verify

Run the test suite to confirm guardrails are active:

```bash
bash test.sh
```

```
Testing Claude Code Guardrails

File protection:
  ✓ Block .env file
  ✓ Block secrets/ directory
  ✓ Block .ssh/ directory
  ✓ Block .pem file
  ✓ Block .credential file
  ✓ Allow normal .py file
  ✓ Allow README.md

Command protection:
  ✓ Block rm -rf /
  ✓ Block rm -rf ~
  ✓ Block DROP TABLE
  ✓ Block DROP DATABASE
  ✓ Allow ls -la
  ✓ Allow normal git push
  ✓ Allow python3
  ✓ Allow rm -rf ./node_modules (relative)

Results: 15 passed, 0 failed (15 tests)
All guardrails working correctly!
```

The test uses pure pattern matching (`grep`) — dangerous strings like `rm -rf /` are only ever treated as data, never executed. A failed test prints `✗` and exits. Nothing is deleted, modified, or run.

### Live test (inside Claude Code)

The most convincing test: open a Claude Code session and ask it to do something the guardrails should block:

```
> Write "test" to /tmp/test.env
```

You should see the hook block the write:

```
✗ Hook blocked tool call: Protected file: /tmp/test.env
```

The file is never created. Try a few:

```
> Write "hello" to ~/.ssh/test        # blocked (protected directory)
> Write "data" to /tmp/safe.txt       # allowed (normal file)
```

This proves the hooks are active in a real session, not just in a test script.

## Requirements

- `jq` (JSON processor)
- `bash` + `grep` (standard on Mac/Linux)
- Claude Code (any version with hooks support)

## How it works

Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) lets you run shell commands before/after tool calls. These hooks inspect the tool input (file path or command) and return `{"decision": "block", "reason": "..."}` if it matches a dangerous pattern, or `{"decision": "approve"}` otherwise.

The installer merges hooks into your existing `~/.claude/settings.json` without overwriting other settings. It creates a timestamped backup first.

## Customizing

Edit `guardrails.json` to add your own patterns:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": "your-check-here"}]
      }
    ]
  }
}
```

Common additions:
- Block writes to production config files
- Block `kubectl delete` or `terraform destroy`
- Block network requests to internal domains
- Log all bash commands to an audit file

## License

MIT
