# Command Reference

Complete reference for all `cr` commands, flags, and environment variables.

## Commands

### `cr init`

Usage: `cr init [path]`

Initialize a project for Compound Ralph. Creates the standard directory structure (`specs/`, `plans/`, `knowledge/`, `AGENTS.md`) and auto-detects the project type (bun, npm, rails, python, etc.).

**Arguments:**
- `path` - Project directory to initialize (default: current directory)

**Examples:**
```bash
cr init
cr init ~/projects/my-app
```

---

### `cr converse`

**Aliases:** `conv`

Usage: `cr converse <topic>`

Explore an idea through Socratic dialogue before committing to a plan. Surfaces assumptions, explores alternatives, and clarifies trade-offs. Saves decision records to `knowledge/decisions/` for use in later planning.

**Arguments:**
- `topic` - The idea or topic to explore (required)

**Examples:**
```bash
cr converse "auth approach"
cr conv "should we use REST or GraphQL"
```

---

### `cr research`

**Aliases:** `res`

Usage: `cr research <topic>`

Deep investigation before planning. Analyzes the codebase, researches best practices, and assesses feasibility. Saves research reports to `knowledge/research/` for use in later planning.

**Arguments:**
- `topic` - The subject to research (required)

**Examples:**
```bash
cr research "oauth providers"
cr res "database migration strategies"
```

---

### `cr plan`

Usage: `cr plan <description>`

Create and deepen a feature plan. Automatically ingests `knowledge/` context from prior `converse` and `research` sessions. Runs the compound-engineering plan and deepen-plan workflows, enriching the plan with 40+ parallel research agents.

**Arguments:**
- `description` - Feature description (required)

**Examples:**
```bash
cr plan "add user authentication"
cr plan "migrate database to PostgreSQL"
```

---

### `cr spec`

Usage: `cr spec <plan-file>`

Convert a plan to SPEC.md format. Creates a `specs/<feature>/` directory containing `SPEC.md` and `PROMPT.md`. Auto-detects quality gates for the project.

**Arguments:**
- `plan-file` - Path to the plan file (required)

**Examples:**
```bash
cr spec plans/add-user-auth.md
```

---

### `cr implement`

**Aliases:** `build`, `run`

Usage: `cr implement [spec-dir] [--json] [--non-interactive]`

Start the autonomous implementation loop. Reads SPEC.md, executes one task per iteration, runs backpressure checks (tests, lint) each iteration, and continues until completion or max iterations. Auto-detects fix specs in `fixes/code` and `fixes/design`.

**Options:**
- `--json` - Output a final JSON summary on completion or failure
- `--non-interactive` - Auto-confirm all prompts (for CI/agent use)

**Arguments:**
- `spec-dir` - Path to the spec directory (default: auto-detected)

**Examples:**
```bash
cr implement
cr implement specs/my-feature
cr --non-interactive --json implement specs/my-feature
```

---

### `cr review`

Usage: `cr review [spec-dir] [options]`

Run a comprehensive, spec-aware code review. Discovers issues and saves them as todos for later fixing. Supports design review with screenshot-based UI analysis.

**Options:**
- `--design` - Include design review (requires dev server)
- `--design-only` - Only run design review (SPA-aware)
- `--url URL` - Specify dev server URL for design review
- `--team` - Use Agent Teams for parallel review (experimental). Spawns 3 competing reviewers (security, performance, quality) that challenge each other's findings. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- `--team-model MODEL` - Model to use for teammates (e.g., `sonnet`)
- `--dry-run` - Preview team structure without running (with `--team`)

**Output:**
- Code review todos: `specs/<feature>/todos/code/`
- Design review todos: `specs/<feature>/todos/design/`

**Examples:**
```bash
cr review
cr review specs/my-feature
cr review --design --url http://localhost:3000
cr review --team --team-model sonnet
cr review --design-only
```

---

### `cr fix`

Usage: `cr fix [type] [spec-dir]`

Convert review todos into a fix spec. Creates a new SPEC.md under `fixes/code/` or `fixes/design/` that can be implemented with `cr implement`.

**Arguments:**
- `type` - Type of issues to fix: `code`, `design`, or omit for all
- `spec-dir` - Path to the spec directory (default: auto-detected)

**Output:**
- `specs/<feature>/fixes/code/SPEC.md`
- `specs/<feature>/fixes/design/SPEC.md`

**Examples:**
```bash
cr fix
cr fix code
cr fix design
cr fix code specs/my-feature
```

---

### `cr test-gen`

**Aliases:** `testgen`, `tg`

Usage: `cr test-gen <spec-dir> [options]`

Generate E2E tests from a feature spec. Reads SPEC.md and produces a WebdriverIO test file using LLM translation of requirements to test code.

**Options:**
- `--output <file>` - Specify output path for the generated test file
- `--example-tests <dir>` - Directory containing example tests for style reference
- `--dry-run` - Show generated test code without writing to disk
- `--all` - Process all specs in the specs directory

**Examples:**
```bash
cr test-gen specs/my-feature
cr tg specs/my-feature --output test/e2e/my-feature.test.js
cr test-gen specs/my-feature --dry-run
cr test-gen --all
```

---

### `cr init-tests`

**Aliases:** `init-e2e`

Usage: `cr init-tests [options]`

Set up WebdriverIO E2E testing infrastructure. Creates `wdio.conf.js`, a test directory, and a smoke test. Installs dependencies and adds npm scripts.

**Options:**
- `--force` - Overwrite existing configuration
- `--test-dir <dir>` - Custom test directory (default: `test/e2e`)

**Examples:**
```bash
cr init-tests
cr init-e2e --test-dir tests/e2e
cr init-tests --force
```

---

### `cr compound`

**Aliases:** `comp`

Usage: `cr compound [feature]`

Extract and preserve learnings from a completed feature. Captures patterns, decisions, and pitfalls to make future work easier by compounding knowledge.

**Output:**
- `knowledge/learnings/`
- `knowledge/patterns/`

**Examples:**
```bash
cr compound
cr comp "user authentication"
```

---

### `cr design`

Usage: `cr design [url] [options]`

Run a proactive design improvement loop. SPA-aware: discovers all pages and view states (nav links, keyboard shortcuts, tabs, sidebars). Uses the `/frontend-design` skill for distinctive UI. Saves screenshots to `design-iterations/`.

**Options:**
- `--n N` - Force exactly N iterations (default: exits early when design is polished)

**Arguments:**
- `url` - Dev server URL (default: auto-detected)

**Examples:**
```bash
cr design
cr design http://localhost:3000
cr design --n 5
```

---

### `cr status`

Usage: `cr status [--json]`

Show progress of all specs, including fix specs.

**Options:**
- `--json` - Output spec status as a JSON array

**Human-readable output columns:**
- Spec name
- Status (`pending`, `building`, `complete`, `blocked`)
- Iteration count
- Task progress (completed/total)

**JSON output format:**
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

**Examples:**
```bash
cr status
cr status --json
```

---

### `cr learnings`

Usage: `cr learnings [category] [limit]`

View project learnings from `.cr/learnings.json`.

**Arguments:**
- `category` - Filter by category: `environment`, `pattern`, `gotcha`, `fix`, `discovery`
- `limit` - Number of entries to show (default: 20)

**Examples:**
```bash
cr learnings
cr learnings pattern
cr learnings fix 10
```

---

### `cr reset-context`

Usage: `cr reset-context <spec-dir>`

Reset accumulated context for a stuck spec. Use when the agent has learned harmful patterns (e.g., dismissing errors as "pre-existing"). Clears bad learnings and allows a fresh start.

**Arguments:**
- `spec-dir` - Path to the spec directory (required)

**Examples:**
```bash
cr reset-context specs/my-feature
```

---

### `cr help`

**Aliases:** `--help`, `-h`

Usage: `cr help`

Show the full help text with all commands, workflow, and project structure.

---

### `cr version`

**Aliases:** `--version`, `-v`

Usage: `cr version`

Print the Compound Ralph version string.

---

## Global Flags

These flags can be placed anywhere on the command line and apply to all commands.

| Flag | Description |
|------|-------------|
| `--non-interactive` | Auto-confirm all interactive prompts. Designed for CI/CD and agent use. |
| `--json` | Output machine-readable JSON. Implies `NO_COLOR`. Supported by: `status`, `implement`. |

**Examples:**
```bash
cr --non-interactive --json implement
cr --json status
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NO_COLOR` | (unset) | Disable colored output ([no-color.org](https://no-color.org/)). Set to any value to enable. |
| `MAX_ITERATIONS` | `50` | Maximum loop iterations for `cr implement`. |
| `ITERATION_DELAY` | `3` | Seconds to wait between iterations. |
| `MAX_RETRIES` | `3` | Number of retries per iteration on transient errors. |
| `RETRY_DELAY` | `5` | Initial retry delay in seconds. Doubles on each subsequent retry. |
| `ITERATION_TIMEOUT` | `600` | Maximum seconds per iteration before timeout (10 minutes). |
| `MAX_CONSECUTIVE_FAILURES` | `3` | Stop the loop after N consecutive failures. |

**Examples:**
```bash
MAX_ITERATIONS=100 cr implement
NO_COLOR=1 cr status
ITERATION_TIMEOUT=1200 MAX_RETRIES=5 cr implement specs/big-feature
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success. Command completed or spec marked complete. |
| `1` | Error. Missing arguments, file not found, command failure, or max iterations reached. |
| `130` | Interrupted. User pressed Ctrl+C or process received SIGTERM. Resumable with `cr implement`. |
