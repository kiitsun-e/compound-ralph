---
name: feature-name
status: pending  # pending | building | complete | blocked
created: YYYY-MM-DD
plan_file: plans/feature-name.md
iteration_count: 0
project_type: bun
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
- [ ] Task 1: Install dependencies and verify all quality gates run
  - Run: `bun install`
  - Verify: `bun test`, `bun lint`, `bun typecheck` all execute (even if they fail)
  - **Blocker if skipped**: Cannot run backpressure without dependencies

#### Phase 2: Implementation (Each task includes its own validation)
- [ ] Task 2: [Create source file]
  - File: `src/path/to/file.ts`
  - Test: `tests/unit/file.test.ts` (CREATE IN SAME ITERATION)
  - Validate: `bun lint src/path/to/file.ts && bun typecheck`

- [ ] Task 3: [Create UI component]
  - File: `src/components/Component.svelte`
  - Test: `tests/unit/Component.test.ts` (CREATE IN SAME ITERATION)
  - Validate: `bun lint && bun typecheck`
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
- [ ] Lint passes on changed files: `bun lint [changed-files]`
- [ ] Types check on changed files: `bun typecheck`
- [ ] Related tests pass: `bun test [related-test-files]`

### Full Gates (run after each iteration)
- [ ] All tests pass: `bun test`
- [ ] Full lint clean: `bun lint`
- [ ] Full type check: `bun typecheck`
- [ ] Build succeeds: `bun build`

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
| `src/components/Feature.tsx` | `tests/unit/Feature.test.ts` | Yes - screenshot |
| `src/hooks/useFeature.ts` | `tests/unit/useFeature.test.ts` | No |
| `src/utils/helper.ts` | `tests/unit/helper.test.ts` | No |

### Patterns to Follow

[From plan research - existing patterns in the codebase to match]

- Follow existing component structure in `src/components/Example.tsx`
- Use the data fetching pattern from `src/hooks/useData.ts`
- Match test style in `tests/unit/example.test.ts`

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
