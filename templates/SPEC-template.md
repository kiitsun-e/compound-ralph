---
name: feature-name
status: pending  # pending | building | complete | blocked
created: YYYY-MM-DD
plan_file: plans/feature-name.md
iteration_count: 0
project_type: auto  # auto-detected: bun | node | rust | python | ruby | go | mixed
---

# Feature: [Feature Name]

## Overview

[2-3 sentence description of what this feature accomplishes. Copy from plan.]

## Requirements

[Clear, testable requirements from the plan. These don't change during implementation.]

- [ ] Requirement 1: [specific, measurable]
- [ ] Requirement 2: [specific, measurable]
- [ ] Requirement 3: [specific, measurable]

## Tasks

<!--
TASK ORDERING RULES (ENFORCED):
1. Setup tasks MUST be first (dependencies, config)
2. Each implementation task MUST specify its test file
3. UI tasks MUST specify visual verification
4. NEVER create "run tests" as a separate task at the end
-->

### Pending

#### Phase 1: Setup (MUST COMPLETE BEFORE IMPLEMENTATION)
- [ ] Task 1: Install dependencies, source environments, and verify all quality gates run
  - Environment: Source any needed toolchains (e.g., `source "$HOME/.cargo/env"` for Rust)
  - Install: Use the project's package manager (bun/npm/cargo/pip/bundle/go mod)
  - Verify: Run each quality gate command from the section below — they must all EXECUTE (even if they fail)
  - **Blocker if skipped**: Cannot run backpressure without dependencies

#### Phase 2: Implementation (Each task includes its own validation)
- [ ] Task 2: [Create source file]
  - File: `src/path/to/file.ext`
  - Test: `tests/unit/file.test.ext` (CREATE IN SAME ITERATION)
  - Validate: Run per-task quality gates on changed files

- [ ] Task 3: [Create UI component]
  - File: `src/components/Component.ext`
  - Test: `tests/unit/Component.test.ext` (CREATE IN SAME ITERATION)
  - Validate: Run per-task quality gates on changed files
  - Visual: `agent-browser screenshot localhost:PORT/path` (REQUIRED FOR UI)

#### Phase 3: Integration (After all implementation tasks)
- [ ] Task N: Integration tests and final validation
  - Run: Full test suite, E2E tests
  - Visual: Full page screenshots with agent-browser

### In Progress

[Currently being worked on - ONLY ONE AT A TIME]

### Completed

[Tasks completed with iteration number for reference]
<!--
Format:
- [x] Task 1: Install dependencies - Iteration 1
  - Result: All quality gates now runnable
-->

### Blocked

[Tasks waiting on external factors - reference todos if applicable]

## Quality Gates

<!--
BACKPRESSURE RULES (ENFORCED):
- Run after EVERY task completion, not just at the end
- If a gate fails, fix it in the SAME iteration
- If dependencies aren't installed, STOP and install them first
-->

### Per-Task Gates (run after each task)
<!--
IMPORTANT: Replace these with CONCRETE commands for your project stack.
Do NOT leave placeholders like [file] or [module] — use actual commands.
The `cr spec` command should populate these based on detected project type.

Examples by stack:
  Node/Bun:    bun lint src/path/to/file.ts && bun typecheck
  Rust:        cargo clippy -p crate-name && cargo test -p crate-name
  Python:      ruff check path/to/file.py && pytest tests/test_file.py
  Go:          go vet ./pkg/... && go test ./pkg/...
  Mixed:       Run gates for EACH stack (e.g., cargo check && pnpm lint)
-->
- [ ] Lint passes on changed files: `<stack-specific lint command>`
- [ ] Types/compilation check: `<stack-specific type check command>`
- [ ] Related tests pass: `<stack-specific test command for changed module>`

### Full Gates (run after each iteration)
<!--
These MUST be concrete, runnable commands — never placeholders.
For multi-stack projects (e.g., Tauri = Rust + TypeScript), include gates for ALL stacks.

Examples by stack:
  Node/Bun:    bun test / bun lint / bun typecheck / bun build
  Rust:        cargo test / cargo clippy / cargo check / cargo build
  Python:      pytest / ruff check . / mypy . / python -m build
  Go:          go test ./... / go vet ./... / go build ./...
  Tauri:       cargo test && pnpm test / cargo clippy && pnpm lint / cargo build && pnpm build
-->
- [ ] All tests pass: `<discovered command>`
- [ ] Full lint clean: `<discovered command>`
- [ ] Full type/compilation check: `<discovered command>`
- [ ] Build succeeds: `<discovered command>`

### Visual Gates (run after UI changes)
- [ ] Screenshot captured: `agent-browser screenshot [url]`
- [ ] Visual diff acceptable (if baseline exists)

## Exit Criteria

[ALL must be true to mark complete]

- [ ] All requirements checked off
- [ ] All quality gates pass (not "will pass later")
- [ ] All tasks completed (including their test files)
- [ ] Every source file has a corresponding test file
- [ ] Code committed with meaningful messages
- [ ] Ready for PR/review

## Context

### Key Files

[From plan - files that will be created or modified]

| Source File | Test File | Visual Check |
|-------------|-----------|--------------|
| `src/path/to/module.ext` | `tests/path/to/module.test.ext` | No |
| `src/components/Feature.ext` | `tests/unit/Feature.test.ext` | Yes - screenshot |

### Patterns to Follow

[From plan research - existing patterns in the codebase to match]

- Follow existing code structure and conventions in the project
- Match the test style used in existing test files
- Use established patterns for the project's stack

### Notes

[Learnings from iterations - this section GROWS over time]

<!--
Add discoveries here during implementation:
- Iteration 2: Discovered we need to update the API types first
- Iteration 3: Found existing utility function we can reuse
-->

## Iteration Log

[Brief log of what each iteration accomplished]

<!--
### Iteration 1 (YYYY-MM-DD HH:MM)
**Task:** Task 1 - Install dependencies
**Files Created:** None (setup only)
**Tests Created:** None (setup only)
**Result:** success - all quality gates now runnable
**Learnings:** bun install completed, all gates execute

### Iteration 2 (YYYY-MM-DD HH:MM)
**Task:** Task 2 - Create Counter component
**Files Created:** src/components/Counter.svelte
**Tests Created:** tests/unit/Counter.test.ts
**Visual:** Screenshot captured at localhost:4321
**Result:** success - component renders, tests pass
**Learnings:** Used $state() rune for reactivity
-->
