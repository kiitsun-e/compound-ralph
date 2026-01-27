# Compound Ralph

Autonomous Feature Implementation System combining compound-engineering's rich planning with the Ralph Loop technique for iterative, self-correcting code generation.

## Philosophy

**Understand first. Plan with context. Build autonomously.**

Each unit of engineering work should make subsequent units easier. Compound Ralph achieves this by:

1. **Exploration Phase** - Socratic dialogue to surface assumptions and explore trade-offs
2. **Research Phase** - Deep investigation of feasibility, best practices, and risks
3. **Rich Planning Phase** - Human + AI collaboration informed by knowledge from prior phases
4. **Autonomous Building Phase** - Loop executes one task per iteration with fresh context
5. **Continuous Backpressure** - Tests, lint, types run every iteration for self-correction
6. **Compounding Learnings** - Notes and patterns accumulate across iterations

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

# 2. (Optional) Explore the idea before committing
cr converse "user authentication approach"
# Socratic dialogue surfaces assumptions and trade-offs
# Saves decision record to knowledge/decisions/

# 3. (Optional) Research before planning
cr research "JWT vs session-based auth"
# Deep investigation of feasibility, best practices, risks
# Saves research report to knowledge/research/

# 4. Create a rich, researched plan (INTERACTIVE)
cr plan "add user authentication with JWT"
# Automatically reads knowledge/ from steps 2-3
# Claude will ask clarifying questions - answer them!
# When satisfied, run /deepen-plan then exit

# 5. Convert plan to SPEC format
cr spec plans/add-user-authentication-with-jwt.md

# 6. Edit SPEC.md to refine tasks and context
# (This is your chance to guide the implementation)

# 7. Start autonomous implementation (AUTONOMOUS)
cr implement
# Walk away - Claude works through tasks one by one
```

## Three Modes

| Phase | Mode | Your Role |
|-------|------|-----------|
| **Exploration** | Interactive | Converse about ideas, review research reports |
| **Planning** | Interactive | Answer questions, refine scope, run /deepen-plan |
| **Implementation** | Autonomous | Walk away, check back later |

## Commands

### `cr init [path]`

Initialize a project for Compound Ralph.

- Creates `specs/`, `plans/`, and `knowledge/` directories
- Generates `AGENTS.md` with auto-detected build/test commands
- Supports: bun, npm, yarn, pnpm, rails, python, go, rust

```bash
cr init                    # Current directory
cr init ~/projects/myapp   # Specific path
```

### `cr converse <topic>`

Start an exploratory conversation about an idea before committing to a plan.

- Activates a Socratic dialogue persona
- Guides through: Understand → Assumptions → Alternatives → Trade-offs → Decide
- Asks hard questions: "Are we solving the right problem?" / "What's the cost of being wrong?"
- Saves decision records to `knowledge/decisions/YYYY-MM-DD-<topic>.md`
- Decision records are automatically fed into `cr plan`

```bash
cr converse "user authentication approach"
cr converse "how should we handle caching"
```

### `cr research <topic>`

Deep investigation before planning — understand before you build.

- Analyzes codebase for existing patterns and dependencies
- Researches external best practices and common pitfalls
- Assesses technical feasibility, complexity, and risks
- States confidence levels (High/Medium/Low/Unknown)
- Saves research reports to `knowledge/research/<topic>.md`
- Research reports are automatically fed into `cr plan`

```bash
cr research "oauth implementation best practices"
cr research "caching strategies for our API"
```

### `cr plan <description>`

Create and enrich a feature plan using compound-engineering workflows.

- **Automatically reads** `knowledge/decisions/` and `knowledge/research/` to incorporate prior converse/research findings
- Runs `/workflows:plan` to create structured plan
- Runs `/deepen-plan` to enrich with 40+ parallel research agents
- Outputs to `plans/<feature-name>.md`

```bash
cr plan "add dark mode toggle with system preference detection"
```

### `cr spec <plan-file>`

Convert a plan to the SPEC.md format for autonomous implementation.

- Creates `specs/<feature>/` directory
- Generates `SPEC.md` (state file) and `PROMPT.md` (iteration instructions)
- Auto-detects quality gates based on project type

```bash
cr spec plans/add-dark-mode-toggle.md
```

### `cr implement [spec-dir]`

Start the autonomous implementation loop.

- Reads SPEC.md as single source of truth
- Executes one task per iteration
- Runs all quality gates (backpressure) each iteration
- Updates state and commits progress
- Continues until completion or max iterations

```bash
cr implement                        # Auto-find active spec
cr implement specs/dark-mode/       # Specific spec
MAX_ITERATIONS=100 cr implement     # Override max iterations
```

### `cr status`

Show progress of all specs.

```bash
cr status
# Output:
# Spec                     Status      Iterations  Tasks
# dark-mode               building    5           3/7
# user-auth               complete    12          8/8
# payment-flow            pending     0           0/5
```

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
│    • Read SPEC.md (source of truth)                        │
│    • Read plan file                                         │
│    • Check iteration log for learnings                     │
│    • Study key files                                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. SELECT - Pick ONE task                                   │
│    • Continue "In Progress" if exists                       │
│    • Otherwise pick highest priority "Pending"              │
│    • Move to "In Progress" BEFORE starting                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. INVESTIGATE - Don't assume not implemented               │
│    • Search codebase for existing implementations           │
│    • Check if task is partially done                        │
│    • Update notes with discoveries                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. IMPLEMENT - Execute the task                             │
│    • Follow patterns from Context section                   │
│    • Write tests alongside (not after)                      │
│    • Keep focused on ONE task                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. VALIDATE - Run backpressure                              │
│    • bun test                                               │
│    • bun run lint                                           │
│    • bun run typecheck                                      │
│    • bun run build                                          │
│    • Fix issues before continuing                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. UPDATE - Record progress                                 │
│    • Move task to "Completed"                               │
│    • Add learnings to Notes                                 │
│    • Update iteration count                                 │
│    • Add to Iteration Log                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. COMMIT & CHECK - Save and evaluate                       │
│    • git commit meaningful progress                         │
│    • Check all exit criteria                                │
│    • If ALL met → output completion promise                 │
│    • If not → next iteration continues                      │
└─────────────────────────────────────────────────────────────┘
```

## Backpressure

**Backpressure** = automated feedback that lets agents self-correct without human intervention.

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
- ❌ "Implement authentication" (too big)
- ✅ "Create User model with validation"
- ✅ "Add login API endpoint"
- ✅ "Create login form component"

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

## Troubleshooting

### Loop stops early without completing

Check the SPEC.md:
- Are all exit criteria achievable?
- Is the completion promise being output correctly?
- Are there blocked tasks that can't proceed?

### Same error repeating

1. Check `.history/` logs for patterns
2. Add the error pattern to Notes section
3. The next iteration will see the learning

### Context seems lost between iterations

This is by design! Each iteration has fresh context. Information persists via:
- SPEC.md (state file)
- AGENTS.md (commands)
- Git history (changes)
- Notes section (learnings)

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
