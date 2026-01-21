# Prompting Patterns for Ralph Loops

Specific language patterns that improve agent behavior during autonomous loops.

## Key Phrases

These phrasings have been proven to improve outcomes:

### "study" not "read"

```markdown
❌ "Read the SPEC.md file"
✅ "Study the SPEC.md file"
```

"Study" implies deeper analysis, understanding patterns, not just parsing text.

### "don't assume not implemented"

```markdown
❌ "Implement the login function"
✅ "DON'T ASSUME NOT IMPLEMENTED - search first, then implement the login function"
```

Forces the agent to search the codebase before writing new code. Prevents duplicate implementations.

### "ultrathink"

```markdown
"Before making this architectural decision, ultrathink about the implications."
```

Triggers deeper reasoning, especially useful before complex decisions.

### "capture the why"

```markdown
"Update SPEC.md notes and capture the why behind this approach"
```

Documents reasoning, not just changes. Future iterations benefit from understanding intent.

### "one task per loop"

```markdown
"Select ONE task. Focus beats breadth. Complete it fully before stopping."
```

Enforces focus, prevents context overload from juggling multiple things.

### "parallel subagents"

```markdown
"Use up to 10 parallel subagents for file operations"
```

Explicitly enables parallelization for reads/searches.

### "only 1 subagent for build/tests"

```markdown
"Only 1 subagent for build/test commands (backpressure control)"
```

Prevents parallel test runs from producing confusing output.

## Prompt Structure

### The 0-9-999 Pattern

Prompts follow a structure:

```
0a-0d: Orientation (load context, read files)
1-8:   Main instructions (what to do this iteration)
99+:   Guardrails (what NOT to do, safety rails)
```

Example:
```markdown
## Phase 0a: Orient
Study SPEC.md...

## Phase 0b: Load Context
Read AGENTS.md...

## Phase 1: Select Task
Pick ONE task...

## Phase 2: Investigate
Search before implementing...

## Phase 99: Guardrails
- NEVER modify files outside the feature scope
- NEVER skip tests even if they're slow
- NEVER commit if tests are failing
```

## Completion Criteria

### Binary Success Criteria

Frame completion in binary terms:

```markdown
❌ "Make the code good"
❌ "Improve the implementation"

✅ "Tests pass"
✅ "Lint returns 0 errors"
✅ "Build succeeds"
✅ "All acceptance criteria checked"
```

### Explicit Completion Signal

```markdown
When ALL of these are true:
- All tasks in "Completed" section
- All quality gates passing
- All requirements checked off

Then output: <promise>COMPLETE</promise>
```

The explicit signal prevents ambiguity.

## Task Description Patterns

### Good Task Descriptions

```markdown
- [ ] Create User model with email validation (file: src/models/User.ts)
- [ ] Add POST /api/login endpoint returning JWT (test: src/tests/auth.test.ts)
- [ ] Create LoginForm component with email/password fields (pattern: src/components/SignupForm.tsx)
```

Note:
- Specific deliverable
- Referenced file locations
- Patterns to follow
- Implicit test expectations

### Bad Task Descriptions

```markdown
- [ ] Work on authentication
- [ ] Make login work
- [ ] Add the form
```

Too vague. No clear done state.

## Context Loading Pattern

Start each iteration by loading context explicitly:

```markdown
## Phase 0: Orient

1. **Study** `SPEC.md` - your single source of truth
2. **Study** the plan file referenced in frontmatter
3. **Check** Iteration Log for learnings from past rounds
4. **Study** key files listed in Context section
5. **Study** `AGENTS.md` for build/test commands
```

Order matters: SPEC first (current state), then supporting context.

## Investigation Pattern

Before implementing anything:

```markdown
## Phase 2: Investigate

DON'T ASSUME NOT IMPLEMENTED - search first!

1. Use Grep to find: `[feature-related-terms]`
2. Use Glob to find: `**/[likely-filenames]*`
3. Check if task is already partially done
4. Look for similar patterns in codebase
5. Update SPEC.md Notes with discoveries
```

This prevents:
- Duplicate code
- Reinventing existing utilities
- Missing integration points

## Validation Pattern

Run backpressure explicitly:

```markdown
## Phase 4: Validate

Run ALL quality gates. Fix issues before continuing.

```bash
bun test              # Must pass
bun run lint          # Must pass
bun run typecheck     # Must pass
bun run build         # Must succeed
```

If any fail:
- Quick fix (< 5 min) → Fix now
- Complex fix → Note and continue if non-blocking
- Blocker → Move task to Blocked, pick another
```

## State Update Pattern

Explicit state management:

```markdown
## Phase 5: Update State

1. Move task to "Completed" with iteration number
2. Add learnings to "Notes" section:
   - What worked
   - What didn't work
   - Patterns discovered
   - Gotchas for future iterations
3. Increment `iteration_count` in frontmatter
4. Add entry to "Iteration Log"
```

This ensures the next iteration has context from this one.

## Anti-Patterns to Avoid

### 1. Vague Instructions

```markdown
❌ "Build the feature"
✅ "Implement Task X from the Pending list, following the pattern in existing-file.ts"
```

### 2. Multiple Tasks

```markdown
❌ "Complete tasks 1, 2, and 3"
✅ "Complete the ONE task marked 'In Progress'"
```

### 3. No Escape Hatch

```markdown
❌ "Keep working until done"
✅ "Work until done OR max 50 iterations OR blocked"
```

### 4. Subjective Success

```markdown
❌ "Make it work well"
✅ "Tests pass AND lint passes AND build succeeds"
```

### 5. No Context Persistence

```markdown
❌ (Relying on conversation memory)
✅ "Update SPEC.md Notes with this learning before continuing"
```
