---
name: _reviews-fixes-design
status: building
created: 2026-01-22
parent_spec: _reviews
fix_type: design
todo_count: 12
iteration_count: 1
project_type: unknown
---

# Fix: _reviews (design)

## Overview

This spec addresses 12 design findings from review of _reviews.

## Requirements

- [ ] Hero headline uses a distinctive, characterful display font
- [ ] Control panel has visual connection to hero section and depth
- [ ] Dashboard empty spaces have subtle visual texture or gradient
- [ ] View tabs have distinctive visual styling with smooth transitions
- [ ] Settings drawer has visual personality matching main app
- [ ] Light mode has warm, inviting feel (not sterile white)
- [ ] Mobile landing page controls meet touch target requirements
- [ ] Library sidebar thumbnails have polished visual treatment
- [ ] Generate button draws the eye with subtle animations
- [ ] Details panel has clear visual hierarchy for scanning
- [ ] Header/logo has distinctive, memorable brand presence
- [ ] Dashboard mobile layout is clear and uncluttered

## Tasks

### Pending

#### Phase 1: Setup
- [x] Task 1: Verify dependencies and quality gates work (Iteration 1)
  - Run: Install any missing dependencies
  - Verify: All lint/test commands execute

#### Phase 2: Fixes (ordered by priority - P1 first, then P2, then P3)

- [ ] Task 2: Fix generic hero typography lacking distinctive character
  - File: Landing page hero section (http://localhost:3000/)
  - Reference: `todos/design/001-p2-generic-hero-typography.md`
  - Acceptance:
    - [ ] Headline uses a distinctive, characterful display font
    - [ ] Font choice reflects the creative/artistic nature of the product
    - [ ] Clear visual hierarchy between headline and body text
    - [ ] Typography has personality that differentiates from generic AI tools

- [ ] Task 3: Fix control panel disconnected from hero section
  - File: Landing page control panel (http://localhost:3000/)
  - Reference: `todos/design/002-p2-disconnected-control-panel.md`
  - Acceptance:
    - [ ] Clear visual connection between hero section and control panel
    - [ ] Control panel has depth and doesn't feel like a flat, disconnected element
    - [ ] Background has visual interest (not just solid dark color)
    - [ ] Overall composition feels cohesive and intentionally designed

- [ ] Task 4: Fix dashboard large underutilized empty dark areas
  - File: Dashboard workspace area (http://localhost:3000/dashboard)
  - Reference: `todos/design/003-p2-dashboard-empty-space.md`
  - Acceptance:
    - [ ] No large areas of pure, flat black in the interface
    - [ ] Empty spaces have subtle visual texture or gradient
    - [ ] Background treatment complements artwork without distracting
    - [ ] Workspace feels like a creative studio, not a void

- [ ] Task 5: Fix view tabs feeling generic
  - File: Dashboard view tabs (http://localhost:3000/dashboard)
  - Reference: `todos/design/004-p2-view-tabs-lack-polish.md`
  - Acceptance:
    - [ ] Tabs have distinctive visual styling that matches app aesthetic
    - [ ] Active tab is clearly distinguished with more than just color
    - [ ] Smooth transitions between tab states
    - [ ] Keyboard shortcuts are styled attractively (not plain text)

- [ ] Task 6: Fix light mode appearing washed out and generic
  - File: Dashboard light mode styles (http://localhost:3000/dashboard)
  - Reference: `todos/design/006-p2-light-mode-washed-out.md`
  - Acceptance:
    - [ ] Light mode has a warm, inviting feel (not sterile white)
    - [ ] Accent colors work well against light backgrounds
    - [ ] Components maintain visual interest without dark mode glow effects
    - [ ] Light mode feels like a deliberate design choice, not an inversion

- [ ] Task 7: Fix mobile view cramped control options
  - File: Landing page mobile responsive styles (http://localhost:3000/)
  - Reference: `todos/design/007-p2-mobile-cramped-controls.md`
  - Acceptance:
    - [ ] All interactive elements meet 44x44px minimum touch target
    - [ ] Controls are spaced comfortably for touch interaction
    - [ ] Mobile layout feels intentionally designed, not just squished desktop
    - [ ] Advanced options are accessible but don't crowd essential controls

- [ ] Task 8: Fix generate button lacking visual impact
  - File: Generate button component (http://localhost:3000/ and /dashboard)
  - Reference: `todos/design/009-p2-generate-button-could-shine.md`
  - Acceptance:
    - [ ] Generate button immediately draws the eye as the primary action
    - [ ] Subtle animation in idle state creates visual interest
    - [ ] Hover state clearly communicates "ready to click"
    - [ ] Loading state provides delightful feedback during generation
    - [ ] Disabled state is clear but not jarring

- [ ] Task 9: Fix dashboard mobile layout being overwhelming
  - File: Dashboard mobile responsive styles (http://localhost:3000/dashboard)
  - Reference: `todos/design/012-p2-dashboard-mobile-overwhelming.md`
  - Acceptance:
    - [ ] Mobile dashboard has a clear, uncluttered layout
    - [ ] Primary content (generated image) is prominently displayed
    - [ ] All features remain accessible via intuitive navigation
    - [ ] Touch targets are appropriately sized
    - [ ] The experience feels designed for mobile, not squeezed from desktop

- [ ] Task 10: Fix settings drawer having purely functional design
  - File: Settings drawer component (http://localhost:3000/)
  - Reference: `todos/design/005-p3-settings-drawer-plain.md`
  - Acceptance:
    - [ ] Settings drawer has visual personality matching main app
    - [ ] Form inputs are styled beyond browser defaults
    - [ ] Section headers have clear visual hierarchy
    - [ ] Overall drawer feels like part of a premium creative tool

- [ ] Task 11: Fix library sidebar thumbnails needing visual enhancement
  - File: Dashboard sidebar thumbnails (http://localhost:3000/dashboard)
  - Reference: `todos/design/008-p3-sidebar-thumbnails-plain.md`
  - Acceptance:
    - [ ] Thumbnails have polished visual treatment (shadows, rounded corners)
    - [ ] Clear hover and selection states
    - [ ] Micro-interactions add delight without being distracting
    - [ ] Library feels like a curated gallery, not a file list

- [ ] Task 12: Fix details panel dense, hard-to-scan text
  - File: Dashboard details panel (http://localhost:3000/dashboard)
  - Reference: `todos/design/010-p3-details-panel-dense-text.md`
  - Acceptance:
    - [ ] Clear visual hierarchy makes scanning information easy
    - [ ] Sections are visually distinct from each other
    - [ ] Labels are clearly differentiated from values
    - [ ] Long text content (prompts) is handled gracefully

- [ ] Task 13: Fix header/logo lacking strong brand presence
  - File: Header component (http://localhost:3000/ and /dashboard)
  - Reference: `todos/design/011-p3-header-lacks-brand-presence.md`
  - Acceptance:
    - [ ] Logo has a distinctive, memorable appearance
    - [ ] Brand identity is consistent across landing page and dashboard
    - [ ] Logo works at multiple sizes (header, favicon, mobile)
    - [ ] Brand presence establishes trust and professionalism

#### Phase 3: Verification
- [ ] Task 14: Run full test suite and verify all fixes work
  - Run: Full test suite
  - Validate: All quality gates pass

### In Progress

### Completed
- [x] Task 1: Verify dependencies and quality gates work (Iteration 1)
  - Dependencies installed successfully (no changes needed)
  - Typecheck: PASS
  - Tests: 490 pass, 0 fail

### Blocked

## Quality Gates

### Per-Task Gates
- [ ] Lint passes on changed files
- [ ] Types check on changed files
- [ ] Related tests pass

### Full Gates
- [ ] Tests pass
- [ ] Lint clean

## Exit Criteria

- [ ] All requirements checked off
- [ ] All quality gates pass
- [ ] All tasks completed
- [ ] Code committed with meaningful messages

## Context

### Parent Spec
_reviews

### Source Todos

| Priority | Todo File | Issue |
|----------|-----------|-------|
| P2 | todos/design/001-p2-generic-hero-typography.md | Generic hero typography lacks distinctive character |
| P2 | todos/design/002-p2-disconnected-control-panel.md | Control panel feels disconnected from hero section |
| P2 | todos/design/003-p2-dashboard-empty-space.md | Dashboard has large underutilized empty dark areas |
| P2 | todos/design/004-p2-view-tabs-lack-polish.md | View tabs feel generic |
| P2 | todos/design/006-p2-light-mode-washed-out.md | Light mode appears washed out and generic |
| P2 | todos/design/007-p2-mobile-cramped-controls.md | Mobile view has cramped control options |
| P2 | todos/design/009-p2-generate-button-could-shine.md | Generate button needs more visual impact |
| P2 | todos/design/012-p2-dashboard-mobile-overwhelming.md | Dashboard mobile layout is overwhelming |
| P3 | todos/design/005-p3-settings-drawer-plain.md | Settings drawer has purely functional design |
| P3 | todos/design/008-p3-sidebar-thumbnails-plain.md | Library sidebar thumbnails need visual enhancement |
| P3 | todos/design/010-p3-details-panel-dense-text.md | Details panel has dense, hard-to-scan text |
| P3 | todos/design/011-p3-header-lacks-brand-presence.md | Header/logo lacks strong brand presence |

### Notes

These fixes originated from design review of _reviews.
Re-run `cr review` after fixes to verify issues are resolved.

## Iteration Log

### Iteration 1
- Task: Verify dependencies and quality gates work (Task 1)
- Status: COMPLETED
- Actions: Ran `bun install`, `bun typecheck`, `bun test`
- Results: All quality gates pass (490 tests, typecheck clean)
- Target project: `/Users/marcus/Desktop/coding-projects/ani-cli/`
