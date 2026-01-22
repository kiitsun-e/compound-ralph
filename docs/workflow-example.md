# Complete Workflow Example

This document walks through a complete feature implementation using Compound Ralph.

## Scenario

You want to add a "dark mode toggle" to your Bun/React application.

## Step 1: Initialize Project

```bash
cd ~/projects/my-app
cr init
```

Output:
```
=== Initializing Compound Ralph in /Users/marcus/projects/my-app ===

[INFO] Detected project type: bun
[SUCCESS] Created specs/ and plans/ directories
[SUCCESS] Created AGENTS.md with bun commands

Next steps:
  1. Review and customize AGENTS.md with your project's commands
  2. Create a plan:    cr plan "your feature description"
  3. Convert to spec:  cr spec plans/your-feature.md
  4. Implement:        cr implement specs/your-feature/
```

## Step 2: Review AGENTS.md

Check the auto-generated commands:

```bash
cat AGENTS.md
```

```markdown
# AGENTS.md - Operational Guide

## Build
bun install
bun run build

## Test
bun test
bun test --coverage

## Lint & Type Check
bun run lint
bun run lint --fix
bun run typecheck

## Development
bun run dev

## Learnings
<!-- Add project-specific learnings here -->
```

Customize if needed (e.g., add `bun run test:e2e` if you have E2E tests).

## Step 3: Create Rich Plan

```bash
cr plan "add dark mode toggle with system preference detection and localStorage persistence"
```

This runs:
1. `/workflows:plan` - Creates structured plan
2. `/deepen-plan` - Enriches with 40+ parallel research agents

Output includes:
- Best practices for dark mode implementation
- Existing patterns in your codebase
- Framework-specific guidance (React, CSS-in-JS, etc.)
- Key files to modify

The plan is saved to `plans/add-dark-mode-toggle-with-system-preference-detection.md`

## Step 4: Convert to SPEC

```bash
cr spec plans/add-dark-mode-toggle-with-system-preference-detection.md
```

Creates:
- `specs/add-dark-mode-toggle-with-system-preference-detection/SPEC.md`
- `specs/add-dark-mode-toggle-with-system-preference-detection/PROMPT.md`

## Step 5: Refine the SPEC

Edit `specs/add-dark-mode-toggle-with-system-preference-detection/SPEC.md`:

```markdown
---
name: add-dark-mode-toggle-with-system-preference-detection
status: pending
created: 2026-01-21
plan_file: plans/add-dark-mode-toggle-with-system-preference-detection.md
iteration_count: 0
project_type: bun
---

# Feature: Dark Mode Toggle

## Overview

Add a dark mode toggle that respects system preferences, persists user choice
to localStorage, and smoothly transitions between themes.

## Requirements

- [ ] Toggle switches between light and dark modes
- [ ] Respects system preference (prefers-color-scheme) by default
- [ ] User preference persists across sessions via localStorage
- [ ] Smooth transition animation when switching
- [ ] No flash of wrong theme on page load

## Tasks

### Pending

- [ ] Create useTheme hook with localStorage + system preference logic
- [ ] Add CSS custom properties for theme colors
- [ ] Create ThemeToggle component
- [ ] Integrate hook at app root level
- [ ] Add theme class to document element
- [ ] Write unit tests for useTheme hook
- [ ] Write component tests for ThemeToggle
- [ ] Add transition styles for smooth switching

### In Progress

### Completed

### Blocked

## Quality Gates

- [ ] Tests pass: `bun test`
- [ ] Lint clean: `bun run lint`
- [ ] Types check: `bun run typecheck`
- [ ] Build succeeds: `bun run build`
- [ ] Visual check: Theme toggle works in browser

## Exit Criteria

- [ ] All requirements checked off
- [ ] All quality gates pass
- [ ] All tasks completed
- [ ] No flash of wrong theme on load
- [ ] Toggle works on desktop and mobile

## Context

### Key Files

- `src/hooks/useTheme.ts` - New hook to create
- `src/components/ThemeToggle.tsx` - New component
- `src/styles/theme.css` - CSS custom properties
- `src/App.tsx` - Integration point
- `src/tests/useTheme.test.ts` - Tests

### Patterns to Follow

- Existing hooks in `src/hooks/useLocalStorage.ts`
- Component style from `src/components/Button.tsx`
- Test patterns in `src/tests/useAuth.test.ts`

### Notes

## Iteration Log
```

## Step 6: Start Implementation

```bash
cr implement
```

The loop begins:

```
=== Starting Compound Ralph Loop ===
Spec:           specs/add-dark-mode-toggle-with-system-preference-detection/SPEC.md
Max iterations: 50
Delay:          3s between iterations

Press Ctrl+C to stop at any time.

=== Iteration 1 (2026-01-21 14:30:22) ===

[Agent reads SPEC.md, selects first task]
[Moves "Create useTheme hook" to In Progress]
[Creates src/hooks/useTheme.ts]
[Creates src/tests/useTheme.test.ts]
[Runs bun test - passes]
[Runs bun run lint - passes]
[Runs bun run typecheck - passes]
[Moves task to Completed]
[Updates iteration_count to 1]
[Commits: "feat(dark-mode): add useTheme hook with localStorage persistence"]

[INFO] Waiting 3s before next iteration...

=== Iteration 2 (2026-01-21 14:32:45) ===

[Agent reads updated SPEC.md]
[Selects "Add CSS custom properties for theme colors"]
[Moves to In Progress]
[Creates src/styles/theme.css]
[Updates tailwind.config.ts with theme colors]
...
```

## Step 7: Monitor Progress

Check status anytime:

```bash
cr status
```

```
=== Compound Ralph Status ===

Spec                                           Status      Iterations  Tasks
----                                           ------      ----------  -----
add-dark-mode-toggle-with-system-preference    building    4           4/8
```

Check iteration history:

```bash
ls specs/add-dark-mode-toggle-with-system-preference-detection/.history/
# 001-20260121-143022.md
# 002-20260121-143245.md
# 003-20260121-143512.md
# 004-20260121-143738.md
```

## Step 8: Completion

After ~8 iterations, all tasks complete:

```
=== Iteration 8 (2026-01-21 14:52:18) ===

[Agent verifies all tasks complete]
[All quality gates pass]
[All requirements checked]
[Updates status to complete]

<promise>COMPLETE</promise>

[SUCCESS] Feature complete after 8 iterations!

Next steps:
  1. Review changes: git diff main
  2. Run final review: claude /workflows:review
  3. Document learnings: claude /workflows:compound
  4. Create PR when ready
```

## Step 9: Post-Completion

### Review the Changes

```bash
git log --oneline main..HEAD
# a1b2c3d feat(dark-mode): add ThemeToggle to header
# d4e5f6g feat(dark-mode): add transition animations
# g7h8i9j feat(dark-mode): integrate useTheme at app root
# ...
```

### Run Final Review

```bash
claude "/workflows:review"
```

This runs 13+ review agents in parallel to catch anything missed.

### Document Learnings

```bash
claude "/workflows:compound"
```

If you discovered useful patterns, this captures them for future use.

### Create PR

```bash
git push -u origin feature/dark-mode
gh pr create --title "Add dark mode toggle" --body "..."
```

## The SPEC After Completion

```markdown
---
name: add-dark-mode-toggle-with-system-preference-detection
status: complete
created: 2026-01-21
plan_file: plans/add-dark-mode-toggle-with-system-preference-detection.md
iteration_count: 8
project_type: bun
---

# Feature: Dark Mode Toggle

## Overview

Add a dark mode toggle that respects system preferences, persists user choice
to localStorage, and smoothly transitions between themes.

## Requirements

- [x] Toggle switches between light and dark modes
- [x] Respects system preference (prefers-color-scheme) by default
- [x] User preference persists across sessions via localStorage
- [x] Smooth transition animation when switching
- [x] No flash of wrong theme on page load

## Tasks

### Pending

### In Progress

### Completed

- [x] Create useTheme hook with localStorage + system preference logic (iteration 1)
- [x] Add CSS custom properties for theme colors (iteration 2)
- [x] Create ThemeToggle component (iteration 3)
- [x] Integrate hook at app root level (iteration 4)
- [x] Add theme class to document element (iteration 4)
- [x] Write unit tests for useTheme hook (iteration 1)
- [x] Write component tests for ThemeToggle (iteration 5)
- [x] Add transition styles for smooth switching (iteration 6)

### Blocked

## Quality Gates

- [x] Tests pass: `bun test`
- [x] Lint clean: `bun run lint`
- [x] Types check: `bun run typecheck`
- [x] Build succeeds: `bun run build`
- [x] Visual check: Theme toggle works in browser

## Exit Criteria

- [x] All requirements checked off
- [x] All quality gates pass
- [x] All tasks completed
- [x] No flash of wrong theme on load
- [x] Toggle works on desktop and mobile

## Context

### Key Files

- `src/hooks/useTheme.ts` - Theme management hook
- `src/components/ThemeToggle.tsx` - Toggle button component
- `src/styles/theme.css` - CSS custom properties
- `src/App.tsx` - Integration point
- `src/tests/useTheme.test.ts` - Hook tests
- `src/tests/ThemeToggle.test.tsx` - Component tests

### Patterns to Follow

- Existing hooks in `src/hooks/useLocalStorage.ts`
- Component style from `src/components/Button.tsx`

### Notes

- Iteration 2: Used CSS custom properties instead of Tailwind's dark: prefix for more control
- Iteration 4: Added inline script in index.html to prevent flash (runs before React)
- Iteration 6: Used 150ms transition, faster feels snappier

## Iteration Log

### Iteration 1 (2026-01-21 14:30)
**Task:** Create useTheme hook
**Result:** Success - hook created with localStorage + matchMedia
**Learnings:** Used useSyncExternalStore for system preference sync

### Iteration 2 (2026-01-21 14:32)
**Task:** Add CSS custom properties
**Result:** Success - theme vars in :root and .dark
**Learnings:** CSS custom properties better than Tailwind dark: for dynamic themes

### Iteration 3 (2026-01-21 14:35)
**Task:** Create ThemeToggle component
**Result:** Success - toggle with sun/moon icons
**Learnings:** Used existing Icon component pattern

### Iteration 4 (2026-01-21 14:37)
**Task:** Integrate at app root + add theme class
**Result:** Success - useTheme in App, class on documentElement
**Learnings:** Added inline script to index.html to prevent FOUC

### Iteration 5 (2026-01-21 14:42)
**Task:** Write component tests
**Result:** Success - 5 tests for toggle behavior
**Learnings:** Mocked matchMedia for testing system preference

### Iteration 6 (2026-01-21 14:45)
**Task:** Add transition styles
**Result:** Success - smooth 150ms transitions
**Learnings:** 150ms feels snappier than 300ms, avoid transitions on load

### Iteration 7 (2026-01-21 14:48)
**Task:** Final verification and cleanup
**Result:** Success - all gates pass
**Learnings:** None

### Iteration 8 (2026-01-21 14:52)
**Task:** Verify exit criteria
**Result:** Complete - all requirements met
**Learnings:** Feature complete, ready for review
```

## Summary

| Phase | Human Effort | Agent Effort |
|-------|-------------|--------------|
| Planning | Review and refine plan | Generate and enrich plan |
| SPEC Creation | Customize tasks and context | Convert plan to format |
| Implementation | Ctrl+C if needed | 8 iterations, ~25 minutes |
| Review | Final approval | Automated code review |

Total human time: ~15 minutes of review/customization
Total feature time: ~30 minutes start to PR-ready
