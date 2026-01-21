# feat: Production-Grade Autonomous Development Loop

> Transform ralph-borg into a fire-and-forget autonomous development system with context preservation, self-healing, and quality gates.

---

## Overview

Ralph-borg works. The 2,934-line bash script successfully runs autonomous iteration loops. This plan adds three essential capabilities to achieve true "fire-and-forget after spec creation":

1. **Context Preservation** - Learnings persist across fresh Claude instances
2. **Self-Healing** - Errors are automatically retried with context
3. **Quality Enforcement** - All stacks get auto-detected quality gates

No architectural rewrites. No module explosions. Surgical additions to what already works.

---

## Problem Statement

| Gap | Impact | Fix |
|-----|--------|-----|
| Context doesn't survive across runs | Fresh Claude repeats mistakes | Add `.borg/context.yaml` |
| Errors stop the loop | Human must intervene | Add retry with error in prompt |
| Quality gates aren't universal | Some stacks miss checks | Extend discovery for all stacks |

---

## Non-Goals (YAGNI)

These were in the original plan. They're cut:

- **Module architecture** - Single file with sections is fine
- **YAML SPEC format** - Markdown works, fix the parser if needed
- **Codebase indexing** - Use ripgrep at query time
- **Similarity detection** - Prompt instruction covers it
- **Multi-agent coordination** - Not needed now
- **Metrics dashboard** - Simple logs suffice
- **Tiered quality gates** - One tier: pass or fail

---

## Implementation

### Phase 1: Context Preservation

**Goal:** Learnings survive across `borg implement` runs.

#### Task 1: Create context file structure

Add to `borg`:

```bash
# Context file location
CONTEXT_FILE=".borg/context.yaml"

init_context() {
  if [[ ! -f "$CONTEXT_FILE" ]]; then
    cat > "$CONTEXT_FILE" << 'EOF'
# Ralph-borg accumulated context
# This file persists across iterations

learnings: []
errors_fixed: []
patterns_discovered: []
EOF
  fi
}
```

#### Task 2: Inject context into PROMPT

Edit `templates/PROMPT-template.md`:

```markdown
## Accumulated Context

### Learnings from Previous Iterations
{{learnings}}

### Errors You've Fixed Before (Don't Repeat)
{{errors_fixed}}

### Patterns Discovered in This Codebase
{{patterns_discovered}}
```

Add to `borg` spec command:

```bash
inject_context() {
  local prompt_file="$1"
  local learnings errors patterns

  if [[ -f "$CONTEXT_FILE" ]]; then
    learnings=$(yq -r '.learnings | map("- " + .) | join("\n")' "$CONTEXT_FILE")
    errors=$(yq -r '.errors_fixed | map("- " + .error + " → Fix: " + .fix) | join("\n")' "$CONTEXT_FILE")
    patterns=$(yq -r '.patterns_discovered | map("- " + .) | join("\n")' "$CONTEXT_FILE")
  fi

  sed -i '' \
    -e "s/{{learnings}}/${learnings:-None yet}/g" \
    -e "s/{{errors_fixed}}/${errors:-None yet}/g" \
    -e "s/{{patterns_discovered}}/${patterns:-None yet}/g" \
    "$prompt_file"
}
```

#### Task 3: Update context after iteration

Add to iteration completion:

```bash
add_learning() {
  local learning="$1"
  yq -i ".learnings += [\"$learning\"]" "$CONTEXT_FILE"
}

add_error_fix() {
  local error="$1"
  local fix="$2"
  yq -i ".errors_fixed += [{\"error\": \"$error\", \"fix\": \"$fix\"}]" "$CONTEXT_FILE"
}

add_pattern() {
  local pattern="$1"
  yq -i ".patterns_discovered += [\"$pattern\"]" "$CONTEXT_FILE"
}
```

#### Task 4: Context pruning (keep it bounded)

```bash
CONTEXT_MAX_LEARNINGS=50
CONTEXT_MAX_ERRORS=20
CONTEXT_MAX_PATTERNS=30

prune_context() {
  # Keep only most recent entries
  yq -i ".learnings = .learnings | .[-$CONTEXT_MAX_LEARNINGS:]" "$CONTEXT_FILE"
  yq -i ".errors_fixed = .errors_fixed | .[-$CONTEXT_MAX_ERRORS:]" "$CONTEXT_FILE"
  yq -i ".patterns_discovered = .patterns_discovered | .[-$CONTEXT_MAX_PATTERNS:]" "$CONTEXT_FILE"
}
```

**Success criteria:**
- [x] Context file created on `borg init`
- [x] Context injected into PROMPT.md
- [x] Learnings added after successful iterations
- [x] Context stays under 100 entries total

---

### Phase 2: Self-Healing

**Goal:** Automatically retry failures with error context.

#### Task 1: Add retry-with-context logic

Replace simple retry with context-aware retry:

```bash
MAX_SELF_HEAL_ATTEMPTS=3

run_iteration_with_healing() {
  local spec_dir="$1"
  local attempt=1
  local last_error=""

  while [[ $attempt -le $MAX_SELF_HEAL_ATTEMPTS ]]; do
    log_info "Iteration attempt $attempt/$MAX_SELF_HEAL_ATTEMPTS"

    # Run iteration, capture result
    if output=$(run_claude_iteration "$spec_dir" "$last_error" 2>&1); then
      return 0  # Success
    fi

    last_error="$output"

    # Check if this is a fixable error
    if is_unfixable_error "$last_error"; then
      log_error "Unfixable error encountered, stopping"
      record_blocked_iteration "$spec_dir" "$last_error"
      return 1
    fi

    log_warn "Iteration failed, retrying with error context..."
    add_error_to_prompt "$spec_dir" "$last_error"

    ((attempt++))
  done

  log_error "Max self-heal attempts reached"
  record_blocked_iteration "$spec_dir" "$last_error"
  return 1
}
```

#### Task 2: Error context injection

```bash
add_error_to_prompt() {
  local spec_dir="$1"
  local error="$2"
  local prompt_file="$spec_dir/PROMPT.md"

  # Append error context to prompt
  cat >> "$prompt_file" << EOF

---

## SELF-HEALING CONTEXT

The previous iteration failed with this error:

\`\`\`
$error
\`\`\`

Please:
1. Analyze what went wrong
2. Fix the issue
3. Re-run validation to confirm the fix
4. Continue with the current task

EOF
}
```

#### Task 3: Identify unfixable errors

```bash
is_unfixable_error() {
  local error="$1"

  # These errors require human intervention
  local unfixable_patterns=(
    "API key"
    "authentication failed"
    "permission denied"
    "disk full"
    "out of memory"
    "rate limit exceeded"
    "SIGKILL"
  )

  for pattern in "${unfixable_patterns[@]}"; do
    if [[ "$error" == *"$pattern"* ]]; then
      return 0  # Is unfixable
    fi
  done

  return 1  # Is fixable (or at least worth trying)
}
```

#### Task 4: Record successful fixes for learning

```bash
record_successful_fix() {
  local error="$1"
  local fix_description="$2"

  add_error_fix "$error" "$fix_description"
  log_success "Learned fix: $error → $fix_description"
}
```

**Success criteria:**
- [x] Lint errors auto-fixed on retry
- [x] Test failures retried with error context
- [x] Unfixable errors stop immediately
- [x] Successful fixes recorded in context

---

### Phase 3: Universal Quality Gates

**Goal:** Auto-detect and run quality gates for any stack.

#### Task 1: Extend project discovery

Add comprehensive quality command detection to existing `detect_project_type`:

```bash
discover_quality_commands() {
  local project_type="$1"
  local quality_commands=()

  case "$project_type" in
    bun)
      [[ -n "$(jq -r '.scripts.test // empty' package.json 2>/dev/null)" ]] && \
        quality_commands+=("bun test")
      [[ -n "$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)" ]] && \
        quality_commands+=("bun run lint")
      [[ -n "$(jq -r '.scripts.typecheck // empty' package.json 2>/dev/null)" ]] && \
        quality_commands+=("bun run typecheck")
      [[ -f "tsconfig.json" ]] && quality_commands+=("bun run tsc --noEmit")
      ;;

    npm|yarn|pnpm)
      local runner="npm run"
      [[ "$project_type" == "yarn" ]] && runner="yarn"
      [[ "$project_type" == "pnpm" ]] && runner="pnpm run"

      [[ -n "$(jq -r '.scripts.test // empty' package.json 2>/dev/null)" ]] && \
        quality_commands+=("$runner test")
      [[ -n "$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)" ]] && \
        quality_commands+=("$runner lint")
      [[ -f "tsconfig.json" ]] && quality_commands+=("npx tsc --noEmit")
      ;;

    rails)
      [[ -f "bin/rails" ]] && quality_commands+=("bin/rails test")
      [[ -f ".rubocop.yml" ]] && quality_commands+=("bundle exec rubocop")
      [[ -f "Gemfile" ]] && grep -q "brakeman" Gemfile && \
        quality_commands+=("bundle exec brakeman -q")
      ;;

    python)
      [[ -f "pytest.ini" || -f "pyproject.toml" ]] && quality_commands+=("pytest")
      [[ -f "pyproject.toml" ]] && grep -q "ruff" pyproject.toml && \
        quality_commands+=("ruff check .")
      [[ -f "pyproject.toml" ]] && grep -q "mypy" pyproject.toml && \
        quality_commands+=("mypy .")
      ;;

    go)
      quality_commands+=("go test ./...")
      command -v golangci-lint &>/dev/null && quality_commands+=("golangci-lint run")
      ;;

    rust)
      quality_commands+=("cargo test")
      quality_commands+=("cargo clippy -- -D warnings")
      ;;
  esac

  printf '%s\n' "${quality_commands[@]}"
}
```

#### Task 2: Run all gates, fail on any failure

```bash
run_quality_gates() {
  local project_type="$1"
  local failed=0

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue

    log_step "Running: $cmd"
    if ! eval "$cmd"; then
      log_error "Gate failed: $cmd"
      failed=1
    else
      log_success "Gate passed: $cmd"
    fi
  done < <(discover_quality_commands "$project_type")

  return $failed
}
```

#### Task 3: Add "search before write" to PROMPT

Edit `templates/PROMPT-template.md`, add to Phase 3 (INVESTIGATE):

```markdown
## Phase 3: INVESTIGATE (MANDATORY)

Before writing ANY new code:

1. **Search for existing implementations:**
   - Use grep/ripgrep to find similar function names
   - Check: src/utils/, src/lib/, src/shared/, lib/

2. **If found:**
   - Import and use existing code
   - Extend if needed, document why
   - DO NOT duplicate functionality

3. **If not found:**
   - Proceed with implementation
   - Consider adding to shared location if reusable

**HARD RULE:** Search first. The codebase may already have what you need.
```

**Success criteria:**
- [x] All 6 supported stacks have quality commands discovered
- [x] Gates run after each task completion
- [x] "Search before write" instruction in every PROMPT
- [x] Gates failure triggers self-healing retry

---

## Files Changed

| File | Change |
|------|--------|
| `borg` | +~150 lines (context, healing, gates) |
| `templates/PROMPT-template.md` | +~30 lines (context injection, search-before-write) |

**Total new code:** ~180 lines

---

## Acceptance Criteria

- [x] Fresh Claude instance continues work using context from previous runs
- [x] Lint/test failures retry with error in prompt (up to 3 times)
- [x] Unfixable errors stop immediately with clear message
- [x] Successful fixes are recorded and reused
- [x] All stacks (JS, TS, Ruby, Python, Go, Rust) have quality gates
- [x] "Search before write" instruction in every PROMPT

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Autonomous completion rate | >90% SPECs complete without intervention |
| Self-healing success rate | >70% of lint/test errors fixed on retry |
| Context utilization | Learnings referenced in subsequent iterations |

---

## What We're NOT Doing

Per reviewer consensus:

1. **No module architecture** - Single file stays single file
2. **No YAML SPEC migration** - Markdown works fine
3. **No codebase indexing** - ripgrep at query time
4. **No similarity detection** - Prompt instruction suffices
5. **No multi-agent support** - Add when actually needed
6. **No metrics dashboard** - Logs are enough
7. **No JSON Schema validation** - Simple section checks if needed

---

## Testing

Add to existing test workflow:

```bash
# Test context persistence
test_context_persistence() {
  borg init /tmp/test-project
  echo "learnings: ['test learning']" > /tmp/test-project/.borg/context.yaml
  # Verify context appears in generated PROMPT
  borg spec /tmp/test-project/plans/test.md
  grep -q "test learning" /tmp/test-project/specs/test/PROMPT.md
}

# Test self-healing retry
test_self_healing() {
  # Mock a failing iteration that succeeds on retry
  # Verify retry count and error context injection
}

# Test quality gate discovery
test_quality_gates() {
  for type in bun npm rails python go rust; do
    # Create minimal project structure
    # Verify correct commands discovered
  done
}
```

---

## Implementation Order

1. **Context preservation** (Phase 1) - Foundation for everything else
2. **Self-healing** (Phase 2) - Depends on context for learning
3. **Quality gates** (Phase 3) - Already mostly exists, just extend

Each phase is independently useful. Ship after each.

---

## References

- Current borg script: `borg:1-2934`
- PROMPT template: `templates/PROMPT-template.md:1-585`
- Existing learnings logic: `borg:1847-1892` (`add_learning`, `get_learnings_summary`)
- Existing retry logic: `borg:312-398` (`run_claude_with_retry`)
- Existing project discovery: `borg:1425-1583` (`discover_project`, `detect_project_type`)
