# Agent and CI/CD Integration Guide

How to invoke Compound Ralph programmatically from AI agents, CI/CD pipelines, and scripts.

## Non-Interactive Mode

By default, `cr` prompts for confirmation at certain steps (e.g., when a spec is already marked complete). The `--non-interactive` flag auto-confirms all prompts:

```bash
cr --non-interactive implement specs/my-feature
```

This is required for any unattended execution where no human is available to respond.

## JSON Output

The `--json` flag produces machine-readable JSON instead of human-formatted text. It automatically implies `NO_COLOR` (no ANSI escape codes in output).

```bash
cr --json status
cr --non-interactive --json implement specs/my-feature
```

### Supported Commands

| Command | JSON behavior |
|---------|--------------|
| `cr status --json` | Outputs a JSON array of spec status objects |
| `cr implement --json` | Outputs a JSON summary object on completion or failure |

### `cr status --json` Output

Returns an array of spec status objects:

```json
[
  {
    "name": "my-feature",
    "status": "building",
    "dir": "specs/my-feature",
    "pending_tasks": 3,
    "completed_tasks": 5,
    "total_iterations": 12
  }
]
```

Returns `[]` if no specs directory exists.

### `cr implement --json` Output

Emits a summary object when the implementation loop exits:

```json
{
  "status": "complete",
  "iterations": 14,
  "spec": "specs/my-feature/SPEC.md",
  "learnings": 7
}
```

Possible `status` values:
- `"complete"` - All tasks and quality gates passed
- `"max_iterations"` - Reached the iteration limit without completion

## Clean Log Parsing with NO_COLOR

Set `NO_COLOR=1` to strip all ANSI color codes from output, making logs easier to parse:

```bash
NO_COLOR=1 cr implement specs/my-feature 2>&1 | tee build.log
```

The `--json` flag sets this automatically, but `NO_COLOR` is useful when you want human-readable output without color codes (e.g., in CI logs).

## Recommended Agent Workflow

The standard sequence for an agent to implement a feature end-to-end:

```bash
# 1. Initialize project (if not already done)
cr init

# 2. Create a plan from a feature description
cr plan "add user authentication with OAuth"

# 3. Convert the plan to an implementation spec
cr spec plans/add-user-authentication-with-oauth.md

# 4. Run the autonomous implementation loop
cr --non-interactive --json implement

# 5. Check status
cr --json status
```

For a feature that already has a spec:

```bash
# Jump straight to implementation
cr --non-interactive --json implement specs/my-feature

# After implementation, run review
cr --non-interactive review specs/my-feature

# Fix any issues found
cr --non-interactive fix code specs/my-feature
cr --non-interactive --json implement specs/my-feature
```

## Error Handling

### Exit Codes

| Code | Meaning | Agent action |
|------|---------|-------------|
| `0` | Success | Proceed to next step |
| `1` | Error (missing args, file not found, max iterations) | Check stderr, retry or escalate |
| `130` | Interrupted (SIGTERM/SIGINT) | Safe to resume with `cr implement` |

### Detecting Completion via JSON

When using `--json`, parse the `status` field:

```bash
result=$(cr --non-interactive --json implement specs/my-feature 2>/dev/null | tail -1)
status=$(echo "$result" | jq -r '.status')

if [ "$status" = "complete" ]; then
    echo "Feature implemented successfully"
elif [ "$status" = "max_iterations" ]; then
    echo "Hit iteration limit, may need more iterations"
fi
```

### Detecting Completion via Exit Code

Without `--json`, use the exit code:

```bash
if cr --non-interactive implement specs/my-feature; then
    echo "Success"
else
    echo "Failed with exit code $?"
fi
```

## Environment Variable Configuration

Control loop behavior with environment variables. Useful for tuning agent runs:

```bash
# Longer runs for complex features
MAX_ITERATIONS=100 \
ITERATION_TIMEOUT=1200 \
MAX_RETRIES=5 \
cr --non-interactive --json implement specs/big-feature
```

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_ITERATIONS` | `50` | Maximum loop iterations |
| `ITERATION_DELAY` | `3` | Seconds between iterations |
| `MAX_RETRIES` | `3` | Retries per iteration on transient errors |
| `RETRY_DELAY` | `5` | Initial retry delay (doubles each retry) |
| `ITERATION_TIMEOUT` | `600` | Max seconds per iteration |
| `MAX_CONSECUTIVE_FAILURES` | `3` | Stop after N consecutive failures |
| `NO_COLOR` | (unset) | Disable ANSI color codes |

## Example: Using cr from Another Claude Code Session

You can invoke `cr` as a subprocess from within a Claude Code session:

```bash
# From another Claude Code session, run implementation non-interactively
cd /path/to/project
cr --non-interactive --json implement specs/my-feature
```

Or use it as part of a Claude Code workflow that orchestrates multiple tools:

```bash
# Plan and implement in sequence
cr plan "add search functionality"
cr spec plans/add-search-functionality.md
cr --non-interactive --json implement
```

## Example: CI/CD Pipeline Integration

### GitHub Actions

```yaml
name: Implement Feature
on:
  workflow_dispatch:
    inputs:
      spec_dir:
        description: 'Spec directory to implement'
        required: true

jobs:
  implement:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: npm install

      - name: Run Compound Ralph
        env:
          MAX_ITERATIONS: 100
          ITERATION_TIMEOUT: 1200
          NO_COLOR: 1
        run: |
          cr --non-interactive --json implement "${{ inputs.spec_dir }}" \
            2>&1 | tee implement.log

          # Parse result
          result=$(tail -1 implement.log)
          status=$(echo "$result" | jq -r '.status')
          echo "status=$status" >> "$GITHUB_OUTPUT"

      - name: Check result
        run: |
          if [ "${{ steps.implement.outputs.status }}" != "complete" ]; then
            echo "Implementation did not complete"
            exit 1
          fi
```

### Generic CI Script

```bash
#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="${1:?Usage: $0 <spec-dir>}"

export NO_COLOR=1
export MAX_ITERATIONS=100
export MAX_CONSECUTIVE_FAILURES=5

echo "Starting implementation: $SPEC_DIR"

# Capture JSON output (last line of stdout)
output=$(cr --non-interactive --json implement "$SPEC_DIR" 2>&1)
json_line=$(echo "$output" | tail -1)

status=$(echo "$json_line" | jq -r '.status' 2>/dev/null || echo "unknown")
iterations=$(echo "$json_line" | jq -r '.iterations' 2>/dev/null || echo "?")

echo "Result: status=$status, iterations=$iterations"

if [ "$status" = "complete" ]; then
    echo "Implementation complete after $iterations iterations"
    exit 0
else
    echo "Implementation did not complete (status: $status)"
    echo "Full output:"
    echo "$output"
    exit 1
fi
```
