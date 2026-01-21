# Backpressure: The Secret Sauce

Backpressure is what makes autonomous loops converge on correct solutions instead of spiraling into chaos.

## What is Backpressure?

Backpressure = automated feedback mechanisms that let agents self-correct without human intervention.

Instead of telling the agent what to do, you engineer an environment where **wrong outputs get rejected automatically**.

## Types of Backpressure

### Hard Gates (Deterministic)

Binary pass/fail with no ambiguity:

| Gate | What it catches | Example |
|------|-----------------|---------|
| Tests | Logic errors, regressions | `bun test` |
| Type checker | Interface mismatches | `bun run typecheck` |
| Linter | Style violations, common bugs | `bun run lint` |
| Build | Syntax errors, missing deps | `bun run build` |
| Security scanner | Known vulnerabilities | `bun run audit` |

**Start with hard gates.** They're deterministic, fast, and unambiguous.

### Soft Gates (Heuristic)

Require interpretation but still automated:

| Gate | What it catches | Implementation |
|------|-----------------|----------------|
| Coverage threshold | Missing tests | `bun test --coverage` + check percentage |
| Bundle size | Bloat | `bun run analyze` + size check |
| Screenshot comparison | Visual regressions | agent-browser + image diff |
| Performance benchmark | Speed regressions | Lighthouse CI, k6 |

### LLM-as-Judge (Subjective)

For criteria that need reasoning:

```markdown
## Quality Gates
- [ ] Code review: Ask Claude "Does this code follow our patterns? Be harsh."
- [ ] UX review: Ask Claude "Is this UI intuitive? Would a user understand it?"
```

**Add LLM-as-judge last**, after mechanical backpressure is working.

## Backpressure by Project Type

### TypeScript/Bun

```markdown
## Quality Gates
- [ ] Tests pass: `bun test`
- [ ] Lint clean: `bun run lint`
- [ ] Types check: `bun run typecheck`
- [ ] Build succeeds: `bun run build`
- [ ] No type errors: `tsc --noEmit`
```

### Rails

```markdown
## Quality Gates
- [ ] Tests pass: `bin/rails test`
- [ ] System tests: `bin/rails test:system`
- [ ] Lint clean: `bundle exec rubocop`
- [ ] Security: `bundle exec brakeman -q`
- [ ] Types: `bin/srb tc` (if using Sorbet)
```

### Python

```markdown
## Quality Gates
- [ ] Tests pass: `pytest`
- [ ] Coverage > 80%: `pytest --cov --cov-fail-under=80`
- [ ] Lint clean: `ruff check .`
- [ ] Types check: `mypy .`
- [ ] Formatting: `ruff format --check .`
```

## Advanced Backpressure Patterns

### 1. Visual Verification

For UI changes, use agent-browser:

```markdown
## Quality Gates
- [ ] Visual check: Take screenshot with agent-browser, compare to expected
```

The agent can:
1. Navigate to the page
2. Take a screenshot
3. Compare to baseline or expectations
4. Report discrepancies

### 2. Integration Test Gate

Run full integration tests that exercise real flows:

```markdown
## Quality Gates
- [ ] Integration: `bun run test:integration`
- [ ] E2E: `bun run test:e2e`
```

### 3. Acceptance Criteria as Tests

Derive tests from acceptance criteria:

```markdown
## Requirements
- [ ] User can log in with email/password

## Quality Gates
- [ ] Acceptance: `bun test --grep "user can log in"`
```

### 4. Performance Budgets

```markdown
## Quality Gates
- [ ] Bundle < 100kb: `bun run build && stat -f%z dist/index.js | awk '{exit ($1 > 100000)}'`
- [ ] First paint < 1s: Lighthouse CI check
```

## Failure Handling

When a quality gate fails:

### Quick Fix (< 5 min)
```
Agent fixes immediately, continues iteration
```

### Complex Fix
```
Agent notes in SPEC.md:
"Test X failing because Y. Need to investigate Z."
Continues with other tasks if non-blocking
```

### Blocker
```
Agent moves task to Blocked section:
"- [ ] Task A → Blocked by failing integration test, see notes"
Documents in Notes what needs to happen
Picks different task
```

## Enforced Backpressure Patterns (v1.3.0)

These patterns are now **enforced** in SPEC.md task structure:

### 1. Dependencies First

**The Problem:** Creating files then running tests → "command not found"

**The Solution:** Task 1 is ALWAYS "Install dependencies":

```markdown
#### Phase 1: Setup (MUST COMPLETE BEFORE IMPLEMENTATION)
- [ ] Task 1: Install dependencies and verify all quality gates run
  - Run: `bun install`
  - Verify: `bun test`, `bun lint`, `bun typecheck` all execute
  - **Blocker if skipped**: Cannot run backpressure without dependencies
```

### 2. Tests With Code (Same Iteration)

**The Problem:** Creating tests at the end → no backpressure during implementation

**The Solution:** Each implementation task specifies its test file:

```markdown
- [ ] Task 5: Create Counter component
  - File: `src/components/Counter.svelte`
  - Test: `tests/unit/Counter.test.ts` (CREATE IN SAME ITERATION)
  - Validate: `bun lint && bun typecheck`
```

**Wrong:**
```
Iteration 5: Create Counter.svelte
Iteration 25: Create Counter.test.ts  ← TOO LATE
```

**Right:**
```
Iteration 5: Create Counter.svelte AND Counter.test.ts
```

### 3. Visual Verification for UI

**The Problem:** UI changes without visual confirmation

**The Solution:** UI tasks require agent-browser screenshots:

```markdown
- [ ] Task 8: Create Header component
  - File: `src/components/Header.tsx`
  - Test: `tests/unit/Header.test.tsx`
  - Validate: `bun lint && bun typecheck`
  - Visual: `agent-browser screenshot localhost:3000` (REQUIRED FOR UI)
```

### 4. Validate Per-Task (Not Deferred)

**The Problem:** Running all validation at the end

**The Solution:** SPEC.md now has per-task and per-iteration gates:

```markdown
## Quality Gates

### Per-Task Gates (run after each task)
- [ ] Lint passes on changed files
- [ ] Types check on changed files
- [ ] Related tests pass (the test file you created with the source file)

### Full Gates (run after each iteration)
- [ ] All tests pass: `bun test`
- [ ] Full lint clean: `bun lint`
...
```

## The Philosophy

> "Instead of telling the agent what to do, engineer an environment where wrong outputs get rejected automatically."

Human roles shift from:
- ❌ "Telling the agent what to do"
- ✅ "Engineering conditions where good outcomes emerge naturally through iteration"

The loop handles the corrections. You set up the rails.
