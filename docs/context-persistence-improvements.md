# Compound Ralph Context Persistence: Improvement Roadmap

Based on a thorough analysis of the `cr` script, templates, and real-world usage data.

---

## Table of Contents

- [Part 1: Improvements to CR Alone (No Tasks)](#part-1-improvements-to-cr-alone-no-tasks)
  - [1.1 Fix the Dead `{{ACCUMULATED_CONTEXT}}` Placeholder](#11-fix-the-dead-accumulated_context-placeholder)
  - [1.2 Capture Successful Learnings (Not Just Failures)](#12-capture-successful-learnings-not-just-failures)
  - [1.3 Inject Previous Iteration Summary](#13-inject-previous-iteration-summary)
  - [1.4 Smart Error Context Injection](#14-smart-error-context-injection)
  - [1.5 Git-Aware Context](#15-git-aware-context)
  - [1.6 Structured Knowledge Base](#16-structured-knowledge-base)
  - [1.7 Refresh Context in PROMPT.md Before Each Iteration](#17-refresh-context-in-promptmd-before-each-iteration)
  - [1.8 Cross-Feature Learning Inheritance](#18-cross-feature-learning-inheritance)
  - [1.9 Iteration Health Scoring](#19-iteration-health-scoring)
  - [1.10 Summary: CR-Only Improvements](#110-summary-cr-only-improvements-implementation-order)
- [Part 2: Improvements with Claude Code Task System](#part-2-improvements-with-claude-code-task-system)
  - [2.0 Critical: Task List Persistence via CLAUDE_CODE_TASK_LIST_ID](#20-critical-task-list-persistence-via-claude_code_task_list_id)
  - [2.1 Architecture: Hybrid CR + Tasks](#21-architecture-hybrid-cr--tasks)
  - [2.2 Learning Tasks: Structured Knowledge Persistence](#22-learning-tasks-structured-knowledge-persistence)
  - [2.3 Three-Phase Iteration with Specialized Agents](#23-three-phase-iteration-with-specialized-agents)
  - [2.4 Smart Context Querying](#24-smart-context-querying)
  - [2.5 Relevance Scoring: Learning from Usage](#25-relevance-scoring-learning-from-usage)
  - [2.6 Cross-Feature Learning with Task Dependencies](#26-cross-feature-learning-with-task-dependencies)
  - [2.7 Parallel Backpressure Verification](#27-parallel-backpressure-verification)
  - [2.8 Feature Tasks with Work Items](#28-feature-tasks-with-work-items)
  - [2.9 Learning Lifecycle Management](#29-learning-lifecycle-management)
  - [2.10 Summary: Task System Integration Benefits](#210-summary-task-system-integration-benefits)
- [Part 3: General Thoughts](#part-3-general-thoughts)

---

## Current State Analysis

### What's Supposed to Exist

The PROMPT-template.md describes these persistence mechanisms:

1. `SPEC.md` - Tasks, requirements, notes
2. `.cr/project.json` - Discovered commands and config
3. `.cr/learnings.json` - Learnings from previous iterations
4. `.cr/context.yaml` - Accumulated context (learnings, error fixes, patterns)
5. `git commits` - Code changes
6. `{{ACCUMULATED_CONTEXT}}` - Placeholder for injected context

### What Actually Works

| Mechanism | Status | Evidence |
|-----------|--------|----------|
| `.cr/project.json` | ✅ Works | Contains discovered commands |
| `.cr/learnings.json` | ⚠️ Partial | Only populated on failures |
| `.cr/context.yaml` | ❌ Empty | Real files show empty arrays |
| `{{ACCUMULATED_CONTEXT}}` | ❌ Dead | Never replaced in code |
| `SPEC.md` Notes | ⚠️ Manual | Depends on Claude updating it |

### Root Causes

1. **Line 1947-1949**: Template copied without substitution
2. **`add_learning()` only called on failures**: Lines 876, 2347
3. **Relies on Claude running jq**: Unreliable execution
4. **No output parsing**: Script doesn't extract learnings from Claude's output

---

## Part 1: Improvements to CR Alone (No Tasks)

These improvements work entirely within the existing CR architecture—bash script modifications, template updates, and new parsing logic.

---

### 1.1 Fix the Dead `{{ACCUMULATED_CONTEXT}}` Placeholder

**The Problem:**

Line 1947-1949 of `cr` copies the template verbatim:

```bash
cp "$CR_DIR/templates/PROMPT-template.md" "$spec_dir/PROMPT.md"
```

The `{{ACCUMULATED_CONTEXT}}` placeholder in PROMPT-template.md is never replaced. It sits there as literal text.

**The Fix:**

Add substitution after copying:

```bash
# In cmd_spec(), after line 1949:
if [[ -f "$spec_dir/PROMPT.md" ]]; then
    local accumulated_ctx
    accumulated_ctx=$(get_context_for_prompt 2>/dev/null || echo "No accumulated context yet.")

    # Escape special characters for sed
    local escaped_ctx
    escaped_ctx=$(printf '%s' "$accumulated_ctx" | sed 's/[&/\]/\\&/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    # Replace placeholder
    sed -i '' "s|{{ACCUMULATED_CONTEXT}}|$escaped_ctx|g" "$spec_dir/PROMPT.md" 2>/dev/null || \
    sed -i "s|{{ACCUMULATED_CONTEXT}}|$escaped_ctx|g" "$spec_dir/PROMPT.md"

    log_info "Injected accumulated context into PROMPT.md"
fi
```

**Impact:** PROMPT.md now contains actual context from previous features/iterations when the spec is created.

---

### 1.2 Capture Successful Learnings (Not Just Failures)

**The Problem:**

Currently `add_learning()` is only called on failures (lines 876, 2347). Real `.cr/learnings.json` files confirm this—they only contain `iteration_failure` entries.

**The Fix:**

Add structured output markers and parse them from Claude's output.

**Step A: Update PROMPT-template.md with output markers:**

```markdown
---

## Output Markers (REQUIRED)

When you complete work, output these markers so learnings persist to the next iteration:

### After completing a task successfully:
```
COMPLETED: <task description>
FILES: <comma-separated list of files created/modified>
TESTS: <comma-separated list of test files created>
```

### When you discover something useful:
```
LEARNING: <what you learned>
```

### When you discover a codebase pattern:
```
PATTERN: <pattern description>
```

### When you fix an error:
```
FIXED: <error message> → <how you fixed it>
```

### When you hit a blocker:
```
BLOCKER: <what's blocking> | NEEDS: <what's needed to unblock>
```

These markers are parsed automatically. Your learnings help future iterations.
```

**Step B: Add parsing function to `cr`:**

```bash
#=============================================================================
# OUTPUT PARSING (Extract learnings from Claude's output)
#=============================================================================

parse_iteration_output() {
    local log_file="$1"
    local spec_name="$2"
    local iteration="$3"

    [[ ! -f "$log_file" ]] && return

    # Extract LEARNING markers
    grep -oE "^LEARNING: .+" "$log_file" 2>/dev/null | while IFS= read -r line; do
        local learning="${line#LEARNING: }"
        add_learning "discovery" "$learning" "" "$spec_name" "$iteration"
        add_context_learning "$learning"
        log_info "Captured learning: ${learning:0:50}..."
    done

    # Extract PATTERN markers
    grep -oE "^PATTERN: .+" "$log_file" 2>/dev/null | while IFS= read -r line; do
        local pattern="${line#PATTERN: }"
        add_context_pattern "$pattern"
        log_info "Captured pattern: ${pattern:0:50}..."
    done

    # Extract FIXED markers (error → solution pairs)
    grep -oE "^FIXED: .+ → .+" "$log_file" 2>/dev/null | while IFS= read -r line; do
        local content="${line#FIXED: }"
        local error_part=$(echo "$content" | sed 's/ → .*//')
        local fix_part=$(echo "$content" | sed 's/.* → //')
        add_context_error_fix "$error_part" "$fix_part"
        add_learning "fix" "Fixed: $error_part → $fix_part" "" "$spec_name" "$iteration"
        log_info "Captured fix: ${error_part:0:30} → ${fix_part:0:30}"
    done

    # Extract COMPLETED markers for success tracking
    grep -oE "^COMPLETED: .+" "$log_file" 2>/dev/null | while IFS= read -r line; do
        local task="${line#COMPLETED: }"
        add_learning "success" "Completed: $task" "" "$spec_name" "$iteration"
    done

    # Extract BLOCKER markers
    grep -oE "^BLOCKER: .+ \| NEEDS: .+" "$log_file" 2>/dev/null | while IFS= read -r line; do
        local content="${line#BLOCKER: }"
        add_learning "blocker" "$content" "" "$spec_name" "$iteration"
    done

    # Prune context to keep it bounded
    prune_context
}
```

**Step C: Call the parser after each iteration (in cmd_implement, after line ~2358):**

```bash
# After the iteration completes successfully
parse_iteration_output "$log_file" "$(basename "$spec_dir")" "$iteration"
```

**Impact:** Successful learnings, patterns, and fixes are now captured automatically without relying on Claude to run jq commands.

---

### 1.3 Inject Previous Iteration Summary

**The Problem:**

Each iteration starts fresh with no summary of what happened last time. Claude has to re-read everything.

**The Fix:**

Generate and inject a summary of the previous iteration.

```bash
#=============================================================================
# ITERATION SUMMARIES
#=============================================================================

generate_iteration_summary() {
    local log_file="$1"

    [[ ! -f "$log_file" ]] && return

    # Extract key metrics from the log
    local completed_tasks=$(grep -c "^COMPLETED:" "$log_file" 2>/dev/null || echo "0")
    local files_created=$(grep -oE "^FILES: .+" "$log_file" 2>/dev/null | head -1 | sed 's/FILES: //')
    local tests_created=$(grep -oE "^TESTS: .+" "$log_file" 2>/dev/null | head -1 | sed 's/TESTS: //')
    local learnings_count=$(grep -c "^LEARNING:" "$log_file" 2>/dev/null || echo "0")
    local fixes_count=$(grep -c "^FIXED:" "$log_file" 2>/dev/null || echo "0")
    local blockers=$(grep -oE "^BLOCKER: [^|]+" "$log_file" 2>/dev/null | head -1 | sed 's/BLOCKER: //')

    # Get the last task that was worked on
    local last_task=$(grep -oE "Move.*to.*In Progress|Working on:.*" "$log_file" 2>/dev/null | tail -1)

    cat << EOF
## Previous Iteration Summary

| Metric | Value |
|--------|-------|
| Tasks completed | $completed_tasks |
| Files created/modified | ${files_created:-None recorded} |
| Tests created | ${tests_created:-None recorded} |
| Learnings captured | $learnings_count |
| Errors fixed | $fixes_count |
| Blockers | ${blockers:-None} |

EOF
}

get_previous_iteration_log() {
    local history_dir="$1"
    local current_iteration="$2"

    local prev_iteration=$((current_iteration - 1))
    if [[ $prev_iteration -gt 0 ]]; then
        local prev_log=$(find "$history_dir" -name "$(printf '%03d' $prev_iteration)-*.md" 2>/dev/null | head -1)
        echo "$prev_log"
    fi
}
```

**Inject into iteration prompt (modify line ~2269):**

```bash
# Get previous iteration summary
local prev_summary=""
local prev_log=$(get_previous_iteration_log "$history_dir" "$iteration")
if [[ -n "$prev_log" ]] && [[ -f "$prev_log" ]]; then
    prev_summary=$(generate_iteration_summary "$prev_log")
fi

# Create the iteration prompt with summary
local iteration_prompt="You are in iteration $iteration of a Compound Ralph implementation loop.

$prev_summary

CRITICAL INSTRUCTIONS:
..."
```

**Impact:** Each iteration starts with a concise summary of what happened before, reducing redundant file reads and providing immediate context.

---

### 1.4 Smart Error Context Injection

**The Problem:**

When an error recurs, Claude has to figure out the fix again. The error→fix memory exists in `context.yaml` but isn't intelligently queried.

**The Fix:**

When an iteration has pending issues, search for similar past fixes and inject them.

```bash
#=============================================================================
# SMART ERROR MATCHING
#=============================================================================

find_similar_error_fixes() {
    local current_error="$1"
    local max_results="${2:-3}"

    [[ ! -f "$CONTEXT_FILE" ]] && return

    # Normalize error for matching (lowercase, remove line numbers, paths)
    local normalized_error
    normalized_error=$(echo "$current_error" | tr '[:upper:]' '[:lower:]' | sed 's/:[0-9]*//g' | sed 's|/[^ ]*||g')

    # Extract key error terms
    local error_terms=$(echo "$normalized_error" | grep -oE "(cannot find|undefined|not found|failed|error|missing|invalid|unexpected)" | head -3 | tr '\n' '|' | sed 's/|$//')

    if [[ -z "$error_terms" ]]; then
        # Fallback: use first significant words
        error_terms=$(echo "$normalized_error" | tr -cs '[:alpha:]' '\n' | grep -E '^[a-z]{4,}$' | head -3 | tr '\n' '|' | sed 's/|$//')
    fi

    [[ -z "$error_terms" ]] && return

    # Search context.yaml for matching errors
    if command -v yq &>/dev/null; then
        yq -r ".errors_fixed[] | select(.error | test(\"$error_terms\"; \"i\")) | \"Previously fixed: \" + .error + \"\n  Solution: \" + .fix + \"\n\"" "$CONTEXT_FILE" 2>/dev/null | head -$((max_results * 3))
    fi
}

# Also search learnings.json for fix-type learnings
find_similar_fixes_in_learnings() {
    local current_error="$1"
    local learnings_file=".cr/learnings.json"

    [[ ! -f "$learnings_file" ]] && return

    if command -v jq &>/dev/null; then
        # Search for fix-category learnings that mention similar terms
        local search_terms=$(echo "$current_error" | tr -cs '[:alpha:]' '\n' | grep -E '^[a-zA-Z]{4,}$' | head -5 | tr '\n' '|' | sed 's/|$//')
        [[ -z "$search_terms" ]] && return

        jq -r ".learnings[] | select(.category == \"fix\") | select(.learning | test(\"$search_terms\"; \"i\")) | \"- \" + .learning" "$learnings_file" 2>/dev/null | head -5
    fi
}
```

**Modify the issues context injection (around line 2237):**

```bash
local issues_context=""
if [[ -n "${PENDING_ISSUES:-}" ]]; then
    # Find similar fixes from history
    local similar_fixes=""
    similar_fixes=$(find_similar_error_fixes "$PENDING_ISSUES")
    local similar_learnings=""
    similar_learnings=$(find_similar_fixes_in_learnings "$PENDING_ISSUES")

    issues_context="
ISSUES FROM PREVIOUS ITERATION (fix these first!):
- ${PENDING_ISSUES}
"

    if [[ -n "$similar_fixes" ]] || [[ -n "$similar_learnings" ]]; then
        issues_context+="
YOU'VE FIXED SIMILAR ERRORS BEFORE:
$similar_fixes
$similar_learnings

Apply these solutions if relevant."
    fi
fi
```

**Impact:** When Claude encounters an error it's seen before, it gets the previous solution injected automatically.

---

### 1.5 Git-Aware Context

**The Problem:**

The script doesn't leverage git history to understand what's been happening in the codebase.

**The Fix:**

Add git analysis functions and inject relevant context.

```bash
#=============================================================================
# GIT-AWARE CONTEXT
#=============================================================================

get_git_context() {
    local spec_name="$1"
    local max_commits="${2:-10}"

    # Check if we're in a git repo
    git rev-parse --git-dir &>/dev/null || return

    local output=""

    # Recent commits related to this feature
    local feature_commits=$(git log --oneline --grep="$spec_name" -$max_commits 2>/dev/null)
    if [[ -n "$feature_commits" ]]; then
        output+="### Recent commits for this feature:
\`\`\`
$feature_commits
\`\`\`

"
    fi

    # Files changed in recent commits
    local recent_files=$(git diff --name-only HEAD~5 2>/dev/null | grep -v "\.lock" | head -10)
    if [[ -n "$recent_files" ]]; then
        output+="### Files in flux (changed recently):
$recent_files

"
    fi

    # Uncommitted changes
    local uncommitted=$(git status --short 2>/dev/null | head -10)
    if [[ -n "$uncommitted" ]]; then
        output+="### Uncommitted changes:
\`\`\`
$uncommitted
\`\`\`

"
    fi

    echo "$output"
}

get_file_change_patterns() {
    # Analyze which files tend to change together
    git log --name-only --pretty=format: -20 2>/dev/null | \
        grep -v "^$" | \
        sort | uniq -c | sort -rn | \
        head -10 | \
        awk '{print "- " $2 " (changed " $1 " times)"}'
}
```

**Inject into iteration prompt:**

```bash
# Get git context
local git_context=""
git_context=$(get_git_context "$(basename "$spec_dir")")
if [[ -n "$git_context" ]]; then
    git_context="
## Git Context
$git_context"
fi

# Add to iteration prompt
local iteration_prompt="You are in iteration $iteration...
$prev_summary
$git_context
$issues_context$learnings_context$accumulated_context
..."
```

**Impact:** Claude understands what's been happening in git, which files are active, and what's uncommitted.

---

### 1.6 Structured Knowledge Base

**The Problem:**

Learnings are stored as flat lists. There's no structure for quick retrieval by category or relevance.

**The Fix:**

Create a structured knowledge base with categories and indexing.

```bash
#=============================================================================
# STRUCTURED KNOWLEDGE BASE
#=============================================================================

KNOWLEDGE_FILE=".cr/knowledge.json"

init_knowledge_base() {
    mkdir -p .cr
    if [[ ! -f "$KNOWLEDGE_FILE" ]]; then
        cat > "$KNOWLEDGE_FILE" << 'EOF'
{
  "version": 1,
  "error_solutions": {},
  "file_patterns": {},
  "task_approaches": {},
  "gotchas": [],
  "last_updated": ""
}
EOF
    fi
}

add_error_solution() {
    local error_key="$1"  # Normalized error identifier
    local solution="$2"
    local files="${3:-}"

    init_knowledge_base

    if command -v jq &>/dev/null; then
        # Create a normalized key from the error
        local key=$(echo "$error_key" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '_' | sed 's/_$//' | cut -c1-50)

        jq --arg key "$key" \
           --arg solution "$solution" \
           --arg files "$files" \
           --arg date "$(date -Iseconds)" \
           '.error_solutions[$key] = {
               "solution": $solution,
               "files": $files,
               "added": $date,
               "used_count": ((.error_solutions[$key].used_count // 0) + 1)
           } | .last_updated = $date' \
           "$KNOWLEDGE_FILE" > "$KNOWLEDGE_FILE.tmp" && mv "$KNOWLEDGE_FILE.tmp" "$KNOWLEDGE_FILE"
    fi
}

add_file_pattern() {
    local source_pattern="$1"  # e.g., "src/components/*.svelte"
    local test_pattern="$2"    # e.g., "tests/unit/*.test.ts"

    init_knowledge_base

    if command -v jq &>/dev/null; then
        jq --arg src "$source_pattern" \
           --arg test "$test_pattern" \
           '.file_patterns[$src] = $test' \
           "$KNOWLEDGE_FILE" > "$KNOWLEDGE_FILE.tmp" && mv "$KNOWLEDGE_FILE.tmp" "$KNOWLEDGE_FILE"
    fi
}

add_task_approach() {
    local task_type="$1"      # e.g., "ui_component", "api_endpoint"
    local approach="$2"       # e.g., "Create component + test + screenshot in same iteration"
    local success_rate="${3:-0}"

    init_knowledge_base

    if command -v jq &>/dev/null; then
        jq --arg type "$task_type" \
           --arg approach "$approach" \
           --argjson rate "$success_rate" \
           '.task_approaches[$type] = {
               "approach": $approach,
               "success_rate": $rate
           }' \
           "$KNOWLEDGE_FILE" > "$KNOWLEDGE_FILE.tmp" && mv "$KNOWLEDGE_FILE.tmp" "$KNOWLEDGE_FILE"
    fi
}

add_gotcha() {
    local gotcha="$1"
    local category="${2:-general}"

    init_knowledge_base

    if command -v jq &>/dev/null; then
        jq --arg gotcha "$gotcha" \
           --arg category "$category" \
           --arg date "$(date -Iseconds)" \
           '.gotchas += [{"text": $gotcha, "category": $category, "added": $date}]' \
           "$KNOWLEDGE_FILE" > "$KNOWLEDGE_FILE.tmp" && mv "$KNOWLEDGE_FILE.tmp" "$KNOWLEDGE_FILE"
    fi
}

get_relevant_knowledge() {
    local task_description="$1"
    local output=""

    [[ ! -f "$KNOWLEDGE_FILE" ]] && return

    if command -v jq &>/dev/null; then
        # Determine task type from description
        local task_type=""
        if echo "$task_description" | grep -qiE "component|ui|button|form|modal"; then
            task_type="ui_component"
        elif echo "$task_description" | grep -qiE "api|endpoint|route|handler"; then
            task_type="api_endpoint"
        elif echo "$task_description" | grep -qiE "test|spec"; then
            task_type="testing"
        fi

        # Get relevant task approach
        if [[ -n "$task_type" ]]; then
            local approach=$(jq -r ".task_approaches[\"$task_type\"].approach // empty" "$KNOWLEDGE_FILE" 2>/dev/null)
            if [[ -n "$approach" ]]; then
                output+="**Recommended approach for $task_type:** $approach

"
            fi
        fi

        # Get relevant gotchas
        local gotchas=$(jq -r '.gotchas[-5:] | .[] | "- " + .text' "$KNOWLEDGE_FILE" 2>/dev/null)
        if [[ -n "$gotchas" ]]; then
            output+="**Recent gotchas to watch for:**
$gotchas

"
        fi
    fi

    echo "$output"
}
```

**Update the output parser to populate the knowledge base:**

```bash
# In parse_iteration_output(), add:

# Extract file patterns from FILES and TESTS markers
local files_line=$(grep "^FILES:" "$log_file" 2>/dev/null | tail -1)
local tests_line=$(grep "^TESTS:" "$log_file" 2>/dev/null | tail -1)
if [[ -n "$files_line" ]] && [[ -n "$tests_line" ]]; then
    # Try to identify patterns
    local src_file=$(echo "$files_line" | grep -oE "src/[^ ,]+" | head -1)
    local test_file=$(echo "$tests_line" | grep -oE "(tests|test|__tests__)/[^ ,]+" | head -1)
    if [[ -n "$src_file" ]] && [[ -n "$test_file" ]]; then
        # Generalize to patterns
        local src_pattern=$(echo "$src_file" | sed 's/[^/]*$/\*/')
        local test_pattern=$(echo "$test_file" | sed 's/[^/]*$/\*.test.ts/')
        add_file_pattern "$src_pattern" "$test_pattern"
    fi
fi

# Track successful task approaches
if grep -q "^COMPLETED:" "$log_file" 2>/dev/null; then
    local task_desc=$(grep "^COMPLETED:" "$log_file" | head -1 | sed 's/COMPLETED: //')
    # Determine task type and record successful approach
    if echo "$task_desc" | grep -qiE "component"; then
        add_task_approach "ui_component" "Created component with co-located test" 1
    fi
fi
```

**Impact:** Structured knowledge accumulates across iterations and features, with fast retrieval by task type.

---

### 1.7 Refresh Context in PROMPT.md Before Each Iteration

**The Problem:**

PROMPT.md is only populated with context when the spec is created. Context learned during implementation doesn't appear there.

**The Fix:**

Refresh the accumulated context section before each iteration.

```bash
refresh_prompt_context() {
    local prompt_file="$1"

    [[ ! -f "$prompt_file" ]] && return

    # Get fresh accumulated context
    local fresh_context
    fresh_context=$(get_context_for_prompt 2>/dev/null || echo "No accumulated context yet.")

    # Get relevant knowledge
    local spec_file=$(dirname "$prompt_file")/SPEC.md
    local current_task=""
    if [[ -f "$spec_file" ]]; then
        current_task=$(grep -A1 "### In Progress" "$spec_file" 2>/dev/null | tail -1)
        [[ -z "$current_task" ]] && current_task=$(grep -A1 "### Pending" "$spec_file" 2>/dev/null | grep "^\- \[ \]" | head -1)
    fi

    local knowledge=""
    if [[ -n "$current_task" ]]; then
        knowledge=$(get_relevant_knowledge "$current_task")
    fi

    # Build replacement content
    local replacement_content="## Accumulated Context (from previous iterations)

$fresh_context

$knowledge"

    # Create a marker-based replacement (add markers to template)
    # If markers exist, replace between them
    if grep -q "<!-- CONTEXT_START -->" "$prompt_file" 2>/dev/null; then
        # Use awk for multi-line replacement
        awk -v new_content="$replacement_content" '
            /<!-- CONTEXT_START -->/ { print; print new_content; skip=1; next }
            /<!-- CONTEXT_END -->/ { skip=0 }
            !skip { print }
        ' "$prompt_file" > "$prompt_file.tmp" && mv "$prompt_file.tmp" "$prompt_file"
    fi
}
```

**Update PROMPT-template.md to include markers:**

```markdown
<!-- CONTEXT_START -->
{{ACCUMULATED_CONTEXT}}
<!-- CONTEXT_END -->
```

**Call before each iteration (in cmd_implement):**

```bash
# Before building iteration_prompt
refresh_prompt_context "$prompt_file"
```

**Impact:** PROMPT.md always has the latest accumulated context, not stale context from spec creation.

---

### 1.8 Cross-Feature Learning Inheritance

**The Problem:**

Each feature starts fresh. Learnings from previous features don't automatically apply.

**The Fix:**

When creating a new spec, seed it with relevant learnings from previous features.

```bash
seed_spec_with_cross_feature_learnings() {
    local spec_dir="$1"
    local spec_file="$spec_dir/SPEC.md"

    [[ ! -f "$spec_file" ]] && return

    # Get learnings from completed features
    local completed_specs=$(find "$SPECS_DIR" -name "SPEC.md" -exec grep -l "status: complete" {} \; 2>/dev/null)

    local cross_learnings=""
    for completed_spec in $completed_specs; do
        # Extract Notes section from completed specs
        local notes=$(sed -n '/^### Notes$/,/^##/p' "$completed_spec" 2>/dev/null | grep -v "^##" | head -10)
        if [[ -n "$notes" ]]; then
            local feature_name=$(basename "$(dirname "$completed_spec")")
            cross_learnings+="
#### From $feature_name:
$notes
"
        fi
    done

    # Also include top learnings from knowledge base
    local top_gotchas=""
    if [[ -f "$KNOWLEDGE_FILE" ]] && command -v jq &>/dev/null; then
        top_gotchas=$(jq -r '.gotchas[-10:] | .[] | "- " + .text' "$KNOWLEDGE_FILE" 2>/dev/null)
    fi

    if [[ -n "$cross_learnings" ]] || [[ -n "$top_gotchas" ]]; then
        # Append to Notes section
        cat >> "$spec_file" << EOF

### Cross-Feature Learnings (Auto-imported)

These learnings from previous features may be relevant:
$cross_learnings

#### Project-wide gotchas:
$top_gotchas
EOF
        log_info "Seeded spec with cross-feature learnings"
    fi
}
```

**Call at end of cmd_spec():**

```bash
# After creating SPEC.md and PROMPT.md
seed_spec_with_cross_feature_learnings "$spec_dir"
```

**Impact:** New features start with accumulated wisdom from completed features.

---

### 1.9 Iteration Health Scoring

**The Problem:**

No way to track whether iterations are getting healthier (fewer failures, more completions) or degrading.

**The Fix:**

Track iteration health metrics and surface trends.

```bash
#=============================================================================
# ITERATION HEALTH TRACKING
#=============================================================================

HEALTH_FILE=".cr/health.json"

init_health_tracking() {
    mkdir -p .cr
    if [[ ! -f "$HEALTH_FILE" ]]; then
        echo '{"iterations": [], "summary": {"total": 0, "successful": 0, "failed": 0}}' > "$HEALTH_FILE"
    fi
}

record_iteration_health() {
    local spec_name="$1"
    local iteration="$2"
    local success="$3"  # true/false
    local tasks_completed="${4:-0}"
    local errors_fixed="${5:-0}"
    local quality_gates_passed="${6:-0}"

    init_health_tracking

    if command -v jq &>/dev/null; then
        jq --arg spec "$spec_name" \
           --argjson iter "$iteration" \
           --argjson success "$success" \
           --argjson tasks "$tasks_completed" \
           --argjson errors "$errors_fixed" \
           --argjson gates "$quality_gates_passed" \
           --arg date "$(date -Iseconds)" \
           '.iterations += [{
               "spec": $spec,
               "iteration": $iter,
               "success": $success,
               "tasks_completed": $tasks,
               "errors_fixed": $errors,
               "quality_gates_passed": $gates,
               "timestamp": $date
           }] |
           .summary.total += 1 |
           .summary.successful += (if $success then 1 else 0 end) |
           .summary.failed += (if $success then 0 else 1 end)' \
           "$HEALTH_FILE" > "$HEALTH_FILE.tmp" && mv "$HEALTH_FILE.tmp" "$HEALTH_FILE"
    fi
}

get_health_trend() {
    [[ ! -f "$HEALTH_FILE" ]] && return

    if command -v jq &>/dev/null; then
        local total=$(jq -r '.summary.total' "$HEALTH_FILE")
        local successful=$(jq -r '.summary.successful' "$HEALTH_FILE")
        local rate=0
        [[ $total -gt 0 ]] && rate=$((successful * 100 / total))

        # Get recent trend (last 10 vs previous 10)
        local recent_success=$(jq -r '[.iterations[-10:] | .[] | select(.success == true)] | length' "$HEALTH_FILE")
        local earlier_success=$(jq -r '[.iterations[-20:-10] | .[] | select(.success == true)] | length' "$HEALTH_FILE" 2>/dev/null || echo "0")

        local trend="stable"
        if [[ $recent_success -gt $earlier_success ]]; then
            trend="improving ↑"
        elif [[ $recent_success -lt $earlier_success ]]; then
            trend="degrading ↓"
        fi

        echo "Success rate: ${rate}% ($successful/$total) | Trend: $trend"
    fi
}
```

**Inject health into iteration prompt:**

```bash
local health_summary=""
health_summary=$(get_health_trend 2>/dev/null)
if [[ -n "$health_summary" ]]; then
    health_summary="
**Iteration Health:** $health_summary
"
fi
```

**Impact:** Visibility into whether the loop is converging or struggling, which informs strategy.

---

### 1.10 Summary: CR-Only Improvements Implementation Order

| Priority | Improvement | Effort | Impact |
|----------|-------------|--------|--------|
| 1 | Fix `{{ACCUMULATED_CONTEXT}}` placeholder | Low | High |
| 2 | Add output markers + parsing | Medium | High |
| 3 | Inject previous iteration summary | Low | Medium |
| 4 | Smart error context injection | Medium | High |
| 5 | Refresh PROMPT.md context before iteration | Low | Medium |
| 6 | Structured knowledge base | Medium | High |
| 7 | Git-aware context | Low | Medium |
| 8 | Cross-feature learning inheritance | Medium | Medium |
| 9 | Iteration health scoring | Low | Low |

---

## Part 2: Improvements with Claude Code Task System

These improvements leverage the native Task System for reliable persistence, parallel execution, and structured metadata.

---

### 2.0 Critical: Task List Persistence via CLAUDE_CODE_TASK_LIST_ID

**This is the most important implementation detail for Task System integration.**

By default, each Claude Code session creates a fresh, ephemeral task list. Tasks created in one session won't be visible in another. To enable cross-session persistence, you must set the `CLAUDE_CODE_TASK_LIST_ID` environment variable.

**How it works:**

```bash
# Generate a unique, persistent task list ID for your project
export CLAUDE_CODE_TASK_LIST_ID="cr-$(basename $(pwd))-$(date +%Y%m%d)"

# Or use a fixed ID per project
export CLAUDE_CODE_TASK_LIST_ID="compound-ralph-learnings"

# Tasks are stored at:
# ~/.claude/tasks/<CLAUDE_CODE_TASK_LIST_ID>/*.json
```

**CR Integration:**

The `cr` script must set this environment variable when invoking Claude:

```bash
# In cr script, before any claude invocations:
export CLAUDE_CODE_TASK_LIST_ID="cr-$(basename "$(pwd)")"

# Or store it in .cr/config and load it:
if [[ -f ".cr/task_list_id" ]]; then
    export CLAUDE_CODE_TASK_LIST_ID=$(cat .cr/task_list_id)
else
    # Generate and persist on first use
    CLAUDE_CODE_TASK_LIST_ID="cr-$(basename "$(pwd)")-$(date +%Y%m%d)"
    echo "$CLAUDE_CODE_TASK_LIST_ID" > .cr/task_list_id
    export CLAUDE_CODE_TASK_LIST_ID
fi
```

**Modified Claude invocations:**

```bash
# Before (tasks are ephemeral):
claude --dangerously-skip-permissions --print "$prompt"

# After (tasks persist across sessions):
CLAUDE_CODE_TASK_LIST_ID="$TASK_LIST_ID" claude --dangerously-skip-permissions --print "$prompt"
```

**Why this matters:**

| Without CLAUDE_CODE_TASK_LIST_ID | With CLAUDE_CODE_TASK_LIST_ID |
|----------------------------------|-------------------------------|
| Each iteration gets fresh task list | All iterations share one task list |
| Learnings lost between sessions | Learnings persist forever |
| Can't query previous learnings | Can query all historical learnings |
| Tasks disappear when session ends | Tasks survive across sessions |

**Verification:**

```bash
# Check if task list exists
ls -la ~/.claude/tasks/

# Should show your project's task list:
# drwxr-xr-x  cr-my-project-20260123/

# List tasks in a specific list
ls ~/.claude/tasks/cr-my-project-20260123/
```

**Project-level vs Global:**

You can choose the scope of task persistence:

```bash
# Project-level (recommended): Each project has its own learnings
export CLAUDE_CODE_TASK_LIST_ID="cr-$(basename "$(pwd)")"

# Global: All projects share learnings (useful for cross-project patterns)
export CLAUDE_CODE_TASK_LIST_ID="cr-global-learnings"

# Feature-level: Each feature has its own learnings (too granular)
export CLAUDE_CODE_TASK_LIST_ID="cr-$(basename "$spec_dir")"  # Not recommended
```

**Recommendation:** Use project-level persistence. This keeps learnings relevant (same codebase) while allowing cross-feature compounding.

---

### 2.1 Architecture: Hybrid CR + Tasks

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CR Orchestrator (bash)                              │
│  - Loop control, backpressure gates, SPEC.md management                     │
│  - Calls Claude with --dangerously-skip-permissions                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Claude Code with Task System                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ Learning Tasks  │  │ Feature Tasks   │  │ Knowledge Tasks │             │
│  │                 │  │                 │  │                 │             │
│  │ - Error fixes   │  │ - Current work  │  │ - Patterns      │             │
│  │ - Patterns      │  │ - Dependencies  │  │ - Gotchas       │             │
│  │ - Discoveries   │  │ - Status        │  │ - Best practices│             │
│  │ - Gotchas       │  │ - Owner         │  │                 │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           ▼                    ▼                    ▼                       │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    Persistent Task Storage                        │      │
│  │              ~/.claude/tasks/<list-id>/*.json                     │      │
│  │                                                                   │      │
│  │  - Survives session summarization                                 │      │
│  │  - Queryable by metadata                                          │      │
│  │  - Dependency tracking (blockedBy)                                │      │
│  │  - Cross-feature persistence                                      │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 2.2 Learning Tasks: Structured Knowledge Persistence

Instead of `.cr/learnings.json` and `.cr/context.yaml`, use Tasks with metadata:

**Learning Task Schema:**

```javascript
TaskCreate({
  subject: "Brief description of the learning",
  description: "Detailed explanation with context",
  activeForm: "Recording learning",  // Required field
  metadata: {
    type: "learning",                 // Task type identifier
    category: "error_fix" | "pattern" | "gotcha" | "discovery" | "approach",
    spec: "feature-name",             // Which feature this came from
    iteration: 5,                     // Which iteration
    error_pattern: "Cannot find module",  // For error_fix category
    solution: "Check import paths",   // For error_fix category
    applies_to: ["api", "auth"],      // Categories where this is relevant
    files: ["src/utils/auth.ts"],     // Related files
    relevance_score: 0,               // Incremented when used
    created: "2026-01-23T10:00:00Z"
  }
})
```

**Categories and Their Uses:**

| Category | Purpose | Query Pattern |
|----------|---------|---------------|
| `error_fix` | Error→solution mappings | Match `error_pattern` against current errors |
| `pattern` | Codebase patterns discovered | Match `applies_to` against task type |
| `gotcha` | Things to watch out for | Always include recent gotchas |
| `discovery` | General learnings | Include recent discoveries |
| `approach` | Successful task approaches | Match against task type |

---

### 2.3 Three-Phase Iteration with Specialized Agents

Replace the monolithic iteration with three specialized phases:

```
┌─────────────────────────────────────────────────────────────────────┐
│                      ITERATION N                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Phase 1: CONTEXT GATHERING (Parallel)           ~30 seconds        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │
│  │   Query      │ │   Analyze    │ │   Read       │                │
│  │   Learning   │ │   Git        │ │   SPEC.md    │                │
│  │   Tasks      │ │   History    │ │   + Files    │                │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘                │
│         │                │                │                         │
│         └────────────────┼────────────────┘                         │
│                          ▼                                          │
│                 Combined Context JSON                               │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Phase 2: IMPLEMENTATION (Sequential)            ~5-15 minutes      │
│  ┌──────────────────────────────────────────────────────────┐      │
│  │                  Implementer Agent                        │      │
│  │                                                           │      │
│  │  - Receives combined context                              │      │
│  │  - Implements ONE task from SPEC.md                       │      │
│  │  - Runs quality gates                                     │      │
│  │  - Outputs structured learning markers                    │      │
│  └──────────────────────────────────────────────────────────┘      │
│                          │                                          │
│                          ▼                                          │
│                 Implementation Output                               │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Phase 3: LEARNING EXTRACTION (Parallel)         ~30 seconds        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │
│  │   Extract    │ │   Update     │ │   Update     │                │
│  │   Learnings  │ │   Knowledge  │ │   Health     │                │
│  │   → Tasks    │ │   Tasks      │ │   Metrics    │                │
│  └──────────────┘ └──────────────┘ └──────────────┘                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```bash
run_iteration_with_tasks() {
    local spec_dir="$1"
    local iteration="$2"
    local spec_name=$(basename "$spec_dir")

    log_step "Iteration $iteration - Phase 1: Context Gathering"

    # Phase 1: Gather context using parallel Task agents
    local context_json
    context_json=$(claude --dangerously-skip-permissions --print "
You are a context gatherer. Query the Task System and output JSON.

1. Call TaskList() to get all tasks
2. Filter for tasks where metadata.type === 'learning'
3. Further filter for relevant learnings:
   - metadata.category === 'error_fix' (always include recent ones)
   - metadata.category === 'gotcha' (always include)
   - metadata.applies_to includes relevant categories
4. Read $spec_dir/SPEC.md for current task
5. Check git status for uncommitted changes

Output ONLY this JSON (no other text):
{
  \"current_task\": \"<task from In Progress or first Pending>\",
  \"relevant_error_fixes\": [
    {\"error\": \"...\", \"solution\": \"...\"}
  ],
  \"recent_gotchas\": [\"...\"],
  \"patterns\": [\"...\"],
  \"recent_discoveries\": [\"...\"],
  \"uncommitted_files\": [\"...\"]
}
")

    # Validate we got JSON
    if ! echo "$context_json" | jq . &>/dev/null; then
        log_warn "Context gathering failed, proceeding with minimal context"
        context_json='{}'
    fi

    log_step "Iteration $iteration - Phase 2: Implementation"

    # Phase 2: Implementation with injected context
    local impl_output
    impl_output=$(claude --dangerously-skip-permissions --print "
You are an implementer in a Compound Ralph loop. Iteration $iteration.

## Context from Previous Iterations (from Task System)
$context_json

## Your Mission
1. Read $spec_dir/SPEC.md
2. Read $spec_dir/PROMPT.md for detailed instructions
3. Implement ONE task (the one in 'In Progress' or first 'Pending')
4. Run quality gates
5. Update SPEC.md

## Output Markers (REQUIRED)
When done, output these markers:

COMPLETED: <task description>
FILES: <files created/modified>
TESTS: <test files created>

If you learned something:
LEARNING: <what you learned>
PATTERN: <codebase pattern discovered>
FIXED: <error> → <solution>
GOTCHA: <thing to watch out for>

If blocked:
BLOCKER: <what> | NEEDS: <what's needed>

Begin by reading the files.
")

    # Log the output
    local log_file="$spec_dir/.history/$(printf '%03d' $iteration)-$(date '+%Y%m%d-%H%M%S').md"
    mkdir -p "$spec_dir/.history"
    echo "$impl_output" > "$log_file"
    echo "$impl_output"

    log_step "Iteration $iteration - Phase 3: Learning Extraction"

    # Phase 3: Extract learnings and create Tasks
    claude --dangerously-skip-permissions --print "
You are a learning extractor. Analyze the implementation output and create Learning Tasks.

## Implementation Output to Analyze:
$impl_output

## Your Job:
For each marker found, create a Learning Task:

### For LEARNING markers:
TaskCreate({
  subject: '<brief learning>',
  description: '<full context>',
  activeForm: 'Recording learning',
  metadata: {
    type: 'learning',
    category: 'discovery',
    spec: '$spec_name',
    iteration: $iteration,
    applies_to: ['<relevant categories>'],
    created: '$(date -Iseconds)'
  }
})

### For FIXED markers:
TaskCreate({
  subject: 'Fix: <error summary>',
  description: '<full error> → <full solution>',
  activeForm: 'Recording error fix',
  metadata: {
    type: 'learning',
    category: 'error_fix',
    spec: '$spec_name',
    iteration: $iteration,
    error_pattern: '<normalized error>',
    solution: '<solution>',
    created: '$(date -Iseconds)'
  }
})

### For PATTERN markers:
TaskCreate({
  subject: 'Pattern: <pattern name>',
  description: '<full pattern description>',
  activeForm: 'Recording pattern',
  metadata: {
    type: 'learning',
    category: 'pattern',
    spec: '$spec_name',
    iteration: $iteration,
    applies_to: ['<relevant categories>'],
    created: '$(date -Iseconds)'
  }
})

### For GOTCHA markers:
TaskCreate({
  subject: 'Gotcha: <brief gotcha>',
  description: '<full gotcha with context>',
  activeForm: 'Recording gotcha',
  metadata: {
    type: 'learning',
    category: 'gotcha',
    spec: '$spec_name',
    iteration: $iteration,
    created: '$(date -Iseconds)'
  }
})

Create the appropriate TaskCreate calls now.
"

    # Check for completion
    if echo "$impl_output" | grep -qE "<loop-complete>"; then
        return 0  # Signal completion
    fi

    return 1  # Continue looping
}
```

---

### 2.4 Smart Context Querying

Query learning tasks intelligently based on the current situation:

```javascript
// Context Gatherer Agent's query logic

async function gatherRelevantContext(currentTask, currentError) {
  const allTasks = await TaskList();
  const learningTasks = allTasks.filter(t => t.metadata?.type === 'learning');

  const context = {
    error_fixes: [],
    patterns: [],
    gotchas: [],
    discoveries: [],
    approaches: []
  };

  // 1. If there's a current error, find matching fixes
  if (currentError) {
    const errorTerms = extractKeyTerms(currentError);
    context.error_fixes = learningTasks
      .filter(t => t.metadata?.category === 'error_fix')
      .filter(t => matchesTerms(t.metadata?.error_pattern, errorTerms))
      .sort((a, b) => (b.metadata?.relevance_score || 0) - (a.metadata?.relevance_score || 0))
      .slice(0, 5)
      .map(t => ({
        error: t.metadata.error_pattern,
        solution: t.metadata.solution,
        taskId: t.id  // So we can update relevance_score later
      }));
  }

  // 2. Get patterns relevant to current task type
  const taskType = inferTaskType(currentTask); // 'ui_component', 'api_endpoint', etc.
  context.patterns = learningTasks
    .filter(t => t.metadata?.category === 'pattern')
    .filter(t => t.metadata?.applies_to?.includes(taskType))
    .slice(0, 5)
    .map(t => t.description);

  // 3. Always include recent gotchas
  context.gotchas = learningTasks
    .filter(t => t.metadata?.category === 'gotcha')
    .sort((a, b) => new Date(b.metadata?.created) - new Date(a.metadata?.created))
    .slice(0, 5)
    .map(t => t.subject);

  // 4. Get relevant approaches
  context.approaches = learningTasks
    .filter(t => t.metadata?.category === 'approach')
    .filter(t => t.metadata?.applies_to?.includes(taskType))
    .slice(0, 3)
    .map(t => t.description);

  // 5. Recent discoveries from same or related features
  context.discoveries = learningTasks
    .filter(t => t.metadata?.category === 'discovery')
    .sort((a, b) => new Date(b.metadata?.created) - new Date(a.metadata?.created))
    .slice(0, 5)
    .map(t => t.description);

  return context;
}
```

---

### 2.5 Relevance Scoring: Learning from Usage

When a learning is used and helps, increment its relevance score:

```javascript
// In the Learner Agent, after successful iteration

async function updateLearningRelevance(usedLearningTaskIds) {
  for (const taskId of usedLearningTaskIds) {
    const task = await TaskGet({ taskId });
    const currentScore = task.metadata?.relevance_score || 0;

    await TaskUpdate({
      taskId,
      metadata: {
        ...task.metadata,
        relevance_score: currentScore + 1,
        last_used: new Date().toISOString()
      }
    });
  }
}
```

**How to track which learnings were used:**

The context gatherer includes task IDs in the context JSON. If the iteration succeeds without the error recurring, those error_fix learnings helped.

---

### 2.6 Cross-Feature Learning with Task Dependencies

Use `blockedBy` to create learning relationships:

```javascript
// When a learning from Feature A helps in Feature B
TaskCreate({
  subject: "Applied auth pattern to payments",
  description: "Reused JWT validation pattern from auth feature",
  metadata: {
    type: "learning",
    category: "discovery",
    spec: "payments",
    derived_from: "auth"  // Cross-feature reference
  }
})

// Query cross-feature learnings
const crossFeatureLearnings = learningTasks
  .filter(t => t.metadata?.derived_from === previousFeature);
```

---

### 2.7 Parallel Backpressure Verification

Use Tasks to run quality gates in parallel:

```javascript
// Instead of sequential: test → lint → typecheck → build
// Run in parallel where possible

const gateResults = await Promise.all([
  Task({
    subagent_type: 'Bash',
    prompt: 'Run: bun test --run. Report pass/fail.',
    description: 'Run tests'
  }),
  Task({
    subagent_type: 'Bash',
    prompt: 'Run: bun run lint. Report pass/fail.',
    description: 'Run lint'
  }),
  Task({
    subagent_type: 'Bash',
    prompt: 'Run: bun run typecheck. Report pass/fail.',
    description: 'Run typecheck'
  })
]);

// Build depends on others passing, so run after
if (gateResults.every(r => r.passed)) {
  await Task({
    subagent_type: 'Bash',
    prompt: 'Run: bun run build. Report pass/fail.',
    description: 'Run build'
  });
}
```

---

### 2.8 Feature Tasks with Work Items

Use feature-level Tasks to track high-level progress, with learning Tasks as enrichment:

```javascript
// Feature task (created from SPEC.md)
TaskCreate({
  subject: "Implement user authentication",
  description: "Full auth flow with JWT tokens",
  metadata: {
    type: "feature",
    spec: "auth",
    status: "in_progress",
    iterations_count: 0,
    tasks_completed: 0,
    tasks_total: 8
  }
})

// Update feature task progress after each iteration
TaskUpdate({
  taskId: featureTaskId,
  metadata: {
    iterations_count: currentIteration,
    tasks_completed: completedCount,
    last_iteration: new Date().toISOString()
  }
})
```

**Query feature progress:**

```javascript
const features = tasks.filter(t => t.metadata?.type === 'feature');
features.forEach(f => {
  console.log(`${f.subject}: ${f.metadata.tasks_completed}/${f.metadata.tasks_total} (${f.metadata.iterations_count} iterations)`);
});
```

---

### 2.9 Learning Lifecycle Management

Manage the learning task lifecycle to prevent unbounded growth:

```javascript
// Periodic cleanup: archive old, unused learnings
async function pruneOldLearnings() {
  const allTasks = await TaskList();
  const learnings = allTasks.filter(t => t.metadata?.type === 'learning');

  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

  for (const learning of learnings) {
    const created = new Date(learning.metadata?.created);
    const lastUsed = learning.metadata?.last_used
      ? new Date(learning.metadata.last_used)
      : created;
    const relevanceScore = learning.metadata?.relevance_score || 0;

    // Archive if: old + never used + low relevance
    if (lastUsed < thirtyDaysAgo && relevanceScore < 2) {
      await TaskUpdate({
        taskId: learning.id,
        status: 'completed',  // Mark as archived
        metadata: {
          ...learning.metadata,
          archived: true,
          archived_reason: 'unused_for_30_days'
        }
      });
    }
  }
}

// Promote high-value learnings to "permanent"
async function promoteValuableLearnings() {
  const learnings = await TaskList()
    .filter(t => t.metadata?.type === 'learning' && !t.metadata?.permanent);

  for (const learning of learnings) {
    if (learning.metadata?.relevance_score >= 5) {
      await TaskUpdate({
        taskId: learning.id,
        metadata: {
          ...learning.metadata,
          permanent: true,
          promoted_at: new Date().toISOString()
        }
      });
    }
  }
}
```

---

### 2.10 Summary: Task System Integration Benefits

| Capability | CR Alone | CR + Tasks |
|------------|----------|------------|
| **Persistence reliability** | File-based, can fail | Native, guaranteed |
| **Learning storage** | JSON files | Task metadata, queryable |
| **Cross-session survival** | Manual, fragile | Automatic via `CLAUDE_CODE_TASK_LIST_ID` env var (see 2.0) |
| **Parallel operations** | Sequential bash | Native parallel agents |
| **Query flexibility** | grep/jq hacks | Filter/map on task arrays |
| **Relevance tracking** | Not possible | Metadata scoring |
| **Cross-feature linking** | Shared files | Task references |
| **Lifecycle management** | Manual cleanup | Status-based archiving |

---

## Part 3: General Thoughts

### The Core Insight

After studying both systems deeply, there's a fundamental tension:

**CR is built around files as the source of truth.**
- SPEC.md is the state
- PROMPT.md is the instructions
- `.cr/` files are the memory
- Git commits are the changelog

**The Task System is built around persistent objects as the source of truth.**
- Tasks have identity (IDs)
- Tasks have relationships (blockedBy)
- Tasks have metadata (arbitrary JSON)
- Tasks survive context loss

These aren't incompatible—they're complementary. CR excels at orchestration (the loop, backpressure, quality gates). The Task System excels at memory (learnings, relationships, queries).

---

### What CR Gets Right

1. **Fresh context per iteration** — The Ralph Loop philosophy of not relying on conversation memory is sound. Context should be explicit, not implicit.

2. **File-based state** — SPEC.md as a human-readable, version-controlled source of truth is excellent. You can `git diff` your progress.

3. **Backpressure philosophy** — Running quality gates every iteration and self-correcting is powerful. It's what makes autonomous loops converge.

4. **Structured prompting** — The PROMPT-template.md phases (Orient, Select, Investigate, Implement, Validate) provide good structure.

5. **One task per iteration** — Focus beats breadth. This prevents context overload.

---

### What CR Gets Wrong

1. **Aspirational persistence** — The template describes a context system that doesn't actually work. `{{ACCUMULATED_CONTEXT}}` is never replaced. The add_learning calls only fire on failures.

2. **Reliance on Claude executing jq** — The template tells Claude to run jq commands to add learnings. This is unreliable. The script should parse output, not delegate persistence to the LLM.

3. **No structured output contract** — Without defined markers, there's no reliable way to extract what happened in an iteration.

4. **Cross-feature is theoretical** — The `.cr/` files could support cross-feature learning, but they're barely populated.

5. **No feedback on learning usage** — There's no way to know if a learning was helpful, so no way to prioritize.

---

### The Hybrid Path Forward

A staged approach is recommended:

**Stage 1: Fix CR's Existing Mechanisms (Part 1)**
- Actually replace `{{ACCUMULATED_CONTEXT}}`
- Add output markers and parsing
- Inject previous iteration summaries
- Get the existing system working as designed

This gives immediate improvement with minimal architectural change.

**Stage 2: Add Structured Knowledge (Part 1 continued)**
- Implement the knowledge base
- Add error→fix matching
- Enable cross-feature learning seeding

This builds the foundation for smarter iterations.

**Stage 3: Task System Integration (Part 2)**

*Prerequisite: Set up `CLAUDE_CODE_TASK_LIST_ID` in CR (see section 2.0)*

- Store learnings as Tasks instead of files
- Use three-phase iteration with specialized agents
- Enable relevance scoring
- Query learnings intelligently

This provides reliable, queryable, cross-session memory.

**Stage 4: Full Hybrid**
- CR orchestrates the loop
- Tasks store all learnings
- Parallel agents gather context
- Feature tasks track high-level progress

---

### On the Task System vs CR for Context

The Task System has a key advantage: **guaranteed persistence with native tooling**. When Claude calls `TaskCreate()`, it happens. When Claude is supposed to run `jq` commands, it might not.

But CR has a key advantage: **human readability and version control**. You can `cat SPEC.md` and see exactly where things stand. You can `git log` and see the history.

The ideal hybrid:
- **Use Tasks for machine memory** (learnings, error fixes, patterns)
- **Use SPEC.md for human-visible state** (tasks, progress, notes)
- **Use CR for orchestration** (loop, backpressure, iteration control)

---

### A Note on Complexity

There's a risk of over-engineering this. The Ralph Loop philosophy is about simplicity:
- Fresh context each iteration
- File-based state
- Backpressure for self-correction

Adding three-phase iterations, learning extraction agents, relevance scoring, and task lifecycle management adds complexity.

**Recommendation:** Start with the CR-only fixes (Part 1). They're high-impact, low-complexity. See if that's enough. If learnings are still being lost across iterations and features, then add Task System integration incrementally.

The goal isn't the most sophisticated system—it's the system that makes each iteration meaningfully smarter than the last with the least overhead.

---

### Final Thought

The fundamental question is: **What does Claude need to know at the start of iteration N+1 that it didn't know at the start of iteration N?**

1. What task was just completed
2. What files were created/modified
3. What errors were encountered and how they were fixed
4. What patterns were discovered
5. What gotchas were identified
6. What the overall health trend is

If those six things can be reliably captured and injected, each iteration will be smarter. The mechanism (files vs Tasks) matters less than the reliability of capture and injection.

CR's current mechanism is unreliable. Fix that first, then decide if the Task System's power is needed.
