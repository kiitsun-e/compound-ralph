# feat: Production-Grade Autonomous Development Loop

> Transform ralph-borg into a production-grade autonomous development system with near-full autonomy after spec creation, self-healing capabilities, and comprehensive quality gates.

---

## Overview

Ralph-borg currently provides a solid foundation for autonomous feature implementation with its 10-phase iteration pattern, backpressure system, and integration with compound-engineering workflows. However, to achieve **production-grade, enterprise-level autonomous development**, several architectural improvements are needed.

This plan transforms ralph-borg from a "human-guided with autonomous execution" system into a **"fire-and-forget after spec creation"** system that:

1. Preserves and compounds context across fresh Claude instances
2. Self-heals by detecting, diagnosing, and fixing bugs during iteration
3. Enforces comprehensive quality gates (tests, lint, types, security) by default
4. Searches and reuses existing code before generating new code
5. Works with any tech stack through intelligent project detection
6. Provides observability into autonomous operation

---

## Problem Statement

### Current Limitations

| Gap | Impact | Evidence |
|-----|--------|----------|
| **Monolithic Architecture** | Hard to test, extend, or maintain | Single 2,934-line bash script (`borg`) |
| **No Structured Error Recovery** | Agent relies on judgment for error handling | Retry logic is generic exponential backoff |
| **Limited Context Preservation** | Fresh instances lose learned patterns | `.borg/learnings.json` exists but isn't structured |
| **No Code Reuse Detection** | Agent may rewrite existing functionality | No "search before write" enforcement |
| **Missing Observability** | Can't measure iteration efficiency or identify bottlenecks | No metrics, logs are unstructured |
| **No Schema Validation** | SPEC.md can be malformed | Markdown parsing is fragile |
| **Single-Agent Architecture** | Can't parallelize research/implementation | Sequential execution only |

### User Requirements

From user interview:
- **Primary Use:** Both greenfield and existing codebase work
- **Oversight Level:** Fire-and-forget after initial planning (human reviews only final output)
- **Tech Stack:** Stack-agnostic, auto-detects conventions
- **Quality Focus:** All quality checks (tests + lint + types + security)

---

## Proposed Solution

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RALPH-BORG v2.0                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   PLANNING   │───▶│ AUTONOMOUS   │───▶│   SHIPPING   │              │
│  │    PHASE     │    │    LOOP      │    │    PHASE     │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│         │                   │                   │                        │
│         ▼                   ▼                   ▼                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │ /workflows:  │    │  10-Phase    │    │ /workflows:  │              │
│  │    plan      │    │  Iteration   │    │   review     │              │
│  │ /deepen-plan │    │   Engine     │    │   PR/Ship    │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│                             │                                            │
│                             ▼                                            │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    CORE SUBSYSTEMS                                 │ │
│  ├───────────────────────────────────────────────────────────────────┤ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐│ │
│  │  │   Context   │  │   Self-     │  │   Quality   │  │  Code     ││ │
│  │  │   Engine    │  │   Healing   │  │   Gates     │  │  Reuse    ││ │
│  │  │             │  │   Engine    │  │   Engine    │  │  Engine   ││ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘│ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐│ │
│  │  │   Project   │  │   SPEC      │  │   Metrics   │  │  Multi-   ││ │
│  │  │   Discovery │  │   Schema    │  │   &         │  │  Agent    ││ │
│  │  │             │  │   Engine    │  │   Observ.   │  │  Coord.   ││ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘│ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Modular Architecture** - Break monolithic script into composable modules
2. **Structured State** - SPEC as YAML with JSON Schema validation
3. **Self-Healing Pipeline** - Error → Diagnose → Fix → Retry cycle
4. **Code-First Search** - Mandatory codebase search before generation
5. **Observable by Default** - Structured logs, metrics, traces
6. **Multi-Agent Ready** - Architecture supports parallel agent coordination

---

## Technical Approach

### Phase 1: Foundation - Modular Architecture

**Objective:** Transform monolithic `borg` script into testable, extensible modules.

#### Tasks

- [ ] Task 1: Create module directory structure
  - File: `lib/core/cli.sh` - Command parsing and routing
  - File: `lib/core/config.sh` - Configuration management
  - File: `lib/core/logger.sh` - Structured logging
  - Test: `tests/unit/cli.bats` (using Bats testing framework)

- [ ] Task 2: Extract project discovery module
  - File: `lib/discovery/project.sh` - Project type detection
  - File: `lib/discovery/commands.sh` - Build/test/lint command discovery
  - File: `lib/discovery/files.sh` - Key file identification
  - Test: `tests/unit/discovery.bats`

- [ ] Task 3: Extract iteration engine
  - File: `lib/engine/iteration.sh` - Core 10-phase loop
  - File: `lib/engine/retry.sh` - Retry logic with circuit breaker
  - File: `lib/engine/signals.sh` - Graceful shutdown handling
  - Test: `tests/unit/engine.bats`

- [ ] Task 4: Extract quality gates module
  - File: `lib/gates/runner.sh` - Gate execution
  - File: `lib/gates/lint.sh` - Linting integration
  - File: `lib/gates/test.sh` - Test execution
  - File: `lib/gates/security.sh` - Security scanning
  - Test: `tests/unit/gates.bats`

- [ ] Task 5: Create main entry point that sources modules
  - File: `borg` - Slim entry point (~100 lines)
  - Validate: All existing commands still work

**Success Criteria:**
- [ ] `borg` script under 200 lines
- [ ] All modules have corresponding tests
- [ ] `bats tests/` passes
- [ ] Existing CLI interface unchanged

---

### Phase 2: Context Engine - Preserved Learning

**Objective:** Ensure context and learnings persist and compound across fresh Claude instances.

#### Tasks

- [ ] Task 1: Design structured context schema
  - File: `lib/context/schema.sh` - Context validation
  - File: `schemas/context.json` - JSON Schema for context
  ```yaml
  # .borg/context.yaml
  project:
    type: bun | npm | rails | python | go | rust
    root: /path/to/project
    discovered_at: 2026-01-21T10:00:00Z

  patterns:
    - name: "API Route Pattern"
      location: "src/routes/*.ts"
      description: "All routes use express-style middleware"
      discovered_iteration: 3

  decisions:
    - date: 2026-01-21
      decision: "Use Zod for validation"
      rationale: "Already used in 3 other places"

  learnings:
    - category: gotcha
      content: "Must run db:migrate before tests"
      discovered_iteration: 2

  errors_encountered:
    - error_signature: "ECONNREFUSED localhost:5432"
      root_cause: "Database not running"
      fix: "docker-compose up -d postgres"
      occurrences: 2
  ```

- [ ] Task 2: Implement context reading/writing
  - File: `lib/context/reader.sh` - Load context for iteration
  - File: `lib/context/writer.sh` - Update context after iteration
  - File: `lib/context/merger.sh` - Merge new learnings with existing
  - Test: `tests/unit/context.bats`

- [ ] Task 3: Inject context into PROMPT.md generation
  - Edit: `templates/PROMPT-template.md` - Add context injection section
  ```markdown
  ## Accumulated Context

  ### Patterns Discovered
  {{patterns}}

  ### Previous Decisions
  {{decisions}}

  ### Known Gotchas
  {{learnings | filter: gotcha}}

  ### Error Fixes (Don't Repeat These)
  {{errors_encountered}}
  ```

- [ ] Task 4: Add context compounding from /workflows:compound
  - File: `lib/context/compound.sh` - Integrate with docs/solutions/
  - Validate: Context includes relevant solutions from past work

**Success Criteria:**
- [ ] Context survives across `borg implement` runs
- [ ] Learnings from iteration N visible in iteration N+1
- [ ] Error patterns stored and used to prevent repeats
- [ ] Context schema validates with JSON Schema

---

### Phase 3: Self-Healing Engine

**Objective:** Automatically detect, diagnose, and fix errors during autonomous operation.

#### Tasks

- [ ] Task 1: Implement error classification
  - File: `lib/healing/classifier.sh` - Classify errors by type
  ```bash
  # Error categories:
  # - SYNTAX: Parse/compile errors (fixable by editing code)
  # - RUNTIME: Execution errors (may need debugging)
  # - DEPENDENCY: Missing packages (fixable by install)
  # - ENVIRONMENT: Config/env issues (may need human)
  # - TEST_FAILURE: Tests fail (fixable by editing code/tests)
  # - LINT_VIOLATION: Style issues (fixable by formatting)
  # - TYPE_ERROR: Type mismatches (fixable by editing types)
  ```

- [ ] Task 2: Create diagnosis pipeline
  - File: `lib/healing/diagnoser.sh` - Analyze error context
  - File: `lib/healing/strategies.sh` - Healing strategy selection
  ```bash
  # Strategy selection based on error type:
  # SYNTAX → Extract error location, read file, prompt fix
  # TEST_FAILURE → Run test in verbose mode, identify assertion
  # DEPENDENCY → Parse error, suggest install command
  # TYPE_ERROR → Extract type mismatch, suggest correction
  ```

- [ ] Task 3: Implement fix-and-retry loop
  - File: `lib/healing/executor.sh` - Execute healing strategies
  - File: `lib/healing/circuit_breaker.sh` - Prevent infinite fix loops
  ```bash
  # Circuit breaker conditions:
  CB_SAME_ERROR_THRESHOLD=3      # Same error 3 times → stop
  CB_TOTAL_FIX_ATTEMPTS=10       # 10 fixes total → stop
  CB_FIX_TIME_LIMIT=300          # 5 min fixing same issue → stop
  ```

- [ ] Task 4: Add self-healing to iteration loop
  - Edit: `lib/engine/iteration.sh` - Integrate healing after validation
  ```bash
  # Phase 5: VALIDATE
  if ! run_quality_gates; then
    if can_self_heal "$last_error"; then
      attempt_self_heal "$last_error"
      # Re-run validation after healing
    else
      record_blocked_task "$current_task" "$last_error"
    fi
  fi
  ```

- [ ] Task 5: Store healing outcomes for learning
  - Edit: `lib/context/writer.sh` - Record successful fixes
  - Validate: Future iterations can reuse fix patterns

**Success Criteria:**
- [ ] Lint errors auto-fixed without human intervention
- [ ] Simple test failures debugged and fixed
- [ ] Dependency errors resolved by install
- [ ] Circuit breaker prevents infinite loops
- [ ] Fix patterns stored in context for reuse

---

### Phase 4: Code Reuse Engine

**Objective:** Always search existing code before generating new code.

#### Tasks

- [ ] Task 1: Implement codebase indexing
  - File: `lib/reuse/indexer.sh` - Index project files
  - File: `lib/reuse/cache.sh` - Cache index for performance
  ```bash
  # Index structure:
  # .borg/index/
  #   functions.json    # Function names → file:line
  #   classes.json      # Class names → file:line
  #   patterns.json     # Common patterns → examples
  #   imports.json      # What imports what
  ```

- [ ] Task 2: Create search-before-write enforcement
  - File: `lib/reuse/searcher.sh` - Search for existing implementations
  - Edit: `templates/PROMPT-template.md` - Add mandatory search phase
  ```markdown
  ## Phase 3: INVESTIGATE (MANDATORY)

  Before writing ANY new code:

  1. Search for existing implementations:
     - `grep -r "function_name" src/`
     - Check: src/utils/, src/lib/, src/shared/

  2. If found:
     - Import and use existing code
     - Extend if needed, don't duplicate
     - Document why extension was necessary

  3. If not found:
     - Proceed with implementation
     - Add to shared location if reusable

  **HARD RULE:** Do NOT generate code that duplicates existing functionality.
  ```

- [ ] Task 3: Add similarity detection
  - File: `lib/reuse/similarity.sh` - Detect similar code patterns
  - Validate: Warn if new code >70% similar to existing

- [ ] Task 4: Track code reuse metrics
  - File: `lib/metrics/reuse.sh` - Track reuse vs generation
  - Output: `.borg/metrics/reuse.json`
  ```json
  {
    "iteration": 5,
    "functions_reused": 3,
    "functions_generated": 1,
    "reuse_ratio": 0.75
  }
  ```

**Success Criteria:**
- [ ] Every implementation task searches codebase first
- [ ] Reuse ratio tracked per iteration
- [ ] Duplicate code generation flagged
- [ ] Index updates automatically after changes

---

### Phase 5: Quality Gates Engine

**Objective:** Comprehensive, stack-agnostic quality enforcement.

#### Tasks

- [ ] Task 1: Extend project discovery for all quality tools
  - Edit: `lib/discovery/commands.sh` - Detect all quality tools
  ```bash
  # Auto-detect quality gates by stack:
  # JavaScript/TypeScript:
  #   - Test: jest, vitest, mocha, ava, bun test
  #   - Lint: eslint, biome, prettier
  #   - Types: tsc --noEmit, tsc -b
  #   - Security: npm audit, snyk
  # Ruby:
  #   - Test: rspec, minitest
  #   - Lint: rubocop, standardrb
  #   - Security: brakeman, bundler-audit
  # Python:
  #   - Test: pytest, unittest
  #   - Lint: ruff, flake8, black
  #   - Types: mypy, pyright
  #   - Security: bandit, safety
  # Go:
  #   - Test: go test
  #   - Lint: golangci-lint
  #   - Security: gosec
  # Rust:
  #   - Test: cargo test
  #   - Lint: cargo clippy
  #   - Security: cargo audit
  ```

- [ ] Task 2: Implement tiered gate execution
  - File: `lib/gates/tiered.sh` - Execute gates in tiers
  ```bash
  # Tier 1: BLOCKING (must pass to continue)
  #   - Tests pass
  #   - Types check
  #   - Lint clean (errors only)

  # Tier 2: IMPORTANT (should pass, warn if not)
  #   - Coverage threshold
  #   - Lint warnings
  #   - Bundle size

  # Tier 3: ADVISORY (nice to have)
  #   - Documentation coverage
  #   - Code complexity
  ```

- [ ] Task 3: Add security scanning
  - File: `lib/gates/security.sh` - Security-specific checks
  - Validate: No high/critical vulnerabilities in new code

- [ ] Task 4: Implement per-task validation
  - Edit: `lib/engine/iteration.sh` - Run gates after each task
  ```bash
  # After each task:
  run_tier1_gates_on_changed_files

  # Before marking complete:
  run_all_gates
  ```

- [ ] Task 5: Add gate result caching
  - File: `lib/gates/cache.sh` - Cache passing results
  - Validate: Only re-run gates for changed files

**Success Criteria:**
- [ ] All major stacks auto-detected
- [ ] Tier 1 gates block progress
- [ ] Security scans run on new code
- [ ] Gate results cached for performance

---

### Phase 6: SPEC Schema Engine

**Objective:** Validate SPEC.md structure to prevent malformed specs.

#### Tasks

- [ ] Task 1: Define SPEC schema
  - File: `schemas/spec.yaml` - YAML-based SPEC format
  ```yaml
  # schemas/spec.yaml
  type: object
  required:
    - metadata
    - requirements
    - tasks
    - quality_gates
    - exit_criteria
  properties:
    metadata:
      type: object
      required: [name, status, created, project_type]
      properties:
        name:
          type: string
          pattern: "^[a-z0-9-]+$"
        status:
          enum: [pending, building, complete, blocked]
        iteration_count:
          type: integer
          minimum: 0
    requirements:
      type: array
      items:
        type: object
        required: [id, description, completed]
    tasks:
      type: object
      required: [pending, in_progress, completed, blocked]
    quality_gates:
      type: object
      required: [per_task, full, visual]
    exit_criteria:
      type: array
      minItems: 1
  ```

- [ ] Task 2: Implement SPEC validation
  - File: `lib/spec/validator.sh` - Validate SPEC against schema
  - File: `lib/spec/parser.sh` - Parse SPEC.md to structured format
  - Test: `tests/unit/spec.bats`

- [ ] Task 3: Add SPEC repair capability
  - File: `lib/spec/repair.sh` - Auto-fix common SPEC issues
  - Validate: Malformed SPECs repaired before iteration

- [ ] Task 4: Migrate templates to new schema
  - Edit: `templates/SPEC-template.md` - Use new validated structure
  - Edit: `borg` spec command - Generate validated SPECs

**Success Criteria:**
- [ ] All SPECs validate against schema
- [ ] Invalid SPECs rejected with clear errors
- [ ] Auto-repair for common issues
- [ ] Template generates valid SPECs

---

### Phase 7: Metrics & Observability

**Objective:** Provide visibility into autonomous operation.

#### Tasks

- [ ] Task 1: Implement structured logging
  - File: `lib/core/logger.sh` - JSON-structured logs
  ```bash
  # Log format:
  {
    "timestamp": "2026-01-21T10:30:00Z",
    "level": "info",
    "iteration": 5,
    "phase": "implement",
    "task": "Create user model",
    "event": "task_started",
    "context": {...}
  }
  ```

- [ ] Task 2: Add iteration metrics
  - File: `lib/metrics/iteration.sh` - Track iteration stats
  ```json
  {
    "iteration": 5,
    "duration_seconds": 120,
    "tasks_completed": 1,
    "tasks_attempted": 1,
    "errors_encountered": 0,
    "self_heals": 0,
    "code_reuse_ratio": 0.75,
    "gates_passed": ["test", "lint", "types"],
    "gates_failed": []
  }
  ```

- [ ] Task 3: Create dashboard output
  - File: `lib/metrics/dashboard.sh` - Summary view
  - Command: `borg dashboard [spec]` - Show metrics
  ```
  ┌─────────────────────────────────────────────┐
  │ SPEC: user-authentication                   │
  │ Status: building (iteration 5/∞)            │
  ├─────────────────────────────────────────────┤
  │ Progress: ████████░░ 80% (8/10 tasks)       │
  │ Time: 45m elapsed                           │
  │ Health: ✅ All gates passing                │
  ├─────────────────────────────────────────────┤
  │ Efficiency:                                 │
  │   Avg iteration: 5.2 min                    │
  │   Self-heals: 2 (both successful)           │
  │   Code reuse: 68%                           │
  └─────────────────────────────────────────────┘
  ```

- [ ] Task 4: Add trace file for debugging
  - File: `lib/metrics/tracer.sh` - Detailed execution trace
  - Output: `.borg/traces/iteration-N.json`

**Success Criteria:**
- [ ] All iterations produce structured logs
- [ ] Metrics available via `borg dashboard`
- [ ] Traces enable debugging stuck iterations
- [ ] Metrics persisted for historical analysis

---

### Phase 8: Multi-Agent Coordination (Future-Ready)

**Objective:** Architecture supports parallel agent execution.

#### Tasks

- [ ] Task 1: Design agent coordination protocol
  - File: `lib/agents/protocol.sh` - Agent communication spec
  ```bash
  # Agent roles:
  # - RESEARCHER: Searches codebase, reads docs
  # - IMPLEMENTER: Writes code, creates tests
  # - REVIEWER: Reviews changes, suggests fixes
  # - FIXER: Handles self-healing

  # Coordination:
  # - Agents write to shared state file
  # - Lock mechanism prevents conflicts
  # - Results aggregated after parallel work
  ```

- [ ] Task 2: Implement agent spawning
  - File: `lib/agents/spawner.sh` - Launch parallel agents
  - Validate: Can run multiple agents in parallel

- [ ] Task 3: Add result aggregation
  - File: `lib/agents/aggregator.sh` - Combine agent outputs
  - Validate: Multiple agent results merged coherently

- [ ] Task 4: Document multi-agent patterns
  - File: `docs/multi-agent.md` - How to use parallel agents
  - Example: Research + Implementation in parallel

**Success Criteria:**
- [ ] Architecture supports multiple agents
- [ ] No conflicts with parallel execution
- [ ] Clear documentation for multi-agent use
- [ ] Single-agent mode remains default

---

## Alternative Approaches Considered

### 1. Rewrite in TypeScript/Python

**Considered:** Rewriting `borg` in a typed language for better maintainability.

**Rejected because:**
- Bash is universal (no runtime dependencies)
- Current users don't need Node/Python installed
- Modular bash with tests achieves similar maintainability
- Migration cost outweighs benefits for v2.0

**Future consideration:** May revisit for v3.0 if complexity grows.

### 2. Full RAG-Based Code Search

**Considered:** Vector embeddings for semantic code search.

**Rejected because:**
- Requires embedding infrastructure
- Adds significant complexity
- Grep + structural search covers 90% of use cases
- Can add later as optional enhancement

### 3. Kubernetes-Based Agent Orchestration

**Considered:** Running agents as K8s pods for true parallelism.

**Rejected because:**
- Overkill for single-developer use case
- Adds infrastructure requirements
- Current approach (multiple Claude instances) works
- Can add later for enterprise use

---

## Acceptance Criteria

### Functional Requirements

- [ ] **F1:** Fresh Claude instance can continue work from previous instance
- [ ] **F2:** Errors are automatically diagnosed and fixed when possible
- [ ] **F3:** Codebase is searched before any new code generation
- [ ] **F4:** All quality gates run after each task completion
- [ ] **F5:** SPEC.md validates against defined schema
- [ ] **F6:** Metrics are available for every iteration
- [ ] **F7:** Works with all supported stacks (JS, Ruby, Python, Go, Rust)

### Non-Functional Requirements

- [ ] **NF1:** Iteration completes in <10 minutes for typical tasks
- [ ] **NF2:** Self-healing resolves >80% of lint/type errors
- [ ] **NF3:** Code reuse ratio >50% for mature codebases
- [ ] **NF4:** False positive rate for "reuse detection" <10%
- [ ] **NF5:** Memory usage <500MB during iteration

### Quality Gates

- [ ] All modules have unit tests
- [ ] Test coverage >80% for core modules
- [ ] `shellcheck` passes on all bash files
- [ ] Documentation complete for all commands
- [ ] README updated with new capabilities

---

## Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Autonomous completion rate | >90% | SPECs completed without human intervention |
| Self-healing success rate | >80% | Errors fixed / errors encountered |
| Code reuse ratio | >50% | Functions reused / functions written |
| Iteration efficiency | <10 min avg | Time per iteration |
| Context preservation | 100% | Learnings available in next iteration |
| Quality gate coverage | 100% | All tasks have gates run |

---

## Dependencies & Prerequisites

### Required Tools

- **Bash 4.0+** - For associative arrays and modern features
- **jq** - JSON processing
- **yq** - YAML processing
- **Bats** - Bash testing framework
- **ShellCheck** - Bash linting

### External Integrations

- Claude Code CLI (`claude`)
- compound-engineering plugin (for /workflows:*)
- ralph-wiggum plugin (for loop mechanics)

### File Structure After Implementation

```
ralph-borg/
├── borg                          # Entry point (~100 lines)
├── lib/
│   ├── core/
│   │   ├── cli.sh
│   │   ├── config.sh
│   │   └── logger.sh
│   ├── discovery/
│   │   ├── project.sh
│   │   ├── commands.sh
│   │   └── files.sh
│   ├── engine/
│   │   ├── iteration.sh
│   │   ├── retry.sh
│   │   └── signals.sh
│   ├── context/
│   │   ├── schema.sh
│   │   ├── reader.sh
│   │   ├── writer.sh
│   │   └── merger.sh
│   ├── healing/
│   │   ├── classifier.sh
│   │   ├── diagnoser.sh
│   │   ├── strategies.sh
│   │   ├── executor.sh
│   │   └── circuit_breaker.sh
│   ├── reuse/
│   │   ├── indexer.sh
│   │   ├── searcher.sh
│   │   ├── similarity.sh
│   │   └── cache.sh
│   ├── gates/
│   │   ├── runner.sh
│   │   ├── tiered.sh
│   │   ├── lint.sh
│   │   ├── test.sh
│   │   ├── security.sh
│   │   └── cache.sh
│   ├── spec/
│   │   ├── validator.sh
│   │   ├── parser.sh
│   │   └── repair.sh
│   ├── metrics/
│   │   ├── iteration.sh
│   │   ├── reuse.sh
│   │   ├── dashboard.sh
│   │   └── tracer.sh
│   └── agents/
│       ├── protocol.sh
│       ├── spawner.sh
│       └── aggregator.sh
├── schemas/
│   ├── spec.yaml
│   ├── context.json
│   └── metrics.json
├── templates/
│   ├── SPEC-template.md
│   └── PROMPT-template.md
├── tests/
│   ├── unit/
│   │   ├── cli.bats
│   │   ├── discovery.bats
│   │   ├── engine.bats
│   │   ├── context.bats
│   │   ├── healing.bats
│   │   ├── reuse.bats
│   │   ├── gates.bats
│   │   └── spec.bats
│   └── integration/
│       ├── full-loop.bats
│       └── self-healing.bats
├── docs/
│   ├── architecture.md
│   ├── self-healing.md
│   ├── quality-gates.md
│   ├── context-preservation.md
│   ├── code-reuse.md
│   └── multi-agent.md
├── plans/
└── specs/
```

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Modularization breaks existing commands | Medium | High | Comprehensive test suite before refactor |
| Self-healing creates more bugs | Medium | Medium | Circuit breaker + human review for complex fixes |
| Context file corruption | Low | High | Backup before write, atomic updates |
| False positive code reuse detection | Medium | Low | Similarity threshold tuning, manual override |
| Performance degradation from checks | Medium | Medium | Caching, parallel execution where safe |
| Schema migration breaks existing SPECs | Low | High | Migration script + backwards compatibility |

---

## Future Considerations

### v2.1: Enhanced Self-Healing
- LLM-as-judge for code quality
- Automatic rollback for failed fixes
- Learning from successful fixes across projects

### v2.2: Enterprise Features
- Team-shared context and learnings
- Audit logging for compliance
- Role-based access control

### v3.0: Multi-Agent Architecture
- True parallel agent execution
- Specialized agent personas
- Distributed coordination

---

## References & Research

### Internal References

- Current borg script: `borg:1-2934`
- SPEC template: `templates/SPEC-template.md:1-160`
- PROMPT template: `templates/PROMPT-template.md:1-585`
- Backpressure docs: `docs/backpressure.md:1-240`
- Prompting patterns: `docs/prompting-patterns.md:1-267`

### External References

- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Aider Lint & Test Patterns](https://aider.chat/docs/usage/lint-test)
- [Ralph Wiggum Technique](https://ghuntley.com/ralph/)
- [Backpressure in AI Workflows](https://ghuntley.com/pressure/)
- [LangGraph Checkpointing](https://docs.langchain.com/oss/python/langchain/human-in-the-loop)

### Curated Skills Referenced

- agent-native-architecture skill
- agent-execution-patterns reference
- file-todos skill
- compound-engineering workflows

---

## Implementation Notes

### Phased Rollout Strategy

1. **Phase 1-2** can ship as v2.0-alpha (modular + context)
2. **Phase 3-4** as v2.0-beta (self-healing + reuse)
3. **Phase 5-7** as v2.0-rc (gates + schema + metrics)
4. **Phase 8** as v2.1 (multi-agent coordination)

### Testing Strategy

- Unit tests with Bats for each module
- Integration tests for full loop execution
- Snapshot tests for SPEC parsing
- Chaos testing for self-healing (inject errors)

### Migration Path

1. Existing users run `borg upgrade`
2. Old `.borg/` structure migrated automatically
3. Existing SPECs validated and repaired if needed
4. Learnings preserved in new context format
