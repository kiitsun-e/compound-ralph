# Compound Ralph

Autonomous feature implementation system combining compound-engineering's rich planning with the Ralph Loop technique for iterative, self-correcting code generation.

## What Is This?

`cr` is a bash CLI (~5,500 lines) that orchestrates [Claude Code](https://claude.ai/code) for autonomous feature implementation. It calls `claude --print` in a loop, using SPEC.md files as state and AGENTS.md for build/test/lint commands.

The key insight: **fresh context per iteration + file-based state + quality gate backpressure**. Each iteration starts with a clean context window, reads the current state from SPEC.md, does one task, runs all quality gates (tests, lint, types, build), and writes results back. If something breaks, the next iteration sees the failure and self-corrects.

Each unit of engineering work should make subsequent units easier.

You handle the thinking (converse, research, plan). The machine handles the building (implement loop). File-based state is the bridge.

## Installation

```bash
# Clone or copy this directory
cd ~/Desktop/coding-projects/compound-ralph

# Make executable
chmod +x cr

# Add to PATH (optional)
echo 'export PATH="$PATH:$HOME/Desktop/coding-projects/compound-ralph"' >> ~/.zshrc
source ~/.zshrc

# Or create symlink
ln -s ~/Desktop/coding-projects/compound-ralph/cr /usr/local/bin/cr
```

### Shell Completions (optional)

```bash
# Bash - add to ~/.bashrc
source ~/Desktop/coding-projects/compound-ralph/completions/cr.bash

# Zsh - add to ~/.zshrc (before compinit)
fpath=(~/Desktop/coding-projects/compound-ralph/completions $fpath)
```

### Prerequisites

1. **Git** - Version control (usually pre-installed)
   ```bash
   git --version  # Verify installation
   ```

2. **Claude Code CLI** - [Install from claude.ai](https://claude.ai/code)
   ```bash
   claude --version  # Verify installation
   ```

3. **Compound Engineering Plugin** - Planning workflows and design skills:
   ```bash
   claude "/plugin marketplace add https://github.com/EveryInc/compound-engineering-plugin"
   claude "/plugin install compound-engineering"
   ```

   Provides: `/workflows:plan`, `/deepen-plan`, `/workflows:review`, `/frontend-design` skill

4. **Vercel agent-browser CLI** - Browser automation for screenshots and visual testing:
   ```bash
   npm install -g agent-browser
   agent-browser install  # Downloads Chromium
   ```

   Basic usage:
   ```bash
   agent-browser open http://localhost:3000  # Navigate to page
   agent-browser screenshot page.png          # Capture screenshot
   agent-browser snapshot                     # Get interactive elements
   agent-browser click @e1                    # Click element by ref
   agent-browser close                        # Close browser
   ```

   See [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) for full documentation.

## Quick Start

```bash
# 1. Initialize your project
cd your-project
cr init

# 2. Explore the idea (optional)
cr converse "user authentication approach"

# 3. Research before planning (optional)
cr research "JWT vs session-based auth"

# 4. Create a rich plan (interactive)
cr plan "add user authentication with JWT"

# 5. Convert plan to SPEC format
cr spec plans/add-user-authentication-with-jwt.md

# 6. Start autonomous implementation
cr implement
# Walk away - Claude works through tasks one by one

# 7. Review the implementation
cr review

# 8. Fix any issues found
cr fix
cr implement

# 9. Extract learnings
cr compound user-authentication
```

```
CONVERSE → RESEARCH → PLAN → SPEC → IMPLEMENT → REVIEW → FIX → COMPOUND
```

For a real-world walkthrough of this workflow in action, see [docs/workflow-example.md](docs/workflow-example.md).

## Commands

### Core Workflow

#### `cr init [path]`
Initialize a project for Compound Ralph. Creates `specs/`, `plans/`, `knowledge/` directories and generates `AGENTS.md` with auto-detected build/test commands. Supports bun, npm, yarn, pnpm, rails, python, go, and rust.

Flags: None

#### `cr converse <topic>` (alias: `conv`)
Start an exploratory Socratic dialogue about an idea before committing to a plan. Surfaces assumptions, explores alternatives, and clarifies trade-offs. Saves decision records to `knowledge/decisions/` for use in later planning.

Flags: None

#### `cr research <topic>` (alias: `res`)
Deep investigation before planning. Analyzes codebase for existing patterns, researches best practices, assesses feasibility and risks with confidence levels. Saves reports to `knowledge/research/`.

Flags: None

#### `cr plan <description>`
Create and enrich a feature plan using compound-engineering workflows. Automatically reads `knowledge/decisions/` and `knowledge/research/` from prior sessions. Runs `/workflows:plan` + `/deepen-plan` with 40+ parallel research agents.

Flags: None

#### `cr spec <plan-file>`
Convert a plan to the SPEC.md format for autonomous implementation. Creates `specs/<feature>/` with SPEC.md (state file) and PROMPT.md (iteration instructions). Auto-detects quality gates based on project type.

Flags: None

#### `cr implement [spec-dir]` (aliases: `build`, `run`)
Start the autonomous implementation loop. Reads SPEC.md, executes one task per iteration, runs all quality gates each iteration, updates state and commits progress. Continues until completion or max iterations.

Flags: `--json`, `--non-interactive`

#### `cr review [spec-dir]`
Run comprehensive code review. Discovers issues and saves todos to `specs/<feature>/todos/code/`.

Flags: `--design`, `--design-only`, `--url <url>`, `--team`

#### `cr fix [type] [spec-dir]`
Convert review todos into a fix spec. Use `cr fix code` for code issues only, `cr fix design` for design issues only, or `cr fix` for all. Creates fix specs under `specs/<feature>/fixes/`, then run `cr implement` to apply fixes.

Flags: None

#### `cr compound [feature]` (alias: `comp`)
Extract and preserve learnings after implementation. Captures patterns, decisions, and pitfalls. Saves to `knowledge/learnings/` and `knowledge/patterns/`. Makes future features easier by compounding knowledge.

Flags: None

### Testing

#### `cr test-gen <spec>` (aliases: `testgen`, `tg`)
Generate E2E tests from a feature spec. Reads SPEC.md and produces WebdriverIO test files using LLM to translate requirements into test code.

Flags: `--output <path>`, `--example-tests <path>`, `--dry-run`, `--all`

#### `cr init-tests` (alias: `init-e2e`)
Set up WebdriverIO E2E testing infrastructure. Creates `wdio.conf.js`, test directory, and smoke test. Installs dependencies and adds npm scripts.

Flags: `--force`, `--test-dir <path>`

### Design

#### `cr design [url]`
Proactive design improvement loop. Auto-detects dev server, discovers all pages and SPA view states (nav links, keyboard shortcuts, tabs, sidebars), takes screenshots, and uses the `/frontend-design` skill for distinctive UI. Saves screenshots to `design-iterations/`.

Flags: `--n <count>`

### Utility

#### `cr status`
Show progress of all specs including fix specs. Displays status, iteration count, and task completion.

Flags: `--json`

#### `cr learnings [category] [limit]`
View project learnings from `.cr/learnings.json`. Categories: environment, pattern, gotcha, fix, discovery. Default limit: 20.

Flags: None

#### `cr reset-context <spec-dir>`
Reset accumulated context for a stuck spec. Use when the agent has learned harmful patterns (e.g., dismissing errors as "pre-existing"). Clears bad learnings and allows a fresh start.

Flags: None

#### `cr help`
Show full usage information with all commands, flags, and workflow examples.

Flags: None

#### `cr version`
Print the current version.

Flags: None

## Workflow Phases

There are three interaction modes across the workflow:

| Mode | Commands | Your Role |
|------|----------|-----------|
| **Interactive** | converse, research, plan, review, compound | You participate in dialogue, answer questions, guide direction |
| **Autonomous** | implement | Walk away -- the loop runs unattended with quality gate backpressure |
| **Hybrid** | design | Autonomous iterations with periodic review |

## Architecture

```
your-project/
├── AGENTS.md                 # Build/test/lint commands (shared)
├── knowledge/                # Pre-planning knowledge base
│   ├── decisions/            # Decision records from cr converse
│   │   └── 2026-01-27-auth-approach.md
│   └── research/             # Research reports from cr research
│       └── oauth-providers.md
├── plans/
│   └── feature-name.md       # Rich plans from cr plan (informed by knowledge/)
└── specs/
    └── feature-name/
        ├── SPEC.md           # State file (single source of truth)
        ├── PROMPT.md         # Iteration instructions
        ├── todos/
        │   ├── code/         # Code review findings
        │   └── design/       # Design review findings
        ├── fixes/
        │   ├── code/         # Fix spec for code issues
        │   └── design/       # Fix spec for design issues
        └── .history/         # Logs from each iteration
            ├── 001-20260121-143022.md
            └── 002-20260121-143145.md
```

### SPEC.md Structure

```yaml
---
name: feature-name
status: building          # pending | building | complete | blocked
created: 2026-01-21
plan_file: plans/feature-name.md
iteration_count: 5
project_type: bun
---
```

**Sections:**
- **Overview** - Brief description
- **Requirements** - Checkboxes (don't change during implementation)
- **Tasks** - Pending / In Progress / Completed / Blocked
- **Quality Gates** - Commands that run every iteration
- **Exit Criteria** - All must be true to complete
- **Context** - Key files, patterns to follow, notes
- **Iteration Log** - History of what each iteration did

### AGENTS.md Structure

Keep under 60 lines. Contains operational commands:

```markdown
## Build
bun install && bun run build

## Test
bun test

## Lint
bun run lint && bun run typecheck

## Learnings
- Use `bun test --watch` for faster iteration
- Types are in `src/types/` not `types/`
```

## The Iteration Loop

Each iteration follows this cycle:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. ORIENT - Load fresh context                              │
│    - Read SPEC.md (source of truth)                         │
│    - Read plan file                                         │
│    - Check iteration log for learnings                      │
│    - Study key files                                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. SELECT - Pick ONE task                                   │
│    - Continue "In Progress" if exists                       │
│    - Otherwise pick highest priority "Pending"              │
│    - Move to "In Progress" BEFORE starting                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. INVESTIGATE - Don't assume not implemented               │
│    - Search codebase for existing implementations           │
│    - Check if task is partially done                        │
│    - Update notes with discoveries                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. IMPLEMENT - Execute the task                             │
│    - Follow patterns from Context section                   │
│    - Write tests alongside (not after)                      │
│    - Keep focused on ONE task                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. VALIDATE - Run backpressure                              │
│    - bun test                                               │
│    - bun run lint                                           │
│    - bun run typecheck                                      │
│    - bun run build                                          │
│    - Fix issues before continuing                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. UPDATE - Record progress                                 │
│    - Move task to "Completed"                               │
│    - Add learnings to Notes                                 │
│    - Update iteration count                                 │
│    - Add to Iteration Log                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. COMMIT & CHECK - Save and evaluate                       │
│    - git commit meaningful progress                         │
│    - Check all exit criteria                                │
│    - If ALL met → output completion promise                 │
│    - If not → next iteration continues                      │
└─────────────────────────────────────────────────────────────┘
```

## Backpressure

**Backpressure** = automated feedback that lets agents self-correct without human intervention. See [docs/backpressure.md](docs/backpressure.md) for a deeper explanation.

### Hard Gates (Deterministic)
- Tests pass/fail
- Build succeeds/fails
- Type checker passes/fails
- Linter passes/fails

### Soft Gates (Heuristic)
- Screenshot comparison (via agent-browser)
- Coverage thresholds
- LLM-as-judge for subjective criteria

### Auto-Detection

Compound Ralph auto-detects your project type and sets appropriate quality gates:

| Project Type | Detection | Quality Gates |
|-------------|-----------|---------------|
| Bun | `bun.lockb` | `bun test`, `bun run lint`, `bun run typecheck`, `bun run build` |
| npm | `package-lock.json` | `npm test`, `npm run lint`, `npm run typecheck` |
| Rails | `Gemfile` | `bin/rails test`, `bundle exec rubocop`, `bundle exec brakeman` |
| Python | `pyproject.toml` | `pytest`, `ruff check`, `mypy` |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_ITERATIONS` | 50 | Maximum iterations before stopping |
| `ITERATION_DELAY` | 3 | Seconds between iterations |
| `MAX_RETRIES` | 3 | Retries per iteration on transient errors |
| `RETRY_DELAY` | 5 | Initial retry delay (doubles with each retry) |
| `ITERATION_TIMEOUT` | 600 | Max seconds per iteration before timeout |
| `MAX_CONSECUTIVE_FAILURES` | 3 | Stop after N consecutive failures |
| `NO_COLOR` | - | Disable colored output ([no-color.org](https://no-color.org/)) |

```bash
MAX_ITERATIONS=100 ITERATION_DELAY=5 cr implement
```

## Self-Healing

The loop automatically recovers from transient errors:

- **Network issues** (ECONNRESET, ETIMEDOUT)
- **Rate limiting** (429, rate limit messages)
- **Server errors** (502, 503, overloaded)
- **Empty responses** ("No messages returned")

When an error occurs:
1. Waits `RETRY_DELAY` seconds (default: 5s)
2. Retries with exponential backoff (5s → 10s → 20s)
3. After `MAX_RETRIES` failures, skips to next iteration
4. Loop continues - no human intervention needed

```bash
# More aggressive retries for flaky connections
MAX_RETRIES=5 RETRY_DELAY=10 cr implement
```

## Tips for Success

### 1. Rich Planning Pays Off

The more context in your plan, the better the implementation:
- Run `/deepen-plan` to get framework docs, best practices
- Identify existing patterns in the codebase
- List all files that will need changes

### 2. Task Granularity Matters

Break tasks small enough to complete in one iteration (~15-30 min of work):
- "Implement authentication" (too big)
- "Create User model with validation" (right size)
- "Add login API endpoint" (right size)
- "Create login form component" (right size)

### 3. Quality Gates Are Your Friend

Add project-specific gates to catch issues early:
```markdown
## Quality Gates
- [ ] Tests pass: `bun test`
- [ ] Lint clean: `bun run lint`
- [ ] Types check: `bun run typecheck`
- [ ] E2E pass: `bun run test:e2e`
- [ ] Bundle size: `bun run analyze | grep "under 100kb"`
```

### 4. Let Notes Compound

The Notes section should grow with each iteration:
```markdown
### Notes
- Iteration 2: Discovered existing auth utility in `src/lib/auth.ts`
- Iteration 3: API types are auto-generated, don't manually edit
- Iteration 5: Use `useAuth` hook, not direct context access
```

### 5. Trust the Loop

Don't micro-manage. If backpressure is set up correctly:
- Tests catch regressions
- Types catch interface mismatches
- Lint catches style issues
- The loop self-corrects

## Further Reading

- [docs/workflow-example.md](docs/workflow-example.md) - Real-world walkthrough of a full feature implementation
- [docs/backpressure.md](docs/backpressure.md) - Deep dive into the backpressure concept
- [docs/prompting-patterns.md](docs/prompting-patterns.md) - Prompt engineering patterns used in cr

## Troubleshooting

### Loop stops early
Check SPEC.md — are all exit criteria achievable? Are there blocked tasks? Check `.history/` logs.

### Same error repeating
Add the error pattern to the Notes section of SPEC.md. The next iteration will see the learning and adapt.

### Context seems lost between iterations
This is by design. Each iteration gets fresh context. Information persists via SPEC.md (state), AGENTS.md (commands), git history (changes), and Notes section (learnings).

## Sources & Inspiration

This tool implements the Ralph Loop technique natively in bash, inspired by:

- [Geoffrey Huntley's Ralph Wiggum Technique](https://ghuntley.com/ralph/) - The original concept
- [Backpressure in AI Workflows](https://ghuntley.com/pressure/)
- [The Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/)
- [frankbria's Enhanced Implementation](https://github.com/frankbria/ralph-claude-code)
- [Don't Waste Your Backpressure](https://banay.me/dont-waste-your-backpressure/)
- [ominous](https://github.com/nia-vf/ominous) - Pre-implementation research and Socratic dialogue workflows (converse/research commands)

Note: This project does **not** use the [official ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) - it implements its own loop by calling `claude --dangerously-skip-permissions --print` directly.

## License

MIT - Use freely, attribute kindly.
