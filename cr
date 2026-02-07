#!/usr/bin/env bash
#
# cr - Compound Ralph: Autonomous Feature Implementation System
#
# Combines compound-engineering's planning workflows with the Ralph Loop
# technique for autonomous, iterative feature implementation.
#
# Usage:
#   cr init [project-path]           Initialize a project for Compound Ralph
#   cr converse <topic>              Explore ideas via Socratic dialogue
#   cr research <topic>              Deep investigation before planning
#   cr plan <feature-description>    Create and deepen a plan (uses knowledge/)
#   cr spec <plan-file>              Convert plan to SPEC.md format
#   cr implement [spec-dir]          Start autonomous implementation loop
#   cr status                        Show progress of all specs
#   cr help                          Show this help
#
# Requirements:
#   - git (version control)
#   - Claude Code CLI (claude) - https://claude.ai/code
#   - compound-engineering plugin:
#       /plugin marketplace add https://github.com/EveryInc/compound-engineering-plugin
#       /plugin install compound-engineering
#   - Vercel agent-browser CLI: npm install -g agent-browser && agent-browser install
#
# Philosophy:
#   Planning is human-guided and rich. Implementation is autonomous and focused.
#   Each iteration: fresh context + file-based state = no degradation.
#   Backpressure (tests, lint, types) lets agents self-correct.
#
# Author: Built with Claude Code
# Source: https://ghuntley.com/ralph/
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
CR_VERSION="2.1.0"
CR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECS_DIR="specs"
PLANS_DIR="plans"
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"
ITERATION_DELAY="${ITERATION_DELAY:-3}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
ITERATION_TIMEOUT="${ITERATION_TIMEOUT:-600}"  # 10 minutes per iteration
MAX_CONSECUTIVE_FAILURES="${MAX_CONSECUTIVE_FAILURES:-3}"

# Track consecutive failures
CONSECUTIVE_FAILURES=0

# Migration: .borg/ → .cr/ (one-time automatic migration)
migrate_borg_to_cr() {
    if [[ -d ".borg" ]] && [[ ! -d ".cr" ]]; then
        log_warn "Migrating .borg/ to .cr/ (one-time migration)"
        mv .borg .cr
        log_success "Migration complete. Config now at .cr/"
    fi
}

# Graceful shutdown handling
SHUTDOWN_REQUESTED=false
CHILD_PIDS=()

cleanup_and_exit() {
    echo ""
    log_warn "Shutdown requested. Cleaning up..."
    SHUTDOWN_REQUESTED=true

    # Kill any tracked child processes
    for pid in "${CHILD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
        fi
    done

    # Kill entire process group to catch any stragglers
    kill -TERM 0 2>/dev/null || true

    log_info "Exiting. Resume with: cr implement"
    exit 130
}
trap cleanup_and_exit SIGINT SIGTERM

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

# Load a prompt file from the prompts/ directory.
# Prompts were previously inline for single-file portability but were extracted
# to separate files for maintainability. Prompt files must be co-located with
# the cr script (i.e. in $CR_DIR/prompts/).
# Placeholders use __DOUBLE_UNDERSCORE__ convention to avoid collision with prompt content
load_prompt() {
    local filename="$1"
    local filepath="$CR_DIR/prompts/$filename"
    if [[ ! -f "$filepath" ]]; then
        log_error "Prompt file not found: $filepath"
        log_error "Ensure prompt files are co-located with the cr script in $CR_DIR/prompts/"
        exit 1
    fi
    cat "$filepath"
}

# Warn if unreplaced __PLACEHOLDER__ tokens remain after substitution
validate_prompt() {
    local prompt_text="$1"
    local prompt_name="$2"
    local leftover
    leftover=$(echo "$prompt_text" | grep -o '__[A-Z_]*__' | sort -u || true)
    if [[ -n "$leftover" ]]; then
        log_warn "Unreplaced placeholders in $prompt_name prompt:"
        echo "$leftover" | while read -r token; do
            log_warn "  $token"
        done
    fi
}

# Run Claude with retry logic and timeout
# Returns 0 on success, 1 on permanent failure
run_claude_with_retry() {
    local prompt="$1"
    local log_file="$2"
    local attempt=1
    local delay="$RETRY_DELAY"
    local temp_output
    temp_output=$(mktemp)

    # Cleanup temp file on exit
    trap "rm -f '$temp_output'" RETURN

    while [[ $attempt -le $MAX_RETRIES ]]; do
        # Check for shutdown request
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            return 1
        fi

        local exit_code=0

        # Show attempt info
        if [[ $attempt -gt 1 ]]; then
            echo -e "${YELLOW}[RETRY $attempt/$MAX_RETRIES]${NC} Attempting again..."
        fi

        # Run Claude with timeout using pure bash (works everywhere)
        # Disable set -e temporarily to capture exit code
        set +e

        # Start Claude in background
        echo "$prompt" | claude --dangerously-skip-permissions --print > "$temp_output" 2>&1 &
        local claude_pid=$!
        CHILD_PIDS+=("$claude_pid")

        # Start watchdog timer in background
        (
            sleep "$ITERATION_TIMEOUT"
            if kill -0 $claude_pid 2>/dev/null; then
                kill -TERM $claude_pid 2>/dev/null
                sleep 2
                kill -9 $claude_pid 2>/dev/null
            fi
        ) &
        local watchdog_pid=$!
        CHILD_PIDS+=("$watchdog_pid")

        # Wait for Claude to finish
        wait $claude_pid 2>/dev/null
        exit_code=$?

        # Kill watchdog if Claude finished first
        kill $watchdog_pid 2>/dev/null
        wait $watchdog_pid 2>/dev/null

        # Clear tracked PIDs (they're done)
        CHILD_PIDS=()

        # Check if it was killed by timeout (exit code 143 = SIGTERM, 137 = SIGKILL)
        if [[ $exit_code -eq 143 ]] || [[ $exit_code -eq 137 ]]; then
            log_error "Iteration timed out after ${ITERATION_TIMEOUT}s"
            exit_code=124  # Use same code as GNU timeout
        fi

        set -e

        # Read output from temp file
        local output=""
        if [[ -f "$temp_output" ]]; then
            output=$(cat "$temp_output")
        fi

        # Write output to log and terminal
        if [[ -n "$output" ]]; then
            echo "$output" | tee -a "$log_file"
        fi

        # Check for transient failures that warrant retry
        local is_transient=false
        local output_length=${#output}

        # Timeout is transient
        if [[ $exit_code -eq 124 ]]; then
            is_transient=true
        # Non-zero exit code is transient
        elif [[ $exit_code -ne 0 ]]; then
            is_transient=true
            log_warn "Claude exited with code $exit_code"
        elif [[ $output_length -lt 100 ]]; then
            # Short output - check if it's an error message
            if echo "$output" | grep -qiE "No messages returned|ECONNRESET|ETIMEDOUT|rate.limit exceeded|503 Service|502 Bad Gateway|overloaded|ENOTFOUND|socket hang up"; then
                is_transient=true
                log_warn "Transient API error detected in output"
            elif [[ -z "$output" ]]; then
                is_transient=true
                log_warn "Empty output received"
            fi
        fi

        if [[ "$is_transient" == "true" ]]; then
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                echo ""
                echo -e "${YELLOW}━━━ Retry ${attempt}/${MAX_RETRIES} ━━━${NC}"
                echo -e "${YELLOW}Waiting ${delay}s before retry...${NC}"
                echo -e "${YELLOW}(Ctrl+C to cancel)${NC}"
                echo ""
                sleep "$delay"
                attempt=$((attempt + 1))
                delay=$((delay * 2))  # Exponential backoff
                # Clear temp file for next attempt
                > "$temp_output"
                continue
            else
                log_error "Max retries ($MAX_RETRIES) exceeded. Moving to next iteration."
                return 1
            fi
        fi

        # Success - reset consecutive failures
        CONSECUTIVE_FAILURES=0
        return 0
    done

    return 1
}

check_prerequisites() {
    local missing=()

    if ! command -v claude &> /dev/null; then
        missing+=("claude (Claude Code CLI)")
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        exit 1
    fi
}

# Check if a script exists in package.json
# Usage: has_script "lint" [package.json path]
has_script() {
    local script_name="$1"
    local pkg_file="${2:-package.json}"

    if [[ -f "$pkg_file" ]] && command -v jq &>/dev/null; then
        [[ -n "$(jq -r ".scripts.\"$script_name\" // empty" "$pkg_file" 2>/dev/null)" ]]
    else
        return 1
    fi
}

detect_project_type() {
    local project_path="${1:-.}"

    if [[ -f "$project_path/package.json" ]]; then
        if grep -q '"bun"' "$project_path/package.json" 2>/dev/null || [[ -f "$project_path/bun.lockb" ]] || [[ -f "$project_path/bun.lock" ]]; then
            echo "bun"
        elif [[ -f "$project_path/yarn.lock" ]]; then
            echo "yarn"
        elif [[ -f "$project_path/pnpm-lock.yaml" ]]; then
            echo "pnpm"
        else
            echo "npm"
        fi
    elif [[ -f "$project_path/Gemfile" ]]; then
        echo "rails"
    elif [[ -f "$project_path/pyproject.toml" ]] || [[ -f "$project_path/requirements.txt" ]]; then
        echo "python"
    elif [[ -f "$project_path/go.mod" ]]; then
        echo "go"
    elif [[ -f "$project_path/Cargo.toml" ]]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

# Discover project configuration by reading actual files
# Creates/updates .cr/project.json with discovered settings
discover_project() {
    mkdir -p .cr

    local config_file=".cr/project.json"
    local pkg_manager=""
    local test_cmd=""
    local test_e2e_cmd=""
    local build_cmd=""
    local db_cmd=""
    local dev_cmd=""
    local e2e_dir=""

    # Detect package manager
    if [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
        pkg_manager="bun"
    elif [[ -f "yarn.lock" ]]; then
        pkg_manager="yarn"
    elif [[ -f "pnpm-lock.yaml" ]]; then
        pkg_manager="pnpm"
    elif [[ -f "package-lock.json" ]] || [[ -f "package.json" ]]; then
        pkg_manager="npm"
    elif [[ -f "Gemfile" ]]; then
        pkg_manager="bundle"
    elif [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        pkg_manager="pip"
    fi

    # Read package.json scripts if it exists
    if [[ -f "package.json" ]]; then
        # Find test script (try common names)
        for script in "test" "test:unit" "vitest" "jest"; do
            if grep -q "\"$script\":" package.json 2>/dev/null; then
                test_cmd="$pkg_manager run $script"
                # Add --run for vitest to prevent watch mode
                if grep -q "vitest" package.json 2>/dev/null; then
                    test_cmd="$pkg_manager test --run"
                fi
                break
            fi
        done

        # Find e2e test script
        for script in "test:e2e" "e2e" "test:integration" "playwright" "cypress"; do
            if grep -q "\"$script\":" package.json 2>/dev/null; then
                test_e2e_cmd="$pkg_manager run $script"
                break
            fi
        done

        # Find build script
        for script in "build" "compile" "dist"; do
            if grep -q "\"$script\":" package.json 2>/dev/null; then
                build_cmd="$pkg_manager run $script"
                break
            fi
        done

        # Find db script
        for script in "db:push" "db:migrate" "migrate" "prisma:push"; do
            if grep -q "\"$script\":" package.json 2>/dev/null; then
                db_cmd="$pkg_manager run $script"
                break
            fi
        done

        # Find dev script
        for script in "dev" "start" "serve"; do
            if grep -q "\"$script\":" package.json 2>/dev/null; then
                dev_cmd="$pkg_manager run $script"
                break
            fi
        done
    fi

    # Rails fallbacks
    if [[ -f "bin/rails" ]]; then
        [[ -z "$test_cmd" ]] && test_cmd="bin/rails test"
        [[ -z "$db_cmd" ]] && db_cmd="bin/rails db:migrate"
        [[ -z "$dev_cmd" ]] && dev_cmd="bin/rails server"
    fi

    # Python fallbacks
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        [[ -z "$test_cmd" ]] && test_cmd="pytest"
    fi

    # Detect e2e directory
    for dir in "e2e" "tests/e2e" "test/e2e" "cypress" "playwright"; do
        if [[ -d "$dir" ]]; then
            e2e_dir="$dir"
            break
        fi
    done

    # Detect dev server port from config files
    local dev_port=""
    local dev_url=""

    # Check Astro config
    if ls astro.config.* 2>/dev/null | grep -q .; then
        local config_file_check
        config_file_check=$(ls astro.config.* 2>/dev/null | head -1)
        dev_port=$(grep -oE 'port["\s]*:["\s]*[0-9]+' "$config_file_check" 2>/dev/null | grep -oE '[0-9]+' | head -1)
        [[ -z "$dev_port" ]] && dev_port=4321
    # Check Vite config
    elif ls vite.config.* 2>/dev/null | grep -q .; then
        local config_file_check
        config_file_check=$(ls vite.config.* 2>/dev/null | head -1)
        dev_port=$(grep -oE 'port["\s]*:["\s]*[0-9]+' "$config_file_check" 2>/dev/null | grep -oE '[0-9]+' | head -1)
        [[ -z "$dev_port" ]] && dev_port=5173
    # Check Next.js config
    elif ls next.config.* 2>/dev/null | grep -q .; then
        dev_port=3000
    # Check Rails
    elif [[ -f "bin/rails" ]]; then
        dev_port=3000
    fi

    [[ -n "$dev_port" ]] && dev_url="http://localhost:$dev_port"

    # Get file modification times for change detection
    local pkg_mtime=""
    local lock_mtime=""
    if [[ -f "package.json" ]]; then
        pkg_mtime=$(stat -f "%m" "package.json" 2>/dev/null || stat -c "%Y" "package.json" 2>/dev/null || echo "")
    fi
    for lockfile in bun.lockb bun.lock yarn.lock pnpm-lock.yaml package-lock.json Gemfile.lock; do
        if [[ -f "$lockfile" ]]; then
            lock_mtime=$(stat -f "%m" "$lockfile" 2>/dev/null || stat -c "%Y" "$lockfile" 2>/dev/null || echo "")
            break
        fi
    done

    # Write config
    cat > "$config_file" << EOF
{
  "discovered": "$(date -Iseconds)",
  "package_manager": "$pkg_manager",
  "dev_url": "$dev_url",
  "commands": {
    "test": "$test_cmd",
    "test_e2e": "$test_e2e_cmd",
    "build": "$build_cmd",
    "db": "$db_cmd",
    "dev": "$dev_cmd"
  },
  "paths": {
    "e2e_dir": "$e2e_dir"
  },
  "mtimes": {
    "package_json": "$pkg_mtime",
    "lockfile": "$lock_mtime"
  }
}
EOF

    log_info "Project config saved to $config_file"
}

# Read a value from .cr/project.json
# Usage: get_project_config "commands.test"
get_project_config() {
    local key="$1"
    local config_file=".cr/project.json"

    if [[ ! -f "$config_file" ]]; then
        discover_project
    fi

    # Parse JSON with jq if available, otherwise grep
    if command -v jq &>/dev/null; then
        jq -r ".$key // empty" "$config_file" 2>/dev/null
    else
        # Fallback: simple grep for the value
        grep "\"${key##*.}\":" "$config_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/'
    fi
}

# Check if project config files have changed since last discovery
# Returns 0 if changed (needs rediscovery), 1 if unchanged
check_config_changed() {
    local config_file=".cr/project.json"

    [[ ! -f "$config_file" ]] && return 0  # No config = needs discovery

    # Get current mtimes
    local current_pkg_mtime=""
    local current_lock_mtime=""

    if [[ -f "package.json" ]]; then
        current_pkg_mtime=$(stat -f "%m" "package.json" 2>/dev/null || stat -c "%Y" "package.json" 2>/dev/null || echo "")
    fi
    for lockfile in bun.lockb bun.lock yarn.lock pnpm-lock.yaml package-lock.json Gemfile.lock; do
        if [[ -f "$lockfile" ]]; then
            current_lock_mtime=$(stat -f "%m" "$lockfile" 2>/dev/null || stat -c "%Y" "$lockfile" 2>/dev/null || echo "")
            break
        fi
    done

    # Get stored mtimes
    local stored_pkg_mtime stored_lock_mtime
    if command -v jq &>/dev/null; then
        stored_pkg_mtime=$(jq -r '.mtimes.package_json // empty' "$config_file" 2>/dev/null)
        stored_lock_mtime=$(jq -r '.mtimes.lockfile // empty' "$config_file" 2>/dev/null)
    else
        stored_pkg_mtime=$(grep '"package_json"' "$config_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
        stored_lock_mtime=$(grep '"lockfile"' "$config_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
    fi

    # Compare
    if [[ "$current_pkg_mtime" != "$stored_pkg_mtime" ]] || [[ "$current_lock_mtime" != "$stored_lock_mtime" ]]; then
        return 0  # Changed
    fi
    return 1  # Unchanged
}

# Validate a command string against an allowlist of safe executables and characters.
# Security comes from THIS VALIDATOR, not from the execution method (bash -c).
# bash -c is functionally equivalent to eval for injection purposes — we use it
# for process isolation consistency, not for injection prevention.
#
# Known bypass vectors NOT fully covered (defense-in-depth, not a sandbox):
#   - Newline injection: $'cmd1\ncmd2'
#   - ${} parameter expansion in arguments
#   - Heredocs (<<)
# TODO: Consider a stricter sandbox (e.g., firejail) for untrusted projects.
#
# Returns 0 if safe, 1 if rejected.
# Usage: validate_command "$cmd"
validate_command() {
    local cmd="$1"

    # Strip safe patterns before validation: stderr redirects and || true (non-fatal suffix)
    local sanitized
    sanitized=$(echo "$cmd" | sed -e 's/2>\/dev\/null//g' -e 's/2>\&1//g' -e 's/|| true//g' | xargs)

    # Extract the first word (the executable)
    local first_word
    first_word=$(echo "$sanitized" | awk '{print $1}')

    # Remove CI=true or CI=1 prefix if present (environment variable prefix)
    if [[ "$first_word" == "CI=true" ]] || [[ "$first_word" == "CI=1" ]]; then
        sanitized=$(echo "$sanitized" | sed 's/^CI=[^ ]* //')
        first_word=$(echo "$sanitized" | awk '{print $1}')
    fi

    # Normalize path-prefixed executables (e.g., bin/rails -> rails)
    local exe_name
    exe_name=$(basename "$first_word")

    # Allowlist of known safe executables
    local -a allowed_executables=(
        bun npm yarn pnpm npx bunx node
        python ruby bundle rails pytest rspec
        cargo go make tsc eslint prettier
        ruff mypy bandit golangci-lint gosec
    )

    local allowed=false
    for exe in "${allowed_executables[@]}"; do
        if [[ "$exe_name" == "$exe" ]]; then
            allowed=true
            break
        fi
    done

    if [[ "$allowed" != "true" ]]; then
        log_warn "SECURITY: Rejected command with disallowed executable '$first_word': $cmd"
        return 1
    fi

    # After confirming the executable, verify the rest contains only safe characters:
    # alphanumeric, spaces, dashes, dots, slashes, equals, colons, quotes, @, underscores
    local rest
    rest=$(echo "$sanitized" | sed 's/^[^ ]* //')
    if [[ "$sanitized" == "$first_word" ]]; then
        rest=""  # No arguments
    fi

    if [[ -n "$rest" ]] && echo "$rest" | grep -qE '[^a-zA-Z0-9 _./:=@"'"'"'-]'; then
        log_warn "SECURITY: Rejected command with unsafe characters in arguments: $cmd"
        return 1
    fi

    return 0
}

# Run lightweight per-iteration checks (tests + lint on changed files)
# Extract quality gate commands from SPEC.md
# Parses the "Quality Gates" section for backtick commands
# Skips lines marked with [INFORMATIONAL] - those are logged but non-blocking
# Usage: get_spec_quality_commands "$spec_file"
get_spec_quality_commands() {
    local spec_file="$1"
    [[ ! -f "$spec_file" ]] && return

    # Extract commands from Quality Gates section
    # Skip lines containing [INFORMATIONAL] - those are non-blocking
    # Look for backtick commands like `bun astro check` or `bun run build`
    awk '/^## Quality Gates/,/^## [^Q]/' "$spec_file" 2>/dev/null | \
        grep -v '\[INFORMATIONAL\]' | \
        grep -oE '`[^`]+`' | \
        tr -d '`' | \
        grep -E '^(bun|npm|yarn|pnpm|npx|bunx|node|python|ruby|bundle|rails|pytest|rspec|cargo|go) ' | \
        sort -u
}

# Extract INFORMATIONAL quality gate commands (logged but non-blocking)
# Usage: get_spec_informational_commands "$spec_file"
get_spec_informational_commands() {
    local spec_file="$1"
    [[ ! -f "$spec_file" ]] && return

    # Extract commands from lines marked [INFORMATIONAL]
    awk '/^## Quality Gates/,/^## [^Q]/' "$spec_file" 2>/dev/null | \
        grep '\[INFORMATIONAL\]' | \
        grep -oE '`[^`]+`' | \
        tr -d '`' | \
        grep -E '^(bun|npm|yarn|pnpm|npx|bunx|node|python|ruby|bundle|rails|pytest|rspec|cargo|go) ' | \
        sort -u
}

# Track repeated failures across iterations
# File: .cr/failure_tracking.json
# Format: {"gate_name": {"count": N, "last_error_hash": "..."}}
FAILURE_TRACKING_FILE=".cr/failure_tracking.json"

init_failure_tracking() {
    mkdir -p .cr
    if [[ ! -f "$FAILURE_TRACKING_FILE" ]]; then
        echo '{}' > "$FAILURE_TRACKING_FILE"
    fi
}

# Record a failure and return how many times this gate has failed consecutively
# Usage: record_gate_failure "gate_command" "error_output"
# Returns: failure count for this gate
record_gate_failure() {
    local gate="$1"
    local error_output="$2"
    init_failure_tracking

    # Create a hash of the error to detect if it's the same error
    local error_hash
    error_hash=$(echo "$error_output" | head -5 | md5sum | cut -d' ' -f1 2>/dev/null || echo "unknown")

    # Safe key for JSON (replace special chars)
    local safe_gate
    safe_gate=$(echo "$gate" | tr -c '[:alnum:]' '_')

    if command -v jq &>/dev/null; then
        local current_count current_hash
        current_count=$(jq -r ".\"$safe_gate\".count // 0" "$FAILURE_TRACKING_FILE" 2>/dev/null || echo "0")
        current_hash=$(jq -r ".\"$safe_gate\".last_error_hash // \"\"" "$FAILURE_TRACKING_FILE" 2>/dev/null || echo "")

        # If same error, increment count; if different error, reset to 1
        local new_count
        if [[ "$current_hash" == "$error_hash" ]]; then
            new_count=$((current_count + 1))
        else
            new_count=1
        fi

        # Update tracking
        jq --arg gate "$safe_gate" --argjson count "$new_count" --arg hash "$error_hash" \
           '.[$gate] = {"count": $count, "last_error_hash": $hash}' \
           "$FAILURE_TRACKING_FILE" > "$FAILURE_TRACKING_FILE.tmp" && \
           mv "$FAILURE_TRACKING_FILE.tmp" "$FAILURE_TRACKING_FILE"

        echo "$new_count"
    else
        echo "1"
    fi
}

# Clear failure tracking for a gate (call when it passes)
# Usage: clear_gate_failure "gate_command"
clear_gate_failure() {
    local gate="$1"
    init_failure_tracking

    local safe_gate
    safe_gate=$(echo "$gate" | tr -c '[:alnum:]' '_')

    if command -v jq &>/dev/null; then
        jq "del(.\"$safe_gate\")" "$FAILURE_TRACKING_FILE" > "$FAILURE_TRACKING_FILE.tmp" && \
           mv "$FAILURE_TRACKING_FILE.tmp" "$FAILURE_TRACKING_FILE"
    fi
}

# Maximum times a gate can fail with the same error before we warn about it
MAX_REPEATED_FAILURES=5

# Returns 0 if all pass, 1 if any fail
# Sets ITERATION_ISSUES array with failures
# SPEC-DRIVEN: Reads quality gates from SPEC.md and runs those commands
run_iteration_checks() {
    ITERATION_ISSUES=()
    local all_passed=true

    # Ensure project is discovered
    if [[ ! -f ".cr/project.json" ]]; then
        discover_project
    fi

    # Check for config changes and rediscover if needed
    if check_config_changed; then
        log_info "Project config changed, rediscovering..."
        discover_project

        # Re-install dependencies if lockfile changed
        local pkg_manager
        pkg_manager=$(get_project_config "package_manager")
        case "$pkg_manager" in
            bun)  bun install 2>/dev/null ;;
            npm)  npm install 2>/dev/null ;;
            yarn) yarn install 2>/dev/null ;;
            pnpm) pnpm install 2>/dev/null ;;
            bundle) bundle install 2>/dev/null ;;
        esac
    fi

    # Find the active SPEC.md
    local spec_file=""
    if [[ -n "${CURRENT_SPEC_DIR:-}" ]] && [[ -f "${CURRENT_SPEC_DIR}/SPEC.md" ]]; then
        spec_file="${CURRENT_SPEC_DIR}/SPEC.md"
    else
        # Try to find it
        spec_file=$(find specs -name "SPEC.md" -type f 2>/dev/null | head -1)
    fi

    # SPEC-DRIVEN CHECKS: Run commands from SPEC.md Quality Gates section
    local spec_commands_run=0
    if [[ -n "$spec_file" ]] && [[ -f "$spec_file" ]]; then
        log_info "Reading quality gates from: $spec_file"

        # Run blocking quality gates
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue

            # Skip visual/manual checks
            [[ "$cmd" == *"screenshot"* ]] && continue
            [[ "$cmd" == *"agent-browser"* ]] && continue

            log_info "Running quality gate: $cmd"

            # Validate command before execution
            if ! validate_command "$cmd"; then
                ITERATION_ISSUES+=("Quality gate rejected (unsafe command): $cmd")
                all_passed=false
                continue
            fi

            spec_commands_run=$((spec_commands_run + 1))

            # Capture output for failure tracking
            local gate_output
            gate_output=$(bash -c "$cmd" 2>&1 | tail -50)
            local gate_exit_code=${PIPESTATUS[0]}

            echo "$gate_output" | tail -20

            if [[ $gate_exit_code -ne 0 ]]; then
                # Track how many times this gate has failed with same error
                local failure_count
                failure_count=$(record_gate_failure "$cmd" "$gate_output")

                ITERATION_ISSUES+=("Quality gate failed: $cmd")
                all_passed=false

                # Save the actual error output so it can be injected into next iteration
                # This is CRITICAL - the agent needs to SEE the errors to fix them
                mkdir -p .cr
                {
                    echo "=== FAILED GATE: $cmd ==="
                    echo "$gate_output"
                    echo ""
                } >> .cr/gate_failures.txt

                # Warn if this gate keeps failing with the same error
                if [[ "$failure_count" -ge "$MAX_REPEATED_FAILURES" ]]; then
                    log_warn "Gate '$cmd' has failed $failure_count times with same error!"
                    log_warn "The agent MUST fix this error, not ignore it."
                    log_warn "If truly unfixable, mark as [INFORMATIONAL] in SPEC.md"
                fi
            else
                # Gate passed - clear failure tracking
                clear_gate_failure "$cmd"
            fi
        done < <(get_spec_quality_commands "$spec_file")

        # Run informational gates (logged but non-blocking)
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            [[ "$cmd" == *"screenshot"* ]] && continue
            [[ "$cmd" == *"agent-browser"* ]] && continue

            log_info "Running informational gate: $cmd"
            if ! validate_command "$cmd"; then
                log_warn "Informational gate rejected (unsafe command): $cmd"
                continue
            fi
            if ! bash -c "$cmd" 2>&1 | tail -10; then
                log_warn "Informational gate failed (non-blocking): $cmd"
            fi
        done < <(get_spec_informational_commands "$spec_file")
    fi

    # FALLBACK: If no SPEC commands found, warn and use minimal project.json detection
    if [[ $spec_commands_run -eq 0 ]]; then
        log_warn "No quality gates found in SPEC.md!"
        log_warn "The implementing agent should discover and add quality gates."
        log_warn "Attempting minimal fallback using project.json scripts..."

        # Only run what we can discover from project.json - no framework-specific hardcoding
        local pkg_manager
        pkg_manager=$(get_project_config "package_manager")

        # Try test command from project.json
        local test_cmd
        test_cmd=$(get_project_config "commands.test")
        if [[ -n "$test_cmd" ]]; then
            log_info "Running discovered test command: $test_cmd"
            if ! validate_command "$test_cmd"; then
                ITERATION_ISSUES+=("Tests rejected (unsafe command): $test_cmd")
                all_passed=false
            elif ! bash -c "CI=true $test_cmd" 2>&1 | tail -20; then
                ITERATION_ISSUES+=("Tests failed")
                all_passed=false
            fi
        fi

        # Try lint only if explicitly in package.json scripts (not framework-specific)
        if [[ -f "package.json" ]] && [[ -n "$pkg_manager" ]]; then
            if grep -q '"lint"' package.json 2>/dev/null; then
                local lint_cmd="$pkg_manager run lint"
                log_info "Running discovered lint command: $lint_cmd"
                if ! validate_command "$lint_cmd"; then
                    ITERATION_ISSUES+=("Lint rejected (unsafe command): $lint_cmd")
                    all_passed=false
                elif ! bash -c "$lint_cmd" 2>&1 | tail -10; then
                    ITERATION_ISSUES+=("Lint failed")
                    all_passed=false
                fi
            fi
        fi

        # Note: We intentionally don't run typecheck/build here unless they're in SPEC
        # The agent should discover and add appropriate quality gates to SPEC.md
    fi

    # VISUAL/FUNCTIONAL VERIFICATION
    # Run if we have UI changes and agent-browser is available
    if command -v agent-browser &>/dev/null; then
        local dev_url
        dev_url=$(get_project_config "dev_url")

        if [[ -n "$dev_url" ]]; then
            # Check if dev server is running
            if curl -s --max-time 2 "$dev_url" > /dev/null 2>&1; then
                log_info "Running visual verification at $dev_url"

                # Create screenshots directory
                local screenshot_dir=".cr/screenshots"
                mkdir -p "$screenshot_dir"
                local timestamp
                timestamp=$(date '+%Y%m%d-%H%M%S')

                # Open the base page first
                agent-browser open "$dev_url" 2>/dev/null || true
                sleep 2  # Wait for page to load

                # Discover all pages via navigation links (like cr design does)
                local all_pages_raw all_pages
                all_pages_raw=$(agent-browser eval "Array.from(document.querySelectorAll('nav a, header a, footer a, [role=navigation] a, main a')).map(a => a.href).filter(h => h && h.startsWith(window.location.origin)).filter((v,i,a) => a.indexOf(v) === i).join('|')" 2>&1) || true

                # Clean up the output: remove quotes, convert | to newlines
                all_pages=$(echo "$all_pages_raw" | tr -d '"' | tr -d "'" | tr '|' '\n')

                # Build list of pages to check (base URL + discovered pages, max 5)
                local pages_to_check=("$dev_url")
                if [[ -n "$all_pages" ]] && [[ "$all_pages" != *"error"* ]]; then
                    local page_count=0
                    while IFS= read -r page; do
                        # Clean the URL
                        page=$(echo "$page" | xargs)
                        [[ -z "$page" ]] && continue
                        [[ "$page" != http* ]] && continue
                        [[ "$page" == "$dev_url" ]] && continue
                        [[ "$page" == "$dev_url/" ]] && continue
                        [[ "$page" == *"#"* ]] && continue  # Skip anchor links
                        pages_to_check+=("$page")
                        page_count=$((page_count + 1))
                        [[ $page_count -ge 4 ]] && break  # Max 4 additional pages
                    done <<< "$all_pages"
                fi

                log_info "Checking ${#pages_to_check[@]} pages: ${pages_to_check[*]}"

                # Check each page
                local page_issues=()
                for page_url in "${pages_to_check[@]}"; do
                    local page_name="${page_url#$dev_url}"
                    [[ -z "$page_name" ]] && page_name="/"

                    # Open the page
                    agent-browser open "$page_url" 2>/dev/null || true
                    sleep 1

                    # Take screenshot
                    local safe_name="${page_name//\//_}"
                    [[ "$safe_name" == "_" ]] && safe_name="home"
                    local screenshot_file="$screenshot_dir/iteration-$timestamp-$safe_name.png"
                    agent-browser screenshot "$screenshot_file" 2>/dev/null || true

                    if [[ -f "$screenshot_file" ]]; then
                        log_info "Screenshot: $page_name → $screenshot_file"
                    fi

                    # Run checks for this page
                    # Clear any pre-existing errors before running checks
                    agent-browser errors --clear 2>/dev/null || true

                    # Check 1: Error overlays present?
                    local has_error_overlay
                    has_error_overlay=$(agent-browser eval "document.querySelectorAll('[data-nextjs-error], .error-overlay, #webpack-dev-server-client-overlay, [class*=vite-error], .svelte-error-overlay').length" 2>&1) || true
                    if [[ "$has_error_overlay" =~ ^[0-9]+$ ]] && [[ "$has_error_overlay" -gt 0 ]]; then
                        ITERATION_ISSUES+=("$page_name: Error overlay detected")
                        all_passed=false
                        log_warn "$page_name: Error overlay detected"
                    fi

                    # Check 2: Page too small/blank?
                    local body_length
                    body_length=$(agent-browser eval "document.body ? document.body.innerHTML.trim().length : 0" 2>&1) || true
                    if [[ "$body_length" =~ ^[0-9]+$ ]] && [[ "$body_length" -lt 50 ]]; then
                        ITERATION_ISSUES+=("$page_name: Page appears blank")
                        all_passed=false
                        log_warn "$page_name: Page appears blank"
                    fi

                    # Check 3: Interactive elements - buttons on this page
                    local button_count clickable_buttons
                    button_count=$(agent-browser eval "document.querySelectorAll('button, [role=button]').length" 2>&1) || true
                    clickable_buttons=$(agent-browser eval "Array.from(document.querySelectorAll('button, [role=button]')).filter(function(el) { var s = window.getComputedStyle(el); return s.pointerEvents !== 'none' && s.display !== 'none'; }).length" 2>&1) || true

                    if [[ "$button_count" =~ ^[0-9]+$ ]] && [[ "$button_count" -gt 0 ]]; then
                        if [[ "$clickable_buttons" =~ ^[0-9]+$ ]] && [[ "$clickable_buttons" -eq 0 ]]; then
                            ITERATION_ISSUES+=("$page_name: All $button_count buttons disabled/hidden")
                            all_passed=false
                            log_warn "$page_name: All $button_count buttons disabled/hidden"
                        else
                            log_info "$page_name: $clickable_buttons/$button_count buttons clickable"
                        fi
                    fi

                    # Check 4: Loading spinners stuck?
                    local loader_count
                    loader_count=$(agent-browser eval "document.querySelectorAll('[class*=loading], [class*=spinner], [aria-busy=true]').length" 2>&1) || true
                    if [[ "$loader_count" =~ ^[0-9]+$ ]] && [[ "$loader_count" -gt 3 ]]; then
                        ITERATION_ISSUES+=("$page_name: Stuck loading state ($loader_count spinners)")
                        all_passed=false
                        log_warn "$page_name: Stuck loading state"
                    fi

                    # Check 5: Page responsiveness
                    local start_time end_time duration
                    start_time=$(date +%s)
                    local responsive_check
                    responsive_check=$(agent-browser eval "Date.now()" 2>&1) || true
                    end_time=$(date +%s)
                    duration=$((end_time - start_time))

                    if [[ "$duration" -gt 3 ]]; then
                        ITERATION_ISSUES+=("$page_name: Slow response (${duration}s)")
                        all_passed=false
                        log_warn "$page_name: Slow response (${duration}s)"
                    fi

                    # Check 6: Visible error text
                    local error_text_check
                    error_text_check=$(agent-browser eval "document.body && document.body.innerText.match(/Uncaught|ReferenceError|TypeError|SyntaxError|RangeError|out of memory|OOM/i) ? 'ERROR_FOUND' : 'OK'" 2>&1) || true
                    if [[ "$error_text_check" == "ERROR_FOUND" ]]; then
                        ITERATION_ISSUES+=("$page_name: Error text visible")
                        all_passed=false
                        log_warn "$page_name: Error text visible"
                    fi

                    # Check 7: Browser console errors (checked last to catch async errors)
                    local console_errors
                    console_errors=$(agent-browser errors 2>&1 | sed 's/\x1b\[[0-9;]*m//g') || true
                    if [[ -n "$console_errors" ]]; then
                        local error_count
                        error_count=$(echo "$console_errors" | grep -c -E "." 2>/dev/null || echo "0")
                        if [[ "$error_count" -gt 0 ]]; then
                            ITERATION_ISSUES+=("$page_name: Console errors ($error_count lines)")
                            all_passed=false
                            log_warn "$page_name: Console errors detected ($error_count lines)"
                            # Log first few errors for context
                            echo "$console_errors" | head -3 | while read -r line; do
                                [[ -n "$line" ]] && log_warn "  $line"
                            done
                        fi
                    fi
                done

                # Close the browser to clean up
                agent-browser close 2>/dev/null || true
            else
                log_info "Dev server not running at $dev_url - skipping visual verification"
            fi
        fi
    fi

    if [[ "$all_passed" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if a learning is harmful and should be rejected
# Returns 0 (true) if the learning should be blocked
# Harmful patterns: encourage skipping, ignoring, or dismissing quality gate failures
is_harmful_learning() {
    local learning="$1"
    local learning_lower
    learning_lower=$(echo "$learning" | tr '[:upper:]' '[:lower:]')

    # Block patterns that encourage skipping/ignoring quality gates
    local harmful_patterns=(
        "pre-existing.*skip"
        "pre-existing.*ignore"
        "pre-existing.*resolve.*immediately"
        "skip.*check"
        "skip.*gate"
        "ignore.*failure"
        "ignore.*error"
        "mark.*resolved.*immediately"
        "resolve.*by updating documentation"
        "doesn't affect runtime"
        "documentation rather than.*fix"
        "not affect.*runtime"
    )

    for pattern in "${harmful_patterns[@]}"; do
        if echo "$learning_lower" | grep -qE "$pattern"; then
            log_warn "BLOCKED harmful learning: $learning"
            log_warn "Quality gates must NEVER be skipped or ignored"
            return 0  # true - is harmful
        fi
    done

    return 1  # false - not harmful
}

# Add a learning to .cr/learnings.json
# Usage: add_learning "category" "learning text" "file1,file2"
add_learning() {
    local category="$1"
    local learning="$2"
    local files="${3:-}"
    local spec="${4:-unknown}"
    local iteration="${5:-0}"

    # FILTER: Reject harmful learnings that encourage skipping quality gates
    if is_harmful_learning "$learning"; then
        log_warn "Rejected harmful learning - quality gates must always be fixed, never skipped"
        return 0
    fi

    mkdir -p .cr
    local learnings_file=".cr/learnings.json"

    # Initialize if doesn't exist
    if [[ ! -f "$learnings_file" ]]; then
        echo '{"learnings":[]}' > "$learnings_file"
    fi

    # Use jq for safe JSON construction (jq --arg handles escaping automatically)
    if command -v jq &>/dev/null; then
        # Build entry safely with jq
        local files_array="[]"
        if [[ -n "$files" ]]; then
            files_array=$(echo "$files" | tr ',' '\n' | jq -R . | jq -s .)
        fi

        jq --arg date "$(date -Iseconds)" \
           --arg spec "$spec" \
           --argjson iteration "$iteration" \
           --arg category "$category" \
           --arg learning "$learning" \
           --argjson files "$files_array" \
           '.learnings += [{date: $date, spec: $spec, iteration: $iteration, category: $category, learning: $learning, files: $files}]' \
           "$learnings_file" > "$learnings_file.tmp" && mv "$learnings_file.tmp" "$learnings_file"
    else
        # Fallback: manual JSON construction with escaping (macOS compatible)
        local escaped_learning escaped_spec
        escaped_learning=$(printf '%s' "$learning" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
        escaped_spec=$(printf '%s' "$spec" | sed 's/\\/\\\\/g; s/"/\\"/g')
        local entry="{\"date\":\"$(date -Iseconds)\",\"spec\":\"$escaped_spec\",\"iteration\":$iteration,\"category\":\"$category\",\"learning\":\"$escaped_learning\",\"files\":[]}"
        sed -i '' 's/\]}/,'"$entry"']}/' "$learnings_file" 2>/dev/null || \
        sed -i 's/\]}/,'"$entry"']}/' "$learnings_file"
    fi
}

# Get recent learnings summary for context
# Usage: get_learnings_summary [category] [limit]
get_learnings_summary() {
    local category="${1:-}"
    local limit="${2:-10}"
    local learnings_file=".cr/learnings.json"

    [[ ! -f "$learnings_file" ]] && return

    if command -v jq &>/dev/null; then
        if [[ -n "$category" ]]; then
            jq -r ".learnings | map(select(.category == \"$category\")) | .[-$limit:] | .[] | \"[\(.category)] \(.learning)\"" "$learnings_file" 2>/dev/null
        else
            jq -r ".learnings | .[-$limit:] | .[] | \"[\(.category)] \(.learning)\"" "$learnings_file" 2>/dev/null
        fi
    else
        # Fallback: just show the file
        tail -50 "$learnings_file"
    fi
}

#=============================================================================
# CONTEXT PRESERVATION (Learnings persist across fresh Claude instances)
#=============================================================================

# Get context for injection into prompts
# Returns formatted context string from learnings.json
get_context_for_prompt() {
    local learnings=""
    local errors=""
    local patterns=""
    local learnings_file=".cr/learnings.json"

    if [[ -f "$learnings_file" ]] && command -v jq &>/dev/null; then
        # Get discovery/success learnings
        learnings=$(jq -r '.learnings // [] | map(select(.category == "discovery" or .category == "success")) | .[-10:] | map("- " + .learning) | join("\n")' "$learnings_file" 2>/dev/null || echo "")
        # Get fix learnings
        errors=$(jq -r '.learnings // [] | map(select(.category == "fix")) | .[-10:] | map("- " + .learning) | join("\n")' "$learnings_file" 2>/dev/null || echo "")
        # Get pattern learnings
        patterns=$(jq -r '.learnings // [] | map(select(.category == "pattern")) | .[-10:] | map("- " + .learning) | join("\n")' "$learnings_file" 2>/dev/null || echo "")
    fi

    cat << EOF
## Accumulated Context (from previous iterations)

### Learnings
${learnings:-None yet}

### Errors You've Fixed Before (Don't Repeat)
${errors:-None yet}

### Patterns Discovered in This Codebase
${patterns:-None yet}
EOF
}

#=============================================================================
# CONTEXT PERSISTENCE ENHANCEMENT (Parse and persist learnings from output)
#=============================================================================

# Parse iteration output for learning markers
# Extracts COMPLETED, FILES, TESTS, LEARNING, PATTERN, FIXED, BLOCKER markers
# Usage: parse_iteration_output "$log_file" "$spec_name" "$iteration"
parse_iteration_output() {
    local log_file="$1"
    local spec_name="${2:-unknown}"
    local iteration="${3:-0}"

    [[ ! -f "$log_file" ]] && return 0

    # Helper to strip markdown bold markers and extract value
    # Handles both "MARKER: value" and "**MARKER:** value"
    extract_marker_value() {
        local line="$1"
        local marker="$2"
        # Remove ** prefix/suffix if present, then extract value after marker
        echo "$line" | sed -E "s/^\*{0,2}${marker}:\*{0,2} *//"
    }

    # Extract LEARNING markers (handles **LEARNING:** and LEARNING:)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local learning
        learning=$(extract_marker_value "$line" "LEARNING")
        if [[ -n "$learning" ]]; then
            add_learning "discovery" "$learning" "" "$spec_name" "$iteration"
            log_info "Captured learning: $learning"
        fi
    done < <(grep -oE "(\*\*)?LEARNING:(\*\*)? .+" "$log_file" 2>/dev/null || true)

    # Extract PATTERN markers
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pattern
        pattern=$(extract_marker_value "$line" "PATTERN")
        if [[ -n "$pattern" ]]; then
            add_learning "pattern" "Pattern: $pattern" "" "$spec_name" "$iteration"
            log_info "Captured pattern: $pattern"
        fi
    done < <(grep -oE "(\*\*)?PATTERN:(\*\*)? .+" "$log_file" 2>/dev/null || true)

    # Extract FIXED markers (format: FIXED: error → solution)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local fixed
        fixed=$(extract_marker_value "$line" "FIXED")
        if [[ -n "$fixed" ]]; then
            # Parse error and fix from "error → fix" format
            if [[ "$fixed" == *"→"* ]]; then
                local error_part="${fixed%% →*}"
                local fix_part="${fixed#*→ }"
                add_learning "fix" "Fixed: $fixed" "" "$spec_name" "$iteration"
                log_info "Captured fix: $error_part → $fix_part"
            fi
        fi
    done < <(grep -oE "(\*\*)?FIXED:(\*\*)? .+" "$log_file" 2>/dev/null || true)

    # Extract COMPLETED markers for success tracking
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local completed
        completed=$(extract_marker_value "$line" "COMPLETED")
        if [[ -n "$completed" ]]; then
            add_learning "success" "Completed: $completed" "" "$spec_name" "$iteration"
            log_info "Captured completion: $completed"
        fi
    done < <(grep -oE "(\*\*)?COMPLETED:(\*\*)? .+" "$log_file" 2>/dev/null || true)

    # Extract BLOCKER markers
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local blocker
        blocker=$(extract_marker_value "$line" "BLOCKER")
        if [[ -n "$blocker" ]]; then
            add_learning "blocker" "Blocker: $blocker" "" "$spec_name" "$iteration"
            log_warn "Captured blocker: $blocker"
        fi
    done < <(grep -oE "(\*\*)?BLOCKER:(\*\*)? .+" "$log_file" 2>/dev/null || true)

    return 0
}

# Get the previous iteration's log file
# Usage: get_previous_iteration_log "$history_dir" "$current_iteration"
get_previous_iteration_log() {
    local history_dir="$1"
    local current_iteration="$2"

    [[ ! -d "$history_dir" ]] && return 1
    [[ "$current_iteration" -le 1 ]] && return 1

    local prev_iteration=$((current_iteration - 1))
    local prev_prefix=$(printf '%03d' $prev_iteration)

    # Find log file matching the prefix
    local prev_log
    prev_log=$(find "$history_dir" -name "${prev_prefix}-*.md" -type f 2>/dev/null | head -1)

    if [[ -n "$prev_log" ]] && [[ -f "$prev_log" ]]; then
        echo "$prev_log"
        return 0
    fi

    return 1
}

# Generate a summary of the previous iteration
# Usage: generate_iteration_summary "$log_file"
generate_iteration_summary() {
    local log_file="$1"

    [[ ! -f "$log_file" ]] && return 0

    local summary=""

    # Extract key information from the log (handles **MARKER:** and MARKER: formats)
    local completed
    completed=$(grep -oE "(\*\*)?COMPLETED:(\*\*)? .+" "$log_file" 2>/dev/null | head -1 | sed -E 's/^\*{0,2}COMPLETED:\*{0,2} *//' || echo "")

    local files
    files=$(grep -oE "(\*\*)?FILES:(\*\*)? .+" "$log_file" 2>/dev/null | head -1 | sed -E 's/^\*{0,2}FILES:\*{0,2} *//' || echo "")

    local learning
    learning=$(grep -oE "(\*\*)?LEARNING:(\*\*)? .+" "$log_file" 2>/dev/null | head -1 | sed -E 's/^\*{0,2}LEARNING:\*{0,2} *//' || echo "")

    local fixed
    fixed=$(grep -oE "(\*\*)?FIXED:(\*\*)? .+" "$log_file" 2>/dev/null | head -1 | sed -E 's/^\*{0,2}FIXED:\*{0,2} *//' || echo "")

    local blocker
    blocker=$(grep -oE "(\*\*)?BLOCKER:(\*\*)? .+" "$log_file" 2>/dev/null | head -1 | sed -E 's/^\*{0,2}BLOCKER:\*{0,2} *//' || echo "")

    # Check iteration outcome
    local outcome="unknown"
    if grep -q "All checks passed" "$log_file" 2>/dev/null; then
        outcome="success"
    elif grep -q "Failed:" "$log_file" 2>/dev/null; then
        outcome="had_issues"
    fi

    # Build summary
    if [[ -n "$completed" ]] || [[ -n "$files" ]] || [[ -n "$learning" ]] || [[ -n "$fixed" ]] || [[ -n "$blocker" ]]; then
        summary="PREVIOUS ITERATION SUMMARY:
"
        [[ -n "$completed" ]] && summary+="- COMPLETED: $completed
"
        [[ -n "$files" ]] && summary+="- FILES: $files
"
        [[ -n "$learning" ]] && summary+="- LEARNING: $learning
"
        [[ -n "$fixed" ]] && summary+="- FIXED: $fixed
"
        [[ -n "$blocker" ]] && summary+="- BLOCKER: $blocker
"
        [[ "$outcome" == "had_issues" ]] && summary+="- Outcome: Had issues that need fixing
"
        [[ "$outcome" == "success" ]] && summary+="- Outcome: Checks passed
"
    fi

    echo "$summary"
}

# Find similar fixes in learnings.json
# Usage: find_similar_fixes_in_learnings "$error_message"
find_similar_fixes_in_learnings() {
    local error="$1"
    local learnings_file=".cr/learnings.json"

    [[ ! -f "$learnings_file" ]] && return 0
    [[ -z "$error" ]] && return 0

    # Extract key terms from error
    local key_terms
    key_terms=$(echo "$error" | tr -cs '[:alnum:]' '\n' | grep -v '^$' | head -5 | tr '\n' '|' | sed 's/|$//')

    [[ -z "$key_terms" ]] && return 0

    local matches=""
    if command -v jq &>/dev/null; then
        matches=$(jq -r ".learnings | map(select(.category == \"fix\" and (.learning | test(\"(?i)($key_terms)\")))) | .[-5:] | .[] | \"- \" + .learning" "$learnings_file" 2>/dev/null || echo "")
    fi

    if [[ -n "$matches" ]]; then
        echo "$matches"
    fi
}

# Refresh PROMPT.md with updated context
# Call this at the start of each iteration to inject fresh accumulated context
# Usage: refresh_prompt_context "$spec_dir"
refresh_prompt_context() {
    local spec_dir="$1"
    local prompt_file="$spec_dir/PROMPT.md"

    [[ ! -f "$prompt_file" ]] && return 0

    # Check if the file has context markers
    if ! grep -q "<!-- CONTEXT_START -->" "$prompt_file" 2>/dev/null; then
        return 0  # No markers, nothing to refresh
    fi

    # Get fresh accumulated context
    local accumulated_ctx
    accumulated_ctx=$(get_context_for_prompt 2>/dev/null || echo "No accumulated context yet.")

    # Create backup
    cp "$prompt_file" "$prompt_file.bak"

    # Write context to temp file (awk -v breaks with multi-line strings)
    local ctx_temp
    ctx_temp=$(mktemp)
    printf '%s\n' "$accumulated_ctx" > "$ctx_temp"

    # Use awk to replace content between markers
    awk -v ctxfile="$ctx_temp" '
        BEGIN {
            while ((getline line < ctxfile) > 0) {
                ctx = ctx (ctx ? "\n" : "") line
            }
            close(ctxfile)
        }
        /<!-- CONTEXT_START -->/ {
            print
            print ctx
            skip = 1
            next
        }
        /<!-- CONTEXT_END -->/ {
            skip = 0
            print
            next
        }
        !skip {
            print
        }
    ' "$prompt_file.bak" > "$prompt_file"

    rm -f "$ctx_temp"
    log_info "Refreshed context in PROMPT.md"
    return 0
}

#=============================================================================
# SELF-HEALING (Automatic retry with error context)
#=============================================================================

MAX_SELF_HEAL_ATTEMPTS="${MAX_SELF_HEAL_ATTEMPTS:-3}"

# Check if an error is unfixable (requires human intervention)
is_unfixable_error() {
    local error="$1"

    # These errors require human intervention
    local unfixable_patterns=(
        "API key"
        "api key"
        "authentication failed"
        "Authentication failed"
        "permission denied"
        "Permission denied"
        "disk full"
        "out of memory"
        "rate limit exceeded"
        "Rate limit"
        "SIGKILL"
        "ENOMEM"
        "ENOSPC"
        "Unable to connect to Claude"
        "network error"
        "Network error"
    )

    for pattern in "${unfixable_patterns[@]}"; do
        if [[ "$error" == *"$pattern"* ]]; then
            return 0  # Is unfixable
        fi
    done

    return 1  # Is fixable (or at least worth trying)
}

# Add error context to prompt for self-healing
add_error_to_prompt() {
    local spec_dir="$1"
    local error="$2"
    local prompt_file="$spec_dir/PROMPT.md"

    # Truncate error if too long (keep first 2000 chars)
    if [[ ${#error} -gt 2000 ]]; then
        error="${error:0:2000}... [truncated]"
    fi

    # Append error context to prompt (heredoc handles the content safely)
    cat >> "$prompt_file" << EOF

---

## SELF-HEALING CONTEXT

The previous iteration failed with this error:

\`\`\`
$error
\`\`\`

Please:
1. Analyze what went wrong
2. Fix the issue (check for typos, missing imports, incorrect paths)
3. Re-run validation to confirm the fix
4. Continue with the current task

**Do NOT** output \`<loop-complete>\` until the issue is actually fixed.

EOF

    log_info "Added self-healing context to prompt"
}

# Record a blocked iteration
record_blocked_iteration() {
    local spec_dir="$1"
    local error="$2"
    local spec_file="$spec_dir/SPEC.md"

    log_error "Iteration blocked due to unfixable error"

    # Add blocked note to SPEC.md
    {
        echo ""
        echo "### Blocked (Auto-added $(date -Iseconds))"
        echo "Error: ${error:0:500}"
        echo ""
    } >> "$spec_file"

    # Record as learning
    add_learning "iteration_failure" "Blocked: ${error:0:200}" "" "$(basename "$spec_dir")" ""
}

#=============================================================================
# UNIVERSAL QUALITY GATES (Stack-agnostic quality checks)
#=============================================================================

# Discover quality commands for any supported stack
# Returns commands one per line
discover_quality_commands() {
    local project_type="${1:-}"
    local quality_commands=()

    # Auto-detect project type if not provided
    if [[ -z "$project_type" ]]; then
        project_type=$(detect_project_type)
    fi

    case "$project_type" in
        bun)
            # Bun-specific checks
            if [[ -f "package.json" ]]; then
                [[ -n "$(jq -r '.scripts.test // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("bun test --run")
                [[ -n "$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("bun run lint")
                [[ -n "$(jq -r '.scripts.typecheck // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("bun run typecheck")
                # Fallback to tsc if no typecheck script but tsconfig exists
                # Note: Framework-specific checks (Astro, Next, etc.) should be in SPEC.md Quality Gates
                # They are discovered by the LLM during cr spec, not hardcoded here
                if [[ -z "$(jq -r '.scripts.typecheck // empty' package.json 2>/dev/null)" ]] && [[ -f "tsconfig.json" ]]; then
                    quality_commands+=("bunx tsc --noEmit")
                fi
            fi
            ;;

        npm|yarn|pnpm)
            local runner="npm run"
            [[ "$project_type" == "yarn" ]] && runner="yarn"
            [[ "$project_type" == "pnpm" ]] && runner="pnpm run"

            if [[ -f "package.json" ]]; then
                [[ -n "$(jq -r '.scripts.test // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("CI=true $runner test")
                [[ -n "$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("$runner lint")
                [[ -n "$(jq -r '.scripts.typecheck // empty' package.json 2>/dev/null)" ]] && \
                    quality_commands+=("$runner typecheck")
                # Fallback to tsc if no typecheck script but tsconfig exists
                if [[ -z "$(jq -r '.scripts.typecheck // empty' package.json 2>/dev/null)" ]] && [[ -f "tsconfig.json" ]]; then
                    quality_commands+=("npx tsc --noEmit")
                fi
            fi
            ;;

        rails)
            # Rails/Ruby checks
            [[ -f "bin/rails" ]] && quality_commands+=("bin/rails test")
            [[ -f ".rubocop.yml" ]] && quality_commands+=("bundle exec rubocop --parallel")
            # Security scan if brakeman is available
            if [[ -f "Gemfile" ]] && grep -q "brakeman" Gemfile 2>/dev/null; then
                quality_commands+=("bundle exec brakeman -q --no-pager")
            fi
            # Bundle audit for security
            if [[ -f "Gemfile" ]] && grep -q "bundler-audit" Gemfile 2>/dev/null; then
                quality_commands+=("bundle exec bundle-audit check --update")
            fi
            ;;

        python)
            # Python checks
            if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]] || [[ -d "tests" ]]; then
                quality_commands+=("pytest")
            fi
            # Ruff for linting (fast, modern)
            if [[ -f "pyproject.toml" ]] && grep -q "ruff" pyproject.toml 2>/dev/null; then
                quality_commands+=("ruff check .")
            elif [[ -f "ruff.toml" ]]; then
                quality_commands+=("ruff check .")
            fi
            # Type checking with mypy or pyright
            if [[ -f "pyproject.toml" ]] && grep -q "mypy" pyproject.toml 2>/dev/null; then
                quality_commands+=("mypy .")
            elif [[ -f "mypy.ini" ]]; then
                quality_commands+=("mypy .")
            fi
            # Security with bandit
            if command -v bandit &>/dev/null; then
                quality_commands+=("bandit -r . -q")
            fi
            ;;

        go)
            # Go checks
            quality_commands+=("go test ./...")
            quality_commands+=("go vet ./...")
            # golangci-lint for comprehensive linting
            if command -v golangci-lint &>/dev/null; then
                quality_commands+=("golangci-lint run")
            fi
            # Security with gosec
            if command -v gosec &>/dev/null; then
                quality_commands+=("gosec -quiet ./...")
            fi
            ;;

        rust)
            # Rust checks
            quality_commands+=("cargo test")
            quality_commands+=("cargo clippy -- -D warnings")
            # Security audit
            if command -v cargo-audit &>/dev/null; then
                quality_commands+=("cargo audit")
            fi
            ;;

        *)
            # Unknown project type - try common commands
            # || true prevents failure when npm test script doesn't exist
            if [[ -f "package.json" ]]; then
                quality_commands+=("npm test 2>/dev/null || true")
            fi
            ;;
    esac

    # Output commands one per line
    printf '%s\n' "${quality_commands[@]}"
}

# Run all quality gates for the project
# Returns 0 if all pass, 1 if any fail
run_quality_gates() {
    local project_type="${1:-}"
    local failed=0
    local gate_output=""

    # Auto-detect project type if not provided
    if [[ -z "$project_type" ]]; then
        project_type=$(detect_project_type)
    fi

    log_step "Running Quality Gates ($project_type)"

    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue

        log_info "Gate: $cmd"

        # Validate command before execution
        if ! validate_command "$cmd"; then
            log_error "Gate REJECTED (unsafe command): $cmd"
            failed=1
            continue
        fi

        # Run command and capture output
        set +e
        gate_output=$(bash -c "$cmd" 2>&1)
        local exit_code=$?
        set -e

        if [[ $exit_code -ne 0 ]]; then
            log_error "Gate FAILED: $cmd"
            echo "$gate_output" | tail -20
            failed=1
        else
            log_success "Gate passed: $cmd"
        fi
    done < <(discover_quality_commands "$project_type")

    if [[ $failed -eq 0 ]]; then
        log_success "All quality gates passed"
    else
        log_error "Some quality gates failed"
    fi

    return $failed
}

#=============================================================================
# INTEGRATION VERIFICATION
#=============================================================================

# Verify integration - ensure everything actually works
# Discovery-based: reads commands from .cr/project.json
# Returns 0 if all checks pass, 1 if any fail
verify_integration() {
    INTEGRATION_FAILURES=()
    local all_passed=true

    log_step "Verifying Integration"

    # Ensure project is discovered
    if [[ ! -f ".cr/project.json" ]]; then
        log_info "Discovering project configuration..."
        discover_project
    fi

    # 1. Start Docker services if docker-compose exists
    if [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log_info "Starting Docker services..."
        if docker compose up -d 2>/dev/null; then
            # Wait for services to be ready
            local waited=0
            local docker_ready=false
            while [[ $waited -lt 30 ]]; do
                if docker compose ps 2>/dev/null | grep -qiE "up|running|healthy"; then
                    docker_ready=true
                    break
                fi
                sleep 1
                waited=$((waited + 1))
            done
            if [[ "$docker_ready" == "true" ]]; then
                log_info "Docker services running"
            else
                log_warn "Docker services may not be fully healthy (waited ${waited}s)"
            fi
        else
            INTEGRATION_FAILURES+=("Docker compose failed to start")
            all_passed=false
        fi
    fi

    # 2. Copy .env if needed
    if [[ -f ".env.example" ]] && [[ ! -f ".env" ]]; then
        log_info "Copying .env.example to .env..."
        cp .env.example .env
    fi

    # 3. Run database migrations using discovered command
    local db_cmd
    db_cmd=$(get_project_config "commands.db")
    if [[ -n "$db_cmd" ]]; then
        log_info "Running database setup: $db_cmd"
        if ! validate_command "$db_cmd"; then
            INTEGRATION_FAILURES+=("Database setup rejected (unsafe command): $db_cmd")
            all_passed=false
        elif ! bash -c "$db_cmd" 2>/dev/null; then
            INTEGRATION_FAILURES+=("Database setup failed: $db_cmd")
            all_passed=false
        fi
    fi

    # 4. Run tests - SPEC-DRIVEN: use SPEC.md quality gates if available
    local tests_run=0

    # Try SPEC-driven test commands first
    if [[ -n "${CURRENT_SPEC_DIR:-}" ]] && [[ -f "${CURRENT_SPEC_DIR}/SPEC.md" ]]; then
        local spec_file="${CURRENT_SPEC_DIR}/SPEC.md"
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            # Skip non-test commands (build, screenshot, etc.)
            [[ "$cmd" == *"build"* ]] && continue
            [[ "$cmd" == *"screenshot"* ]] && continue
            [[ "$cmd" == *"agent-browser"* ]] && continue

            log_info "Running SPEC test: $cmd"
            if ! validate_command "$cmd"; then
                INTEGRATION_FAILURES+=("Tests rejected (unsafe command): $cmd")
                all_passed=false
                continue
            fi
            tests_run=$((tests_run + 1))
            if ! bash -c "CI=true $cmd" 2>&1 | tail -20; then
                INTEGRATION_FAILURES+=("Tests failed: $cmd")
                all_passed=false
            fi
        done < <(get_spec_quality_commands "$spec_file")
    fi

    # Fallback to project.json test command if no SPEC tests
    if [[ $tests_run -eq 0 ]]; then
        local test_cmd
        test_cmd=$(get_project_config "commands.test")
        if [[ -n "$test_cmd" ]]; then
            log_info "Running tests: $test_cmd"
            if ! validate_command "$test_cmd"; then
                INTEGRATION_FAILURES+=("Tests rejected (unsafe command): $test_cmd")
                all_passed=false
            elif ! bash -c "CI=true $test_cmd" 2>/dev/null; then
                INTEGRATION_FAILURES+=("Tests failed: $test_cmd")
                all_passed=false
            fi
        else
            log_warn "No test command discovered"
        fi
    fi

    # 5. Run e2e tests if discovered
    local test_e2e_cmd
    test_e2e_cmd=$(get_project_config "commands.test_e2e")
    local e2e_dir
    e2e_dir=$(get_project_config "paths.e2e_dir")

    if [[ -n "$test_e2e_cmd" ]] && [[ -n "$e2e_dir" ]]; then
        log_info "Running e2e tests: $test_e2e_cmd"

        # Run e2e tests and capture output (use script for proper tty on macOS)
        local e2e_output
        local e2e_exit_code=0

        # Create temp file for output
        local e2e_temp
        e2e_temp=$(mktemp)

        # Validate e2e command before execution
        if ! validate_command "$test_e2e_cmd"; then
            INTEGRATION_FAILURES+=("E2E tests rejected (unsafe command): $test_e2e_cmd")
            all_passed=false
            rm -f "$e2e_temp"
        else
            # Run with CI=true to disable interactive features
            bash -c "CI=true $test_e2e_cmd" > "$e2e_temp" 2>&1 || e2e_exit_code=$?

            e2e_output=$(cat "$e2e_temp")
            rm -f "$e2e_temp"

            # Strip ANSI escape codes for reliable pattern matching
            local e2e_clean
            e2e_clean=$(echo "$e2e_output" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9]*[A-Za-z]//g')

            # Show summary of e2e results
            local passed_line failed_line
            passed_line=$(echo "$e2e_clean" | grep -oE "[0-9]+ passed" | head -1 || true)
            failed_line=$(echo "$e2e_clean" | grep -oE "[0-9]+ failed" | head -1 || true)

            if [[ -n "$passed_line" ]] || [[ -n "$failed_line" ]]; then
                log_info "E2E results: ${passed_line:-0 passed}, ${failed_line:-0 failed}"
            fi

            # Check for port conflict (dev server already running)
            if echo "$e2e_clean" | grep -q "already used\|reuseExistingServer"; then
                log_warn "E2E skipped: dev server already running (set reuseExistingServer:true in playwright.config)"
                # Don't fail - this is a config issue, not a test failure
            # Check if ANY tests passed (some browsers may not be installed)
            elif [[ -n "$passed_line" ]]; then
                local passed_count
                passed_count=$(echo "$passed_line" | grep -oE "[0-9]+")
                if [[ $passed_count -gt 0 ]]; then
                    log_info "E2E tests: $passed_count passed (some browsers may have failed - OK)"
                else
                    INTEGRATION_FAILURES+=("E2E tests failed - 0 tests passed")
                    all_passed=false
                fi
            else
                # No "passed" found - show what we got for debugging
                log_warn "E2E output (last 5 lines):"
                echo "$e2e_clean" | tail -5
                INTEGRATION_FAILURES+=("E2E tests failed - no tests passed")
                all_passed=false
            fi
        fi
    fi

    # 6. Check if build works using discovered command
    local build_cmd
    build_cmd=$(get_project_config "commands.build")
    if [[ -n "$build_cmd" ]]; then
        log_info "Verifying build: $build_cmd"
        if ! validate_command "$build_cmd"; then
            INTEGRATION_FAILURES+=("Build rejected (unsafe command): $build_cmd")
            all_passed=false
        elif ! bash -c "$build_cmd" 2>/dev/null; then
            INTEGRATION_FAILURES+=("Build failed: $build_cmd")
            all_passed=false
        fi
    fi

    # 7. Verify dev server if API endpoints exist
    if [[ -d "src/pages/api" ]] || [[ -d "pages/api" ]] || [[ -d "app/api" ]] || [[ -d "app/controllers" ]]; then
        log_info "Checking API availability..."
        local dev_url
        dev_url=$(detect_dev_server 2>/dev/null || true)
        if [[ -n "$dev_url" ]]; then
            if curl -sf "$dev_url" > /dev/null 2>&1; then
                log_info "Dev server responding at $dev_url"
            else
                log_warn "Dev server not responding at $dev_url (may need manual start)"
            fi
        fi
    fi

    # Report results
    echo ""
    if [[ "$all_passed" == "true" ]]; then
        log_success "All integration checks passed!"
        return 0
    else
        log_error "Integration verification failed:"
        for failure in "${INTEGRATION_FAILURES[@]}"; do
            echo "  - $failure"
        done
        return 1
    fi
}

# Find the current/active spec directory
# Priority: 1) building status, 2) most recently modified, 3) pending
# Returns empty string if no spec found
find_active_spec() {
    local spec_dir=""

    # First, look for a spec with "building" status
    spec_dir=$(find "$SPECS_DIR" -name "SPEC.md" -exec grep -l "^status: building" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
    if [[ -n "$spec_dir" ]]; then
        echo "$spec_dir"
        return 0
    fi

    # Next, look for most recently modified SPEC.md that's not complete
    spec_dir=$(find "$SPECS_DIR" -name "SPEC.md" -newer "$SPECS_DIR" 2>/dev/null | while read -r f; do
        if ! grep -q "^status: complete" "$f" 2>/dev/null; then
            dirname "$f"
            break
        fi
    done)
    if [[ -n "$spec_dir" ]]; then
        echo "$spec_dir"
        return 0
    fi

    # Finally, any pending spec
    spec_dir=$(find "$SPECS_DIR" -name "SPEC.md" -exec grep -l "^status: pending" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
    if [[ -n "$spec_dir" ]]; then
        echo "$spec_dir"
        return 0
    fi

    return 1
}

# Find spec that needs fixing (has todos but no fix spec yet)
find_spec_needing_fixes() {
    local review_type="${1:-}"  # code, design, or empty for any

    for spec_dir in "$SPECS_DIR"/*/; do
        [[ -d "$spec_dir" ]] || continue

        # Skip fix specs themselves
        [[ "$spec_dir" == *"/fixes/"* ]] && continue

        local todos_dir="$spec_dir/todos"

        if [[ -n "$review_type" ]]; then
            todos_dir="$spec_dir/todos/$review_type"
        fi

        # Check if todos exist
        if [[ -d "$todos_dir" ]] && [[ -n "$(find "$todos_dir" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
            # Check if fix spec doesn't exist yet
            local fix_dir="$spec_dir/fixes"
            if [[ -n "$review_type" ]]; then
                fix_dir="$spec_dir/fixes/$review_type"
            fi

            if [[ ! -f "$fix_dir/SPEC.md" ]]; then
                echo "${spec_dir%/}"
                return 0
            fi
        fi
    done

    return 1
}

# Get absolute path for a spec directory
get_abs_spec_dir() {
    local spec_dir="$1"
    if [[ -d "$spec_dir" ]]; then
        cd "$spec_dir" && pwd
    else
        echo ""
    fi
}

generate_agents_md() {
    local project_type="$1"
    local output_file="$2"
    local project_dir
    project_dir=$(dirname "$output_file")

    cat > "$output_file" << 'HEADER'
# AGENTS.md - Operational Guide

This file contains build, test, and validation commands for this project.
Updated automatically and manually with learnings during implementation.

Keep this file under 60 lines. Status updates belong in SPEC.md.

HEADER

    case "$project_type" in
        bun)
            # Build section
            echo "## Build" >> "$output_file"
            echo '```bash' >> "$output_file"
            echo "bun install" >> "$output_file"
            has_script "build" "$project_dir/package.json" && echo "bun run build" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Test section
            echo "## Test" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "test" "$project_dir/package.json" && echo "bun test" >> "$output_file"
            has_script "test" "$project_dir/package.json" && echo "bun test --coverage" >> "$output_file"
            # If no test script, suggest default
            has_script "test" "$project_dir/package.json" || echo "# Add test script to package.json" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Lint & Type Check section
            echo "## Lint & Type Check" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "lint" "$project_dir/package.json" && echo "bun run lint" >> "$output_file"
            has_script "lint" "$project_dir/package.json" && echo "bun run lint --fix" >> "$output_file"
            has_script "typecheck" "$project_dir/package.json" && echo "bun run typecheck" >> "$output_file"
            # Fallback to tsc if no typecheck script but tsconfig exists
            if ! has_script "typecheck" "$project_dir/package.json" && [[ -f "$project_dir/tsconfig.json" ]]; then
                echo "bunx tsc --noEmit" >> "$output_file"
            fi
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Development section
            echo "## Development" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "dev" "$project_dir/package.json" && echo "bun run dev" >> "$output_file"
            has_script "dev" "$project_dir/package.json" || echo "# Add dev script to package.json" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            echo "## Learnings" >> "$output_file"
            echo "<!-- Add project-specific learnings here as you discover them -->" >> "$output_file"
            echo "" >> "$output_file"
            ;;
        npm|yarn|pnpm)
            local pm="$project_type"
            local run_cmd="$pm run"
            [[ "$pm" == "npm" ]] && run_cmd="npm run"

            # Build section
            echo "## Build" >> "$output_file"
            echo '```bash' >> "$output_file"
            echo "$pm install" >> "$output_file"
            has_script "build" "$project_dir/package.json" && echo "$run_cmd build" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Test section
            echo "## Test" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "test" "$project_dir/package.json" && echo "$run_cmd test" >> "$output_file"
            has_script "test" "$project_dir/package.json" && echo "$run_cmd test -- --coverage" >> "$output_file"
            has_script "test" "$project_dir/package.json" || echo "# Add test script to package.json" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Lint & Type Check section
            echo "## Lint & Type Check" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "lint" "$project_dir/package.json" && echo "$run_cmd lint" >> "$output_file"
            has_script "lint" "$project_dir/package.json" && echo "$run_cmd lint --fix" >> "$output_file"
            has_script "typecheck" "$project_dir/package.json" && echo "$run_cmd typecheck" >> "$output_file"
            # Fallback to tsc if no typecheck script but tsconfig exists
            if ! has_script "typecheck" "$project_dir/package.json" && [[ -f "$project_dir/tsconfig.json" ]]; then
                echo "npx tsc --noEmit" >> "$output_file"
            fi
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            # Development section
            echo "## Development" >> "$output_file"
            echo '```bash' >> "$output_file"
            has_script "dev" "$project_dir/package.json" && echo "$run_cmd dev" >> "$output_file"
            has_script "dev" "$project_dir/package.json" || echo "# Add dev script to package.json" >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"

            echo "## Learnings" >> "$output_file"
            echo "<!-- Add project-specific learnings here as you discover them -->" >> "$output_file"
            echo "" >> "$output_file"
            ;;
        rails)
            cat >> "$output_file" << 'RAILS'
## Build
```bash
bundle install
bin/rails db:prepare
```

## Test
```bash
bin/rails test
bin/rails test:system
bundle exec rspec
```

## Lint & Type Check
```bash
bundle exec rubocop
bundle exec rubocop -A
bin/srb tc
```

## Security
```bash
bundle exec brakeman -q
```

## Development
```bash
bin/dev
```

## Learnings
<!-- Add project-specific learnings here as you discover them -->

RAILS
            ;;
        python)
            cat >> "$output_file" << 'PYTHON'
## Build
```bash
pip install -e .
# or: poetry install / uv sync
```

## Test
```bash
pytest
pytest --cov
```

## Lint & Type Check
```bash
ruff check .
ruff check . --fix
mypy .
```

## Development
```bash
python -m app
# or: uvicorn app:app --reload
```

## Learnings
<!-- Add project-specific learnings here as you discover them -->

PYTHON
            ;;
        *)
            cat >> "$output_file" << 'UNKNOWN'
## Build
```bash
# Add your build command
```

## Test
```bash
# Add your test command
```

## Lint
```bash
# Add your lint command
```

## Learnings
<!-- Add project-specific learnings here as you discover them -->

UNKNOWN
            ;;
    esac
}

#=============================================================================
# INIT COMMAND
#=============================================================================

cmd_init() {
    local project_path="${1:-.}"
    project_path="$(cd "$project_path" && pwd)"

    log_step "Initializing Compound Ralph in $project_path"

    # Detect project type
    local project_type
    project_type=$(detect_project_type "$project_path")
    log_info "Detected project type: $project_type"

    # Create directories
    mkdir -p "$project_path/$SPECS_DIR"
    mkdir -p "$project_path/$PLANS_DIR"
    mkdir -p "$project_path/knowledge/decisions"
    mkdir -p "$project_path/knowledge/research"
    log_success "Created specs/, plans/, and knowledge/ directories"

    # Generate AGENTS.md if it doesn't exist
    if [[ ! -f "$project_path/AGENTS.md" ]]; then
        generate_agents_md "$project_type" "$project_path/AGENTS.md"
        log_success "Created AGENTS.md with $project_type commands"
    else
        log_warn "AGENTS.md already exists, skipping"
    fi

    # Copy templates
    if [[ -d "$CR_DIR/templates" ]]; then
        cp -n "$CR_DIR/templates/SPEC-template.md" "$project_path/$SPECS_DIR/" 2>/dev/null || true
        log_success "Copied SPEC template to specs/"
    fi

    # Discover project configuration
    (cd "$project_path" && discover_project)
    log_success "Discovered project configuration"

    # Create .gitignore additions if needed
    if [[ -f "$project_path/.gitignore" ]]; then
        if ! grep -q "specs/.history" "$project_path/.gitignore" 2>/dev/null; then
            echo -e "\n# Compound Ralph iteration logs\nspecs/.history/" >> "$project_path/.gitignore"
            log_success "Added specs/.history/ to .gitignore"
        fi
    fi

    echo ""
    log_success "Compound Ralph initialized!"
    echo ""
    echo "Next steps:"
    echo "  1. Review and customize AGENTS.md with your project's commands"
    echo "  2. (Optional) Explore ideas: cr converse \"your topic\""
    echo "  3. (Optional) Research:      cr research \"your topic\""
    echo "  4. Create a plan:            cr plan \"your feature description\""
    echo "  5. Convert to spec:          cr spec plans/your-feature.md"
    echo "  6. Implement:                cr implement specs/your-feature/"
    echo ""
}


#=============================================================================
# CONVERSE COMMAND (Pre-planning: Socratic dialogue)
#=============================================================================

cmd_converse() {
    local topic="$*"

    if [[ -z "$topic" ]]; then
        log_error "Usage: cr converse <topic>"
        log_error "Example: cr converse \"user authentication approach\""
        exit 1
    fi

    log_step "Starting Conversation: $topic"

    # Ensure knowledge directories exist
    mkdir -p "knowledge/decisions"

    # Generate decision filename
    local topic_slug
    topic_slug=$(echo "$topic" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-50)
    # Fallback if slug is empty (e.g. non-ASCII topic)
    if [[ -z "$topic_slug" ]]; then
        topic_slug="untitled-$(date '+%s' | tail -c 7)"
    fi
    local decision_file="knowledge/decisions/$(date '+%Y-%m-%d')-${topic_slug}.md"

    # Gather existing context
    local existing_decisions=""
    if [[ -d "knowledge/decisions" ]] && [[ -n "$(find knowledge/decisions -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        existing_decisions="$(printf '\n## Existing Decision Records\nReview these for relevant context:\n')$(find knowledge/decisions -maxdepth 1 -name '*.md' 2>/dev/null | while read -r f; do echo "- $f: $(head -1 "$f" | sed 's/^# //')"; done)"
    fi

    local existing_research=""
    if [[ -d "knowledge/research" ]] && [[ -n "$(find knowledge/research -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        existing_research="$(printf '\n## Existing Research\nThese reports may be relevant:\n')$(find knowledge/research -maxdepth 1 -name '*.md' 2>/dev/null | while read -r f; do echo "- $f: $(head -1 "$f" | sed 's/^# //')"; done)"
    fi

    local vision_context=""
    if [[ -f "specs/VISION.md" ]]; then
        vision_context=$'\nRead specs/VISION.md for product context.'
    fi

    local claude_md_context=""
    if [[ -f "CLAUDE.md" ]]; then
        claude_md_context=$'\nRead CLAUDE.md for project conventions.'
    fi

    echo ""
    echo -e "${CYAN}Starting exploratory conversation about: $topic${NC}"
    echo ""
    echo "This is a Socratic dialogue to surface assumptions and explore trade-offs"
    echo "BEFORE committing to any plan or implementation."
    echo ""
    echo "The conversation will:"
    echo "  1. Understand the core problem"
    echo "  2. Surface and examine assumptions"
    echo "  3. Explore 2-3 alternative approaches"
    echo "  4. Discuss trade-offs of each"
    echo "  5. Reach a decision (or identify what research is needed)"
    echo ""
    echo -e "Decision record will be saved to: ${BOLD}$decision_file${NC}"
    echo ""
    echo -e "${YELLOW}Starting Claude...${NC}"
    echo ""

    local converse_prompt
    converse_prompt=$(load_prompt "converse.txt")
    converse_prompt="${converse_prompt//__TOPIC__/$topic}"
    converse_prompt="${converse_prompt//__VISION_CONTEXT__/$vision_context}"
    converse_prompt="${converse_prompt//__CLAUDE_MD_CONTEXT__/$claude_md_context}"
    converse_prompt="${converse_prompt//__EXISTING_DECISIONS__/$existing_decisions}"
    converse_prompt="${converse_prompt//__EXISTING_RESEARCH__/$existing_research}"
    converse_prompt="${converse_prompt//__DECISION_FILE__/$decision_file}"
    converse_prompt="${converse_prompt//__DATE__/$(date '+%Y-%m-%d')}"
    validate_prompt "$converse_prompt" "converse"

    # Run Claude interactively
    claude --dangerously-skip-permissions "$converse_prompt"

    echo ""
    log_success "Conversation complete!"
    echo ""

    # Check if decision record was created
    if [[ -f "$decision_file" ]]; then
        log_success "Decision record saved to: $decision_file"
    else
        local latest_decision
        latest_decision=$(ls -t knowledge/decisions/*.md 2>/dev/null | head -1)
        if [[ -n "$latest_decision" ]]; then
            log_success "Decision record saved to: $latest_decision"
        else
            log_warn "No decision record was created. You can create one manually."
        fi
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Review the decision: cat $decision_file"
    echo "  2. If more info needed: cr research \"<specific-topic>\""
    echo "  3. If ready to build:   cr plan \"<feature-description>\""
    echo ""
}

#=============================================================================
# RESEARCH COMMAND (Pre-planning: Deep investigation)
#=============================================================================

cmd_research() {
    local topic="$*"

    if [[ -z "$topic" ]]; then
        log_error "Usage: cr research <topic>"
        log_error "Example: cr research \"oauth implementation best practices\""
        exit 1
    fi

    log_step "Starting Research: $topic"

    # Ensure knowledge directories exist
    mkdir -p "knowledge/research"

    # Generate report filename
    local topic_slug
    topic_slug=$(echo "$topic" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-50)
    # Fallback if slug is empty (e.g. non-ASCII topic)
    if [[ -z "$topic_slug" ]]; then
        topic_slug="untitled-$(date '+%s' | tail -c 7)"
    fi
    local report_file="knowledge/research/$(date '+%Y-%m-%d')-${topic_slug}.md"

    # Gather existing context
    local existing_decisions=""
    if [[ -d "knowledge/decisions" ]] && [[ -n "$(find knowledge/decisions -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        existing_decisions="$(printf '\n## Relevant Decision Records\nThese decisions may inform your research:\n')$(find knowledge/decisions -maxdepth 1 -name '*.md' 2>/dev/null | while read -r f; do echo "- $f"; done)"
    fi

    local existing_research=""
    if [[ -d "knowledge/research" ]] && [[ -n "$(find knowledge/research -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        existing_research="$(printf '\n## Existing Research Reports\nBuild on or reference these:\n')$(find knowledge/research -maxdepth 1 -name '*.md' 2>/dev/null | while read -r f; do echo "- $f: $(head -1 "$f" | sed 's/^# //')"; done)"
    fi

    local vision_context=""
    if [[ -f "specs/VISION.md" ]]; then
        vision_context=$'\nRead specs/VISION.md for product direction and priorities.'
    fi

    local claude_md_context=""
    if [[ -f "CLAUDE.md" ]]; then
        claude_md_context=$'\nRead CLAUDE.md for project conventions and existing patterns.'
    fi

    echo ""
    echo -e "${CYAN}Starting deep research on: $topic${NC}"
    echo ""
    echo "This is a thorough investigation to understand before building."
    echo ""
    echo "The research will cover:"
    echo "  1. Codebase analysis - existing patterns and dependencies"
    echo "  2. External research - best practices and common pitfalls"
    echo "  3. Feasibility assessment - complexity, risks, prerequisites"
    echo ""
    echo -e "Research report will be saved to: ${BOLD}$report_file${NC}"
    echo ""
    echo -e "${YELLOW}Starting Claude...${NC}"
    echo ""

    local research_prompt
    research_prompt=$(load_prompt "research.txt")
    research_prompt="${research_prompt//__TOPIC__/$topic}"
    research_prompt="${research_prompt//__VISION_CONTEXT__/$vision_context}"
    research_prompt="${research_prompt//__CLAUDE_MD_CONTEXT__/$claude_md_context}"
    research_prompt="${research_prompt//__EXISTING_DECISIONS__/$existing_decisions}"
    research_prompt="${research_prompt//__EXISTING_RESEARCH__/$existing_research}"
    research_prompt="${research_prompt//__REPORT_FILE__/$report_file}"
    validate_prompt "$research_prompt" "research"

    # Run Claude interactively
    claude --dangerously-skip-permissions "$research_prompt"

    echo ""
    log_success "Research complete!"
    echo ""

    # Check if report was created
    if [[ -f "$report_file" ]]; then
        log_success "Research report saved to: $report_file"
    else
        local latest_report
        latest_report=$(ls -t knowledge/research/*.md 2>/dev/null | head -1)
        if [[ -n "$latest_report" ]]; then
            log_success "Research report saved to: $latest_report"
        else
            log_warn "No research report was created. You can create one manually."
        fi
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Review the report: cat $report_file"
    echo "  2. If ready to build: cr plan \"<feature-description>\""
    echo "  3. If need to discuss: cr converse \"<topic>\""
    echo ""
}

#=============================================================================
# PLAN COMMAND
#=============================================================================

cmd_plan() {
    local description="$*"

    if [[ -z "$description" ]]; then
        log_error "Usage: cr plan <feature-description>"
        exit 1
    fi

    log_step "Creating Plan: $description"

    # Ensure plans directory exists
    mkdir -p "$PLANS_DIR"

    # Generate plan filename
    local plan_name
    plan_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-50)
    # Fallback if slug is empty (e.g. non-ASCII description)
    if [[ -z "$plan_name" ]]; then
        plan_name="untitled-$(date '+%s' | tail -c 7)"
    fi
    local plan_file="$PLANS_DIR/${plan_name}.md"

    # Gather knowledge context from converse/research phases
    local knowledge_context=""
    local knowledge_files_found=false

    if [[ -d "knowledge/decisions" ]] && [[ -n "$(find knowledge/decisions -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        knowledge_context+="

IMPORTANT: Decision records from prior conversations exist in knowledge/decisions/.
Read ALL of these before planning - they contain assumptions, trade-offs, and
decisions that MUST inform your plan:"
        while IFS= read -r f; do
            knowledge_context+="
  - $f"
        done < <(find knowledge/decisions -maxdepth 1 -name '*.md' 2>/dev/null)
        knowledge_files_found=true
    fi

    if [[ -d "knowledge/research" ]] && [[ -n "$(find knowledge/research -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        knowledge_context+="

IMPORTANT: Research reports from prior investigation exist in knowledge/research/.
Read ALL of these before planning - they contain feasibility assessments, risks,
and recommendations that MUST inform your plan:"
        while IFS= read -r f; do
            knowledge_context+="
  - $f"
        done < <(find knowledge/research -maxdepth 1 -name '*.md' 2>/dev/null)
        knowledge_files_found=true
    fi

    if [[ "$knowledge_files_found" == "true" ]]; then
        log_info "Found knowledge context from prior converse/research sessions"
    fi

    echo ""
    echo -e "${CYAN}Starting interactive planning session...${NC}"
    echo ""
    echo "You'll work with Claude to create and refine your plan."
    echo "Claude will ask clarifying questions - answer them to shape the plan."
    if [[ "$knowledge_files_found" == "true" ]]; then
        echo ""
        echo -e "${GREEN}Knowledge context detected - decisions and research will be fed into planning.${NC}"
    fi
    echo ""
    echo "When planning is complete:"
    echo "  1. Type /deepen-plan to enrich with research (recommended)"
    echo "  2. Type 'exit' or Ctrl+C when satisfied"
    echo ""
    echo -e "${YELLOW}Starting Claude...${NC}"
    echo ""

    # If knowledge context exists, prime Claude with it before planning
    if [[ -n "$knowledge_context" ]]; then
        claude --dangerously-skip-permissions "Before starting the plan, read all knowledge files for context:
${knowledge_context}

After reading those files, proceed with:
/workflows:plan $description

The plan MUST incorporate findings from the knowledge files. Reference specific
decisions, risks, and recommendations from the research/conversation phases."
    else
        # Run Claude for planning with auto-permissions (original behavior)
        claude --dangerously-skip-permissions "/workflows:plan $description"
    fi

    echo ""
    log_success "Planning session complete!"
    echo ""
    echo "Your plan should be in the plans/ directory."
    echo ""
    echo "Next steps:"
    echo "  1. Review the plan: ls plans/"
    echo "  2. Convert to spec: cr spec plans/<plan-file>.md"
    echo ""
}


#=============================================================================
# SPEC COMMAND
#=============================================================================

cmd_spec() {
    local plan_file="$1"

    if [[ -z "$plan_file" ]] || [[ ! -f "$plan_file" ]]; then
        log_error "Usage: cr spec <plan-file>"
        log_error "Example: cr spec plans/user-authentication.md"
        exit 1
    fi

    log_step "Converting Plan to SPEC"

    # Extract feature name from plan file
    local feature_name
    feature_name=$(basename "$plan_file" .md)
    local spec_dir="$SPECS_DIR/$feature_name"
    local abs_plan_file
    abs_plan_file=$(cd "$(dirname "$plan_file")" && pwd)/$(basename "$plan_file")

    # Create spec directory
    mkdir -p "$spec_dir"
    local abs_spec_dir
    abs_spec_dir=$(cd "$spec_dir" && pwd)

    # Detect project type (used for hints, but quality gates are LLM-discovered)
    local project_type
    project_type=$(detect_project_type ".")

    # Check if this is a greenfield project (no package manager files)
    local is_greenfield="false"
    if [[ ! -f "package.json" ]] && [[ ! -f "Gemfile" ]] && [[ ! -f "pyproject.toml" ]] && \
       [[ ! -f "go.mod" ]] && [[ ! -f "Cargo.toml" ]]; then
        is_greenfield="true"
    fi

    # Quality gates are now discovered by Claude, not hardcoded here
    # Claude will: extract from plan, discover from project files, or infer from plan text

    log_info "Reading plan and converting to SPEC format..."
    log_info "Project type detected: $project_type (greenfield: $is_greenfield)"
    echo ""

    # Use Claude to convert plan to SPEC with LLM-driven quality gate discovery
    local conversion_prompt="You are converting a plan document into a SPEC.md file for autonomous implementation.

READ the plan file: $abs_plan_file

Also examine the current project directory for existing config files:
- package.json, tsconfig.json, eslint.config.*, vite.config.*, astro.config.*
- Gemfile, .rubocop.yml
- pyproject.toml, pytest.ini, ruff.toml
- go.mod, Cargo.toml
- Any other relevant config files

Project info: type=$project_type, greenfield=$is_greenfield

Then CREATE the file: $abs_spec_dir/SPEC.md

---

## QUALITY GATE DISCOVERY (CRITICAL - DO NOT SKIP)

You MUST populate the Quality Gates section. Follow this priority order:

### Priority 1: Extract from Plan
If the plan has a \"Quality Gates\" or \"### Quality Gates\" section:
- Copy those commands EXACTLY as written
- They are authoritative

### Priority 2: Discover from Project Files
If the project has existing config files (package.json, Gemfile, pyproject.toml, etc.):
- Read the files to find available scripts/commands
- For package.json: check scripts.test, scripts.lint, scripts.typecheck, scripts.build, scripts.check
- For Gemfile: look for test gems (rspec, minitest), linters (rubocop), type checkers (sorbet)
- For pyproject.toml: look for pytest, ruff, mypy, black configurations
- Generate gates for commands that ACTUALLY EXIST in the config

### Priority 3: Infer from Plan Text (Greenfield Projects)
If the project directory is empty/minimal AND the plan mentions technologies:

| Plan Mentions | Inferred Quality Gates |
|---------------|------------------------|
| \"astro\" | \\\`bunx astro check\\\`, \\\`bunx astro build\\\` |
| \"next\", \"nextjs\" | \\\`next lint\\\`, \\\`next build\\\` |
| \"vite\" | \\\`vite build\\\` |
| \"vitest\" | \\\`vitest run\\\` |
| \"jest\" | \\\`jest\\\` or \\\`npm test\\\` |
| \"typescript\", \"tsx\" | \\\`tsc --noEmit\\\` or \\\`bunx tsc --noEmit\\\` |
| \"eslint\" | \\\`eslint .\\\` |
| \"prettier\" | \\\`prettier --check .\\\` |
| \"rails\", \"ruby on rails\" | \\\`bin/rails test\\\`, \\\`bundle exec rubocop\\\` |
| \"rspec\" | \\\`bundle exec rspec\\\` |
| \"python\", \"fastapi\", \"django\", \"flask\" | \\\`pytest\\\` |
| \"ruff\" | \\\`ruff check .\\\` |
| \"mypy\" | \\\`mypy .\\\` |
| \"go\", \"golang\" | \\\`go test ./...\\\`, \\\`go vet ./...\\\` |
| \"rust\", \"cargo\" | \\\`cargo test\\\`, \\\`cargo clippy\\\`, \\\`cargo check\\\` |
| \"tauri\" (mixed) | Rust: \\\`cargo test\\\`, \\\`cargo clippy\\\` + Frontend: \\\`pnpm test\\\`, \\\`pnpm lint\\\` |

### Environment Notes
- **Rust projects:** Cargo may not be in PATH by default. Task 1 MUST include: \\\`source \"\$HOME/.cargo/env\"\\\`
- **Mixed projects (e.g., Tauri):** Quality gates MUST cover ALL stacks, not just one
- **Per-Task Gates:** MUST use concrete commands, never placeholders like \\\`[file]\\\` or \\\`[module]\\\`

For greenfield projects, add this comment above Full Gates:
\\\`<!-- PROVISIONAL: Inferred from plan. Task 1 MUST verify these work. -->\\\`

### Priority 4: Placeholder
If you cannot determine quality gates:
\\\`<!-- TODO: Discover quality gates in iteration 1 -->\\\`

---

The SPEC.md MUST follow this EXACT format:

---
name: $feature_name
status: pending
created: $(date '+%Y-%m-%d')
plan_file: $plan_file
iteration_count: 0
project_type: $project_type
---

# Feature: [Title from plan]

## Overview

[2-3 sentence summary extracted from the plan]

## Requirements

[Convert the plan's requirements/goals into checkbox items]
- [ ] Requirement 1
- [ ] Requirement 2
[etc.]

## Tasks

<!--
TASK ORDERING RULES (ENFORCED):
1. Setup tasks MUST be first (dependencies, config)
2. Each implementation task MUST specify its test file
3. UI tasks MUST specify visual verification
4. NEVER create 'run tests' as a separate task at the end
-->

### Pending

#### Phase 1: Setup (MUST COMPLETE BEFORE IMPLEMENTATION)
- [ ] Task 1: Setup project and verify quality gates
  - Install dependencies (use appropriate package manager for project type)
  - Run each quality gate command from the Quality Gates section below
  - If any command fails (not found, wrong syntax), find the correct command
  - Update this SPEC.md with verified working commands
  - **Blocker if skipped**: Cannot run backpressure without working quality gates

#### Phase 2: Implementation (Each task includes its own validation)
[Break down the plan into small tasks. EACH TASK MUST INCLUDE:]

- [ ] Task N: [Create/modify source file]
  - File: \\\`src/path/to/file.ts\\\`
  - Test: \\\`tests/unit/file.test.ts\\\` (CREATE IN SAME ITERATION)
  - Validate: Run quality gates after changes
  - Visual: (if UI component) \\\`agent-browser screenshot localhost:PORT/path\\\`

#### Phase 3: Integration (After all implementation tasks)
- [ ] Task N: Run full test suite and verify all integrations work
  - Run: Full test suite including E2E if applicable
  - Visual: Full page screenshots with agent-browser (if UI)

### In Progress

### Completed

### Blocked

## Quality Gates

<!--
BACKPRESSURE RULES (ENFORCED):
- Run after EVERY task completion, not just at the end
- If a gate fails, fix it in the SAME iteration
- If dependencies aren't installed, STOP and install them first
-->

### Per-Task Gates (run after each task)
- [ ] Lint passes on changed files
- [ ] Types check on changed files
- [ ] Related tests pass (the test file you created with the source file)

### Full Gates (run after each iteration)
[DISCOVER THESE using the priority order above - extract from plan, discover from project, or infer from plan text]
- [ ] Tests pass: \\\`<discovered command>\\\`
- [ ] Lint clean: \\\`<discovered command>\\\`
- [ ] Types check: \\\`<discovered command>\\\`
- [ ] Build succeeds: \\\`<discovered command>\\\`

### Visual Gates (run after UI changes)
- [ ] Screenshot captured with agent-browser
- [ ] Visual diff acceptable (if baseline exists)

## Exit Criteria

[ALL must be true to mark complete]

- [ ] All requirements checked off
- [ ] All quality gates pass (not 'will pass later')
- [ ] All tasks completed (including their test files)
- [ ] Every source file has a corresponding test file
- [ ] Code committed with meaningful messages
- [ ] Ready for PR/review

## Context

### Key Files

[From plan - list source files AND their corresponding test files]

| Source File | Test File | Visual Check |
|-------------|-----------|--------------|
| \\\`src/path/to/file.ts\\\` | \\\`tests/unit/file.test.ts\\\` | No |
| \\\`src/components/UI.tsx\\\` | \\\`tests/unit/UI.test.tsx\\\` | Yes - screenshot |

### Patterns to Follow

[Extract any patterns, conventions, or references mentioned in the plan]

### Notes

[Any important notes or considerations from the plan]

## Iteration Log

CRITICAL RULES:
1. Task 1 MUST setup dependencies AND verify quality gates work - NEVER skip this
2. EVERY implementation task MUST specify a test file to create IN THE SAME ITERATION
3. UI tasks MUST include a Visual line with agent-browser command
4. NEVER create 'run tests' or 'run lint' as separate tasks at the end - these run PER TASK
5. Extract ALL requirements from the plan - don't leave any out
6. Break tasks down small enough to complete in one iteration (~15-30 min each)
7. Tasks should be specific and actionable, not vague
8. Include file paths where known
9. Copy any patterns/conventions mentioned in the plan to the Patterns section
10. DO NOT include placeholder text like 'Requirement 1' - use actual content from the plan
11. Quality gates MUST have actual commands, not placeholders - discover them!

Write the SPEC.md file now."

    # Run Claude to do the conversion
    echo "$conversion_prompt" | claude --dangerously-skip-permissions --print

    # Verify SPEC.md was created
    if [[ ! -f "$spec_dir/SPEC.md" ]]; then
        log_error "SPEC.md was not created. Creating minimal template..."
        # Fallback to template if Claude didn't create it
        cat > "$spec_dir/SPEC.md" << EOF
---
name: $feature_name
status: pending
created: $(date '+%Y-%m-%d')
plan_file: $plan_file
iteration_count: 0
project_type: $project_type
---

# Feature: $feature_name

## Overview

See plan file for details.

## Requirements

- [ ] See plan file

## Tasks

### Pending

- [ ] Review plan and break down tasks

### In Progress

### Completed

### Blocked

## Quality Gates

<!-- TODO: Discover quality gates in iteration 1 -->
<!-- Check plan for explicit gates, or discover from project config files -->
- [ ] Tests pass: \`<discover in iteration 1>\`
- [ ] Lint clean: \`<discover in iteration 1>\`
- [ ] Types check: \`<discover in iteration 1>\`

## Exit Criteria

- [ ] All requirements checked off
- [ ] All quality gates pass
- [ ] All tasks completed

## Context

### Key Files

See plan file.

### Patterns to Follow

See plan file.

### Notes

## Iteration Log
EOF
    fi

    log_success "Created $spec_dir/SPEC.md"

    # Copy the PROMPT template or create inline
    if [[ -f "$CR_DIR/templates/PROMPT-template.md" ]]; then
        cp "$CR_DIR/templates/PROMPT-template.md" "$spec_dir/PROMPT.md"
        log_success "Created $spec_dir/PROMPT.md (from template)"

        # Substitute {{ACCUMULATED_CONTEXT}} placeholder with actual context
        if [[ -f "$spec_dir/PROMPT.md" ]]; then
            local accumulated_ctx
            accumulated_ctx=$(get_context_for_prompt 2>/dev/null || echo "No accumulated context yet.")

            # Check if there's actual content to inject
            if [[ -n "$accumulated_ctx" ]]; then
                # Write context to temp file for safe multi-line substitution
                local ctx_temp
                ctx_temp=$(mktemp)
                printf '%s' "$accumulated_ctx" > "$ctx_temp"

                # Use Perl for reliable multi-line substitution (handles special chars)
                if command -v perl &>/dev/null; then
                    perl -i -pe "
                        BEGIN { local \$/; open(F, '<', '$ctx_temp'); \$ctx = <F>; close(F); }
                        s/\{\{ACCUMULATED_CONTEXT\}\}/\$ctx/g;
                    " "$spec_dir/PROMPT.md"
                else
                    # Fallback: use awk with file read
                    awk -v ctxfile="$ctx_temp" '
                        BEGIN { while ((getline line < ctxfile) > 0) ctx = ctx (ctx ? "\n" : "") line }
                        /\{\{ACCUMULATED_CONTEXT\}\}/ { gsub(/\{\{ACCUMULATED_CONTEXT\}\}/, ctx) }
                        { print }
                    ' "$spec_dir/PROMPT.md" > "$spec_dir/PROMPT.md.tmp" && \
                    mv "$spec_dir/PROMPT.md.tmp" "$spec_dir/PROMPT.md"
                fi

                rm -f "$ctx_temp"
                log_info "Injected accumulated context into PROMPT.md"
            fi
        fi
    else
        # Fallback: create inline with enforced backpressure
        cat > "$spec_dir/PROMPT.md" << 'PROMPT'
# Ralph Loop - Build Iteration

You are in an autonomous implementation loop. Each iteration has fresh context.
Your state persists ONLY through files (SPEC.md, git commits, Notes section).

---

## Phase 0: Pre-Flight Check (MANDATORY - DO NOT SKIP)

Before ANY implementation work, verify backpressure is possible:

```bash
# Can quality gates run?
bun --version      # Package manager works?
bun test --help    # Test runner available?
bun lint --help    # Linter available?
```

**IF ANY FAIL:**
1. Run `bun install` immediately
2. Verify all gates now work
3. Only then proceed to Phase 1

**HARD RULE:** You cannot validate code without working quality gates.

---

## Phase 1: Orient (Load Fresh Context)

Study these files in order:
1. **SPEC.md** - Single source of truth for this feature
2. **Plan file** - Referenced in SPEC.md frontmatter
3. **AGENTS.md** (if exists) - Build/test commands
4. **Key Files** - Listed in SPEC.md Context section

---

## Phase 2: Select Task

**ONLY ONE TASK PER ITERATION. Focus beats breadth.**

1. If a task is "In Progress" → Continue that task
2. Otherwise → Pick the first "Pending" task
3. Move selected task to "In Progress" BEFORE starting work

---

## Phase 3: Investigate (DON'T ASSUME NOT IMPLEMENTED)

Before writing ANY new code:
1. Search for existing implementations (Grep/Glob)
2. Check if task is partially done
3. Update Notes with discoveries

---

## Phase 4: Implement (WITH TESTS - NOT AFTER)

### HARD RULE: Source file + Test file = SAME ITERATION

```
❌ Iteration 5: Create Counter.svelte
   Iteration 25: Create Counter.test.ts  ← TOO LATE

✅ Iteration 5: Create Counter.svelte AND Counter.test.ts
```

### For UI components - take screenshot:
```
/agent-browser screenshot http://localhost:PORT/path
```

---

## Phase 5: Validate (IMMEDIATELY - NOT DEFERRED)

**Run quality gates NOW:**

```bash
bun lint [files-you-changed]
bun typecheck
bun test [test-file-you-created]
```

| Failure Type | Action |
|--------------|--------|
| Quick fix | Fix NOW in this iteration |
| Complex | Note issue, continue if non-blocking |
| Blocker | Move task to "Blocked", pick another |

**HARD RULE:** Do not mark task complete if tests don't exist or don't pass.

---

## Phase 6: Visual Verification (FOR UI CHANGES)

If you modified anything visual:
1. Take screenshot: `/agent-browser screenshot http://localhost:PORT`
2. Log in iteration: `**Visual:** Screenshot at localhost:PORT`

---

## Phase 7: Update State

1. Move task to "Completed" with iteration number
2. Add learnings to "Notes" section
3. Update `iteration_count` in frontmatter
4. Add to "Iteration Log"

---

## Phase 8: Commit & Check Exit

1. Commit: `git commit -m "feat(feature): [what]"`
2. Check ALL exit criteria
3. If ALL met: output `<loop-complete>Feature complete.</loop-complete>`

---

## HARD RULES (NEVER VIOLATE)

1. **Dependencies First** - Install before implementation
2. **Tests With Code** - Each source file gets a test file IN SAME ITERATION
3. **Validate Immediately** - Run tests after EVERY task
4. **Visual for UI** - Screenshot required for UI changes
5. **One Task Per Iteration** - Complete fully, then stop

---

## Completion Signal

When complete, output: `<loop-complete>Feature complete. All exit criteria met.</loop-complete>`
PROMPT
        log_success "Created $spec_dir/PROMPT.md (inline)"
    fi

    # Create iteration history directory
    mkdir -p "$spec_dir/.history"

    echo ""
    log_success "Spec created at $spec_dir/"
    echo ""
    echo "The SPEC.md has been populated from your plan."
    echo ""
    echo "Next steps:"
    echo "  1. Review: cat $spec_dir/SPEC.md"
    echo "  2. (Optional) Adjust tasks or add context if needed"
    echo "  3. Implement: cr implement $spec_dir"
    echo ""
}

#=============================================================================
# IMPLEMENT COMMAND
#=============================================================================

cmd_implement() {
    local spec_dir="${1:-}"

    # If no spec dir provided, find one with status: building or pending
    if [[ -z "$spec_dir" ]]; then
        # Priority 1: Look for fix specs with building status
        spec_dir=$(find "$SPECS_DIR" -path "*/fixes/*" -name "SPEC.md" -exec grep -l "status: building" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)

        # Priority 2: Look for fix specs with pending status
        if [[ -z "$spec_dir" ]]; then
            spec_dir=$(find "$SPECS_DIR" -path "*/fixes/*" -name "SPEC.md" -exec grep -l "status: pending" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
        fi

        # Priority 3: Look for regular specs with building status
        if [[ -z "$spec_dir" ]]; then
            spec_dir=$(find "$SPECS_DIR" -maxdepth 2 -name "SPEC.md" ! -path "*/fixes/*" -exec grep -l "status: building" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
        fi

        # Priority 4: Look for regular specs with pending status
        if [[ -z "$spec_dir" ]]; then
            spec_dir=$(find "$SPECS_DIR" -maxdepth 2 -name "SPEC.md" ! -path "*/fixes/*" -exec grep -l "status: pending" {} \; 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
        fi

        if [[ -z "$spec_dir" ]]; then
            log_error "No active spec found. Create one with: cr spec <plan-file>"
            exit 1
        fi
    fi

    local spec_file="$spec_dir/SPEC.md"
    local prompt_file="$spec_dir/PROMPT.md"

    if [[ ! -f "$spec_file" ]]; then
        log_error "SPEC.md not found in $spec_dir"
        exit 1
    fi

    if [[ ! -f "$prompt_file" ]]; then
        log_error "PROMPT.md not found in $spec_dir"
        exit 1
    fi

    # Check if already complete
    if grep -q "status: complete" "$spec_file"; then
        log_warn "This spec is already marked complete."
        read -p "Reset to 'building' and continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
        sed -i '' 's/status: complete/status: building/' "$spec_file"
    fi

    # Update status to building
    sed -i '' 's/status: pending/status: building/' "$spec_file" 2>/dev/null || true

    # Check if PROMPT.md is outdated compared to template
    local prompt_file="$spec_dir/PROMPT.md"
    local template_file="$CR_DIR/templates/PROMPT-template.md"
    if [[ -f "$prompt_file" ]] && [[ -f "$template_file" ]]; then
        local prompt_time template_time
        # Linux uses -c %Y, macOS uses -f %m (stat -f on Linux returns filesystem info, not file mtime)
        if [[ "$(uname)" == "Darwin" ]]; then
            prompt_time=$(stat -f %m "$prompt_file" 2>/dev/null || echo 0)
            template_time=$(stat -f %m "$template_file" 2>/dev/null || echo 0)
        else
            prompt_time=$(stat -c %Y "$prompt_file" 2>/dev/null || echo 0)
            template_time=$(stat -c %Y "$template_file" 2>/dev/null || echo 0)
        fi

        if [[ "$template_time" -gt "$prompt_time" ]]; then
            log_warn "PROMPT.md is older than the template and may be missing recent improvements"
            log_warn "Run 'cr spec <plan-file> --force' to regenerate from latest template"
            log_warn "Or run 'cr reset-context $spec_dir' to clear accumulated context"
            echo ""
        fi
    fi

    log_step "Starting Compound Ralph Loop"
    echo "Spec:           $spec_file"
    echo "Max iterations: $MAX_ITERATIONS"
    echo "Delay:          ${ITERATION_DELAY}s between iterations"
    echo "Learnings:      .cr/learnings.json"
    echo ""
    echo "Press Ctrl+C to stop at any time."
    echo ""

    local iteration=0
    local history_dir="$spec_dir/.history"
    mkdir -p "$history_dir"

    # Get absolute path to spec directory
    local abs_spec_dir
    abs_spec_dir=$(cd "$spec_dir" && pwd)

    # Export for use by run_iteration_checks
    CURRENT_SPEC_DIR="$abs_spec_dir"

    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
        iteration=$((iteration + 1))
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Check for shutdown before starting iteration
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            log_info "Shutdown requested. Stopping loop."
            exit 130
        fi

        # Check if all tasks are already complete before starting iteration
        local pending_tasks completed_tasks
        pending_tasks=$(grep -c "^\- \[ \]" "$spec_file" 2>/dev/null || true)
        completed_tasks=$(grep -c "^\- \[x\]" "$spec_file" 2>/dev/null || true)
        pending_tasks=${pending_tasks:-0}
        completed_tasks=${completed_tasks:-0}

        if [[ $pending_tasks -eq 0 ]] && [[ $completed_tasks -gt 0 ]]; then
            log_info "All tasks complete ($completed_tasks tasks). Running final verification..."

            # Run integration verification
            if verify_integration; then
                log_success "All tasks complete and verified!"
                sed -i '' 's/status: building/status: complete/' "$spec_file" 2>/dev/null || \
                sed -i 's/status: building/status: complete/' "$spec_file"
                echo ""
                echo "Next steps:"
                echo "  1. Review changes: git diff main"
                echo "  2. Run code review: cr review"
                echo "  3. Create PR when ready"
                exit 0
            else
                log_warn "Tasks complete but integration failed. Adding fix task..."
                {
                    echo ""
                    echo "### Integration Fix Required (Auto-added)"
                    echo "- [ ] Fix integration failures: ${INTEGRATION_FAILURES[*]}"
                } >> "$spec_file"
                # Continue to let the loop handle it
            fi
        fi

        echo ""
        echo -e "${CYAN}${BOLD}=== Iteration $iteration ($timestamp) ===${NC}"
        echo ""

        # Clear gate failures from previous iteration (each iteration gets fresh tracking)
        rm -f .cr/gate_failures.txt

        # Log file for this iteration
        local log_file="$history_dir/$(printf '%03d' $iteration)-$(date '+%Y%m%d-%H%M%S').md"

        # Build iteration context
        local issues_context=""
        if [[ -n "${PENDING_ISSUES:-}" ]]; then
            # Look for similar errors we've fixed before
            local similar_fixes=""
            similar_fixes=$(find_similar_fixes_in_learnings "${PENDING_ISSUES}" 2>/dev/null || true)

            issues_context="
ISSUES FROM PREVIOUS ITERATION (fix these first!):
- ${PENDING_ISSUES}
"
            if [[ -n "$similar_fixes" ]]; then
                issues_context+="
$similar_fixes
"
            fi
            issues_context+="
Before continuing with tasks, address these issues."
        fi

        local learnings_context=""
        if [[ -f ".cr/learnings.json" ]]; then
            local recent_learnings
            recent_learnings=$(get_learnings_summary "" 5 2>/dev/null)
            if [[ -n "$recent_learnings" ]]; then
                learnings_context="

LEARNINGS FROM PREVIOUS ITERATIONS (reference these):
$recent_learnings"
            fi
        fi

        # Get accumulated context from learnings.json (persists across sessions)
        local accumulated_context=""
        if [[ -f ".cr/learnings.json" ]]; then
            accumulated_context=$(get_context_for_prompt 2>/dev/null || true)
            if [[ -n "$accumulated_context" ]]; then
                accumulated_context="

$accumulated_context"
            fi
        fi

        # Refresh PROMPT.md with latest accumulated context
        refresh_prompt_context "$abs_spec_dir"

        # Generate summary from previous iteration (if any)
        local prev_iteration_summary=""
        if [[ $iteration -gt 1 ]]; then
            local prev_log
            prev_log=$(get_previous_iteration_log "$history_dir" "$iteration" 2>/dev/null || true)
            if [[ -n "$prev_log" ]] && [[ -f "$prev_log" ]]; then
                prev_iteration_summary=$(generate_iteration_summary "$prev_log" 2>/dev/null || true)
            fi
        fi

        # Create the iteration prompt
        local iteration_prompt="You are in iteration $iteration of a Compound Ralph implementation loop.
$prev_iteration_summary
CRITICAL INSTRUCTIONS:
1. Read $abs_spec_dir/SPEC.md - this is your single source of truth
2. Read $abs_spec_dir/PROMPT.md - this contains your detailed instructions
3. Follow the phases in PROMPT.md exactly
4. Complete ONE task, run quality checks, update SPEC.md
5. If ALL exit criteria are met, output <loop-complete>Feature complete</loop-complete>
6. Output LEARNING/PATTERN/FIXED markers to help future iterations learn
$issues_context$learnings_context$accumulated_context

Start by reading both files now."

        # Run Claude with the iteration prompt
        # Initialize log file
        {
            echo "# Iteration $iteration"
            echo "Started: $timestamp"
            echo "Spec: $abs_spec_dir/SPEC.md"
            echo ""
            echo "## Output"
            echo ""
        } > "$log_file"

        # Check for shutdown request
        if [[ "$SHUTDOWN_REQUESTED" == "true" ]]; then
            log_info "Shutdown requested. Stopping loop."
            exit 130
        fi

        # Run the iteration with retry logic
        if ! run_claude_with_retry "$iteration_prompt" "$log_file"; then
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            log_warn "Iteration $iteration failed after retries. (Consecutive failures: $CONSECUTIVE_FAILURES/$MAX_CONSECUTIVE_FAILURES)"

            # Add failure note to log
            {
                echo ""
                echo "## Iteration Failed"
                echo "This iteration failed after $MAX_RETRIES retries."
                echo "Consecutive failures: $CONSECUTIVE_FAILURES"
            } >> "$log_file"

            # Check for too many consecutive failures
            if [[ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                echo ""
                log_error "Too many consecutive failures ($CONSECUTIVE_FAILURES). Stopping to prevent infinite loop."
                log_error "This usually means:"
                log_error "  - API is having issues (wait and try again)"
                log_error "  - Network connectivity problems"
                log_error "  - Rate limiting"
                echo ""
                log_info "Resume when ready: cr implement $spec_dir"
                exit 1
            fi

            sleep "$ITERATION_DELAY"
            continue
        fi

        # Success - reset consecutive failures
        CONSECUTIVE_FAILURES=0

        # Run per-iteration checks (tests, lint, typecheck)
        log_info "Running per-iteration checks..."
        if ! run_iteration_checks; then
            log_warn "Per-iteration checks failed. Next iteration will address these issues."

            # Prepare issues for next iteration prompt
            PENDING_ISSUES="${ITERATION_ISSUES[*]}"

            # Add note to log
            {
                echo ""
                echo "## Per-Iteration Checks"
                echo "Failed: ${ITERATION_ISSUES[*]}"
            } >> "$log_file"

            # Record learning about the failure
            add_learning "iteration_failure" "Iteration $iteration had issues: ${ITERATION_ISSUES[*]}" "" "$(basename "$spec_dir")" "$iteration"
        else
            log_success "Per-iteration checks passed"
            PENDING_ISSUES=""

            # Add success note to log
            {
                echo ""
                echo "## Per-Iteration Checks"
                echo "All checks passed (tests, lint, typecheck)"
            } >> "$log_file"
        fi

        # Parse iteration output for learnings (COMPLETED, LEARNING, PATTERN, FIXED markers)
        parse_iteration_output "$log_file" "$(basename "$spec_dir")" "$iteration"

        # Check for completion signal in log (support both old and new format)
        # Match the FULL tag with closing to avoid false positives like "Not outputting `<loop-complete>`"
        if grep -qE "<loop-complete>.*</loop-complete>|<promise>COMPLETE</promise>" "$log_file"; then
            echo ""

            # If per-iteration checks failed, don't accept completion
            if [[ ${#ITERATION_ISSUES[@]} -gt 0 ]]; then
                log_warn "Claude signaled completion but per-iteration checks failed:"
                for issue in "${ITERATION_ISSUES[@]}"; do
                    log_warn "  - $issue"
                done
                echo ""
                log_error "=== COMPLETION REJECTED ==="
                log_error "You MUST fix these errors before completion is accepted."
                log_error ""
                log_error "DO NOT:"
                log_error "  - Dismiss errors as 'pre-existing'"
                log_error "  - Signal <loop-complete> again without fixing"
                log_error "  - Add documentation instead of fixing"
                log_error ""
                log_error "DO:"
                log_error "  - Read the actual error messages"
                log_error "  - Fix the root cause of each error"
                log_error "  - Run the quality gate again to verify"
                log_error ""
                log_error "If a gate is TRULY unfixable (requires external API key, etc.):"
                log_error "  - Mark it as [INFORMATIONAL] in SPEC.md Quality Gates"
                log_error "  - Example: '- [ ] [INFORMATIONAL] External API: \`curl ...\`'"
                log_error ""
                log_info "Continuing loop to address issues..."

                # Add issues to SPEC for next iteration with clear instructions
                {
                    echo ""
                    echo "### Quality Gate Failures - MUST FIX (Auto-added iteration $iteration)"
                    echo ""
                    echo "**These errors MUST be fixed before completion will be accepted.**"
                    echo ""
                    echo "Do NOT:"
                    echo "- Dismiss as 'pre-existing' - fix them anyway"
                    echo "- Signal completion again without fixing"
                    echo "- Document the errors instead of fixing them"
                    echo ""
                    echo "Failing gates:"
                    for issue in "${ITERATION_ISSUES[@]}"; do
                        echo "- [ ] $issue"
                    done
                    echo ""

                    # Include ACTUAL ERROR OUTPUT so agent knows what to fix
                    if [[ -f ".cr/gate_failures.txt" ]]; then
                        echo "**Actual error output (READ THIS TO UNDERSTAND WHAT TO FIX):**"
                        echo ""
                        echo '```'
                        # Include up to 100 lines of errors (enough context, not overwhelming)
                        head -100 .cr/gate_failures.txt
                        echo '```'
                        echo ""
                    fi

                    echo "Fix these specific errors. Do not proceed until they are resolved."
                } >> "$spec_file"

                sleep "$ITERATION_DELAY"
                continue
            fi

            log_info "Claude signals completion. Verifying integration..."

            # Detect project type for verification
            local project_type
            project_type=$(detect_project_type ".")

            # Run integration verification
            if verify_integration "$project_type"; then
                # Integration passed - truly complete
                log_success "Feature complete after $iteration iterations!"

                # Update spec status
                sed -i '' 's/status: building/status: complete/' "$spec_file"

                echo ""
                echo "Next steps:"
                echo "  1. Review changes: git diff main"
                echo "  2. Run code review: cr review"
                echo "  3. Fix any issues:  cr fix && cr implement"
                echo "  4. Document learnings: claude /workflows:compound"
                echo "  5. Create PR when ready"
                echo ""
                exit 0
            else
                # Integration failed - continue loop to fix
                log_warn "Integration verification failed. Continuing loop to fix issues..."
                echo ""

                # Create a new iteration prompt focused on fixing integration
                local fix_prompt="INTEGRATION VERIFICATION FAILED

The following integration checks failed:
$(for f in "${INTEGRATION_FAILURES[@]}"; do echo "- $f"; done)

You must fix these issues before the feature can be considered complete.

1. Read the SPEC.md to understand the context
2. Investigate why each integration check failed
3. Fix the root cause (not just suppress errors)
4. Verify the fix works
5. Update SPEC.md notes with what you learned

Do NOT output <loop-complete> until integration actually passes.

Start by investigating the first failure: ${INTEGRATION_FAILURES[0]}"

                # Add a task to SPEC for fixing integration
                {
                    echo ""
                    echo "### Integration Fix Required (Auto-added)"
                    echo "- [ ] Fix integration failures: ${INTEGRATION_FAILURES[*]}"
                } >> "$spec_file"

                # Continue to next iteration with the fix prompt
                sleep "$ITERATION_DELAY"
                continue
            fi
        fi

        # Check if spec was marked complete manually
        if grep -q "status: complete" "$spec_file"; then
            echo ""
            log_success "Spec marked complete after $iteration iterations!"
            exit 0
        fi

        # Delay before next iteration
        log_info "Waiting ${ITERATION_DELAY}s before next iteration..."
        sleep "$ITERATION_DELAY"
    done

    echo ""
    log_warn "Max iterations ($MAX_ITERATIONS) reached without completion."
    echo ""
    echo "Options:"
    echo "  1. Review SPEC.md to see current progress"
    echo "  2. Run 'cr implement $spec_dir' to continue"
    echo "  3. Increase MAX_ITERATIONS: MAX_ITERATIONS=100 cr implement $spec_dir"
    echo ""
    exit 1
}

#=============================================================================
# REVIEW COMMAND
#=============================================================================

cmd_review() {
    local spec_dir=""
    local review_type="code"  # code, design, or both
    local design_url=""
    local use_team=false
    local team_model=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team)
                use_team=true
                shift
                ;;
            --team-model)
                team_model="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --design)
                if [[ "$review_type" == "code" ]]; then
                    review_type="both"
                fi
                shift
                ;;
            --design-only)
                review_type="design"
                shift
                ;;
            --url)
                design_url="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                spec_dir="$1"
                shift
                ;;
        esac
    done

    # Determine review type label
    local review_label
    case "$review_type" in
        code)   review_label="Code Review" ;;
        design) review_label="Design Review" ;;
        both)   review_label="Code + Design Review" ;;
    esac

    log_step "Running $review_label"

    # Find spec if not provided, or create a default one for standalone reviews
    local standalone_review=false
    if [[ -z "$spec_dir" ]] || [[ ! -d "$spec_dir" ]]; then
        spec_dir=$(find_active_spec || true)
        if [[ -z "$spec_dir" ]]; then
            # No spec found - create a default review location
            standalone_review=true
            spec_dir="specs/_reviews"
            mkdir -p "$spec_dir"

            # Create a minimal SPEC.md if it doesn't exist
            if [[ ! -f "$spec_dir/SPEC.md" ]]; then
                cat > "$spec_dir/SPEC.md" << 'SPEC_EOF'
# Standalone Reviews

This spec is auto-created for running `cr review` without a specific spec context.

Review findings are stored here when no active spec is specified.

## Usage

Run reviews:
```bash
cr review              # Code review
cr review --design     # Code + design review
cr review --design-only # Design review only
```

Findings are saved to:
- `todos/code/` - Code review findings
- `todos/design/` - Design review findings
SPEC_EOF
                log_info "Created standalone review spec at $spec_dir/"
                log_info "Note: Specify a spec for feature-specific reviews: cr review specs/my-feature/"
                echo ""
            fi
        fi
    fi

    # Validate spec exists
    if [[ ! -f "$spec_dir/SPEC.md" ]]; then
        log_error "No SPEC.md found in $spec_dir"
        exit 1
    fi

    local spec_name
    spec_name=$(basename "$spec_dir")

    if [[ "$standalone_review" == "true" ]]; then
        log_info "Running standalone review (no spec context)"
    else
        log_info "Reviewing spec: $spec_name"
    fi

    # Get absolute path for spec
    local abs_spec_dir
    abs_spec_dir=$(cd "$spec_dir" && pwd)

    # Create todos directories within the spec
    local code_todos_dir="$abs_spec_dir/todos/code"
    local design_todos_dir="$abs_spec_dir/todos/design"

    # Run code review
    if [[ "$review_type" == "code" ]] || [[ "$review_type" == "both" ]]; then
        mkdir -p "$code_todos_dir"

        log_info "Running code review..."
        log_info "Findings will be saved to: $spec_name/todos/code/"
        echo ""

        local code_review_prompt
        if [[ "$standalone_review" == "true" ]]; then
            code_review_prompt="You are reviewing code changes in this repository.

This is a standalone review (no specific feature spec).
Review the current git diff and recent changes for issues.

Run /workflows:review to perform comprehensive code review.

IMPORTANT: Save all todo files to this directory:
$code_todos_dir/

Name files like: 001-p1-issue-name.md, 002-p2-issue-name.md, etc.

Use this format for todos:
---
priority: p1|p2|p3
tags: [security|performance|architecture|etc]
spec: standalone
type: code
---
# [Issue Title]

## Problem Statement
[What's wrong]

## Findings
- File: \`path/to/file.ts:line\`

## Recommended Action
[How to fix]

## Acceptance Criteria
- [ ] [Specific outcome]

Run the review now."
        else
            code_review_prompt="You are reviewing code changes for the spec: $spec_name

SPEC FILE: $abs_spec_dir/SPEC.md

Run /workflows:review to perform comprehensive code review.

IMPORTANT: Save all todo files to this directory:
$code_todos_dir/

Name files like: 001-p1-issue-name.md, 002-p2-issue-name.md, etc.

Use this format for todos:
---
priority: p1|p2|p3
tags: [security|performance|architecture|etc]
spec: $spec_name
type: code
---
# [Issue Title]

## Problem Statement
[What's wrong]

## Findings
- File: \`path/to/file.ts:line\`

## Recommended Action
[How to fix]

## Acceptance Criteria
- [ ] [Specific outcome]

Run the review now."
        fi

        if [[ "$use_team" == "true" ]]; then
            # Agent Teams mode: spawn competing reviewers
            
            # Validate experimental feature is enabled
            if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
                log_error "Agent Teams requires the experimental feature to be enabled."
                log_error ""
                log_error "Add to ~/.claude/settings.json:"
                log_error '  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }'
                log_error ""
                log_error "Or set the environment variable:"
                log_error "  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
                exit 1
            fi

            local team_model_arg=""
            if [[ -n "$team_model" ]]; then
                team_model_arg="Use $team_model for each teammate."
            fi

            # Dry-run mode: show team structure without running
            if [[ "$dry_run" == "true" ]]; then
                log_step "Agent Teams Review (dry-run)"
                echo ""
                echo "Would create agent team with 3 competing reviewers:"
                echo ""
                echo "  🔒 Security Reviewer"
                echo "     Focus: auth, validation, injection, secrets"
                echo ""
                echo "  ⚡ Performance Reviewer"
                echo "     Focus: complexity, memory, queries, bundle size"
                echo ""
                echo "  ✅ Quality Reviewer"
                echo "     Focus: tests, error handling, maintainability"
                echo ""
                if [[ -n "$team_model" ]]; then
                    echo "  Model: $team_model (for each teammate)"
                else
                    echo "  Model: default"
                fi
                echo ""
                echo "  Spec: $spec_name"
                echo "  Output: $code_todos_dir/"
                echo ""
                log_info "Run without --dry-run to execute"
                return 0
            fi

            log_info "Using Agent Teams mode with competing reviewers"
            log_warn "Note: This uses significantly more tokens than single-session review"
            echo ""

            local team_review_prompt
            team_review_prompt=$(load_prompt "review-team.txt")
            team_review_prompt="${team_review_prompt//__SPEC_NAME__/$spec_name}"
            team_review_prompt="${team_review_prompt//__ABS_SPEC_DIR__/$abs_spec_dir}"
            team_review_prompt="${team_review_prompt//__CODE_TODOS_DIR__/$code_todos_dir}"
            team_review_prompt="${team_review_prompt//__TEAM_MODEL_ARG__/$team_model_arg}"
            validate_prompt "$team_review_prompt" "review-team"

            echo "$team_review_prompt" | claude --dangerously-skip-permissions --print
        else
            echo "$code_review_prompt" | claude --dangerously-skip-permissions --print
        fi
        echo ""
    fi

    # Run design review
    if [[ "$review_type" == "design" ]] || [[ "$review_type" == "both" ]]; then
        mkdir -p "$design_todos_dir"

        log_info "Running design review..."

        # Auto-detect dev server if no URL provided
        if [[ -z "$design_url" ]]; then
            design_url=$(detect_dev_server 2>/dev/null || true)
        fi

        if [[ -z "$design_url" ]]; then
            log_warn "No dev server detected for design review."
            log_warn "Start your dev server or use: cr review --design --url http://localhost:3000"
        else
            # Create screenshots directory for this review session
            local review_screenshots_dir="design-reviews"
            mkdir -p "$review_screenshots_dir"
            local review_timestamp
            review_timestamp=$(date '+%Y%m%d-%H%M%S')
            local review_session_dir="$review_screenshots_dir/$review_timestamp"
            mkdir -p "$review_session_dir"

            log_info "Design review target: $design_url"
            log_info "Will discover ALL pages AND view states (SPA-aware)"
            log_info "Screenshots will be saved to: $review_session_dir/"
            log_info "Findings will be saved to: $spec_name/todos/design/"
            echo ""

            local design_review_prompt
            local design_context
            local design_spec_tag

            if [[ "$standalone_review" == "true" ]]; then
                design_context="You are reviewing UI design for this application.

This is a standalone review (no specific feature spec)."
                design_spec_tag="standalone"
            else
                design_context="You are reviewing UI design for the spec: $spec_name

SPEC FILE: $abs_spec_dir/SPEC.md"
                design_spec_tag="$spec_name"
            fi

            design_review_prompt="$design_context

TARGET URL: $design_url

INSTRUCTIONS:

## Step 1: Discover All Pages (URL-based)

First, crawl the site to find all URL-based pages:

\`\`\`bash
# Open the base URL
agent-browser open $design_url

# Get all navigation links (look for nav, header, footer links)
agent-browser eval \"Array.from(document.querySelectorAll('nav a, header a, footer a, [role=navigation] a')).map(a => a.href).filter(h => h.startsWith(window.location.origin))\"
\`\`\`

Build a list of unique URL pages to review.

## Step 2: Discover View States (SPA-aware)

CRITICAL: Modern SPAs have multiple views/states at the SAME URL. You must discover these.

For EACH page, after opening it, discover view states:

\`\`\`bash
# Get interactive elements to find view switchers
agent-browser snapshot -i
\`\`\`

Look for these patterns in the snapshot output:

1. **Tab groups / View switchers** - Elements with:
   - role=\"tablist\" or role=\"tab\"
   - Buttons/links labeled: View, Mode, Tab, Focus, Tree, Gallery, Compare, List, Grid, Stats
   - Segmented controls or toggle button groups
   - Sidebar navigation items that don't change URL

2. **Keyboard shortcuts** - Check for:
   - Number keys 1-9 often switch views
   - Letters like G (gallery), T (tree), S (stats)
   - Look for keyboard hint text or data-shortcut attributes
   \`\`\`bash
   # Try common view-switching shortcuts
   agent-browser press 1
   agent-browser snapshot -i  # Check if view changed
   agent-browser press 2
   agent-browser snapshot -i  # Check if view changed
   # Continue for 3, 4, 5 if views keep changing
   \`\`\`

3. **Collapsible sidebars** - Look for:
   - Toggle buttons for sidebars/panels
   - Collapsed vs expanded states
   - Left/right panel toggles

4. **Sub-tabs within views** - Like:
   - \"Trees\" vs \"Favorites\" tabs in a sidebar
   - Filter modes or display options

Build a complete list of view states for each page:
\`\`\`
Page: /dashboard
  - View: focus (default, or press 1)
  - View: tree (press 2, or click Tree tab)
  - View: compare (press 3)
  - View: gallery (press 4)
  - View: statistics (press 5)
  - Sidebar: trees tab
  - Sidebar: favorites tab
  - Sidebar: collapsed state
\`\`\`

## Step 3: Screenshot Each Page AND View State at Multiple Viewports

SCREENSHOT DIRECTORY: $review_session_dir/

For EACH page, and for EACH view state on that page, screenshot at ALL viewport widths:

\`\`\`bash
# Example: Dashboard with multiple view states
agent-browser open [page-url]

# === DEFAULT VIEW ===
agent-browser resize 1920 1080
agent-browser screenshot $review_session_dir/[page-name]-default-1920.png
agent-browser resize 1440 900
agent-browser screenshot $review_session_dir/[page-name]-default-1440.png
agent-browser resize 1024 768
agent-browser screenshot $review_session_dir/[page-name]-default-1024.png
agent-browser resize 375 812
agent-browser screenshot $review_session_dir/[page-name]-default-375.png

# === EACH DISCOVERED VIEW STATE ===
# Switch to next view (click tab or press shortcut)
agent-browser press 2  # or: agent-browser click @e5
agent-browser resize 1920 1080
agent-browser screenshot $review_session_dir/[page-name]-[view-name]-1920.png
agent-browser resize 1440 900
agent-browser screenshot $review_session_dir/[page-name]-[view-name]-1440.png
agent-browser resize 1024 768
agent-browser screenshot $review_session_dir/[page-name]-[view-name]-1024.png
agent-browser resize 375 812
agent-browser screenshot $review_session_dir/[page-name]-[view-name]-375.png

# Repeat for ALL view states discovered in Step 2
\`\`\`

Naming convention for screenshots:
- \`landing-1920.png\` - Simple page, no view states
- \`dashboard-focus-1920.png\` - Dashboard in focus view
- \`dashboard-tree-1920.png\` - Dashboard in tree view
- \`dashboard-gallery-1440.png\` - Dashboard gallery at laptop size
- \`dashboard-sidebar-collapsed-1024.png\` - Collapsed sidebar state

IMPORTANT:
- Screenshot ALL viewport sizes for EVERY view state
- Don't skip views - each view may have unique responsive issues
- Sidebar states often break differently than main content

## Step 4: Load Design Skill

Load the /frontend-design skill to apply its philosophy:
Use: skill: frontend-design

## Step 5: Review ALL Pages AND View States

Apply the /frontend-design skill philosophy to critique EACH page AND EACH view state:

   DISTINCTIVE vs GENERIC - Ask yourself:
   - Does this look like every other AI-generated site? (Bad)
   - Would a human designer be proud of this? (Good)
   - Is there a clear point of view? (Good)
   - Could this be any company's website? (Bad)

   TYPOGRAPHY - Check for:
   - Default system fonts vs intentional font choices
   - Weak hierarchy (everything same size/weight)
   - Poor line-height and letter-spacing
   - Missing typographic rhythm

   COLOR - Look for:
   - Too much gray (the #1 sign of AI-generated design)
   - Safe, boring palette with no personality
   - Poor contrast or muddy colors
   - No accent color or visual interest

   SPACING & LAYOUT - Evaluate:
   - Cramped or inconsistent spacing
   - No visual rhythm or intentional whitespace
   - Generic grid without personality
   - Components feel disconnected

   RESPONSIVE DESIGN - Check at ALL viewport sizes:
   - Text compression or overflow at larger widths (1920px, 1440px)
   - Layout breaks at specific breakpoints
   - Elements that don't scale properly between sizes
   - Content that becomes unreadable at mobile (375px)
   - Max-width constraints that cause issues when maximized

   COMPONENTS - Identify:
   - Default/unstyled buttons, inputs, cards
   - No hover states or micro-interactions
   - Generic shadows and borders
   - Missing polish and craft

   PERSONALITY - Consider:
   - Does the design have a point of view?
   - Is there craft and attention to detail?
   - Would this stand out or blend in?

4. For each issue found, create a todo file in:
   $design_todos_dir/

   Name files like: 001-p2-bland-hero.md, 002-p2-weak-typography.md

5. Use this format (note: include PAGE and VIEW STATE where issue was found):
---
priority: p2
tags: [design, ui, frontend-design]
spec: $design_spec_tag
type: design
page: [url of page where issue found]
view: [view state if applicable, e.g., \"tree\", \"gallery\", \"sidebar-collapsed\"]
---
# [Issue Title]

## Problem Statement
[What's wrong - reference specific /frontend-design principles violated]

## Findings
- Page: \`[full URL of the page]\`
- View State: \`[view name, e.g., tree, gallery, focus]\` (or \"default\" if no SPA views)
- File: \`path/to/component.tsx\`
- Screenshot: [reference screenshot filename, e.g., dashboard-tree-375.png]
- Principle violated: [e.g., 'Generic color palette with too much gray']

## Recommended Action
[Specific design improvement following /frontend-design philosophy]
[Include concrete suggestions: specific colors, font sizes, spacing values]

## Acceptance Criteria
- [ ] [Specific visual outcome that would satisfy /frontend-design standards]

## Review Summary

After reviewing ALL pages, ALL view states, at ALL viewport sizes, provide a summary:
- Total URL pages reviewed: [N]
- Total view states reviewed: [N] (e.g., dashboard has 5 views = 5 states)
- Viewport sizes tested: 1920px, 1440px, 1024px, 375px
- Total screenshots taken: [N]

### Issues Found
- Global issues (affect all pages/views): [list]
- Page-specific issues: [list by page]
- View-specific issues: [list by view state]
- Responsive issues: [list any layout/scaling problems at specific viewports]

### View State Coverage
List all view states discovered and reviewed:
| Page | View State | Screenshots |
|------|------------|-------------|
| /dashboard | focus | 4 viewports |
| /dashboard | tree | 4 viewports |
| etc. | | |

IMPORTANT: Be opinionated. The /frontend-design skill demands distinctive, memorable design.
Don't accept 'good enough' - push for design that has craft and personality.

CRITICAL FOR SPAs:
- Review EVERY view state, not just the default view
- Each view (focus, tree, gallery, etc.) may have completely different layouts and issues
- Sidebar states (collapsed, different tabs) often have unique responsive bugs
- A thorough review of a complex SPA like a dashboard should have 20-50+ screenshots

Screenshots are saved to: $review_session_dir/"

            echo "$design_review_prompt" | claude --dangerously-skip-permissions --print
            echo ""
        fi
    fi

    # Count findings
    local code_count=0
    local design_count=0

    if [[ -d "$code_todos_dir" ]]; then
        code_count=$(find "$code_todos_dir" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [[ -d "$design_todos_dir" ]]; then
        design_count=$(find "$design_todos_dir" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    fi

    local total_count=$((code_count + design_count))

    log_success "Review complete!"
    echo ""
    echo "Spec:     $spec_name"
    echo "Findings: $code_count code, $design_count design ($total_count total)"
    echo ""
    echo "Todos saved to:"
    [[ $code_count -gt 0 ]] && echo "  - $spec_name/todos/code/ ($code_count files)"
    [[ $design_count -gt 0 ]] && echo "  - $spec_name/todos/design/ ($design_count files)"
    echo ""
    echo "Next steps:"
    echo "  1. View findings:    ls $spec_dir/todos/"
    [[ $code_count -gt 0 ]] && echo "  2. Fix code issues:  cr fix code"
    [[ $design_count -gt 0 ]] && echo "  3. Fix design:       cr fix design"
    echo "  4. Fix all:          cr fix"
    if [[ "$review_type" == "code" ]]; then
        echo ""
        echo "  Run design review:   cr review --design"
    fi
    echo ""
}

#=============================================================================
# FIX COMMAND
#=============================================================================

cmd_fix() {
    local fix_type=""
    local spec_dir=""

    # Parse arguments: cr fix [code|design] [spec-dir]
    while [[ $# -gt 0 ]]; do
        case "$1" in
            code|design)
                fix_type="$1"
                shift
                ;;
            *)
                # Assume it's a spec directory
                if [[ -d "$1" ]]; then
                    spec_dir="$1"
                else
                    log_error "Unknown argument or directory not found: $1"
                    log_error "Usage: cr fix [code|design] [spec-dir]"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Find spec if not provided
    if [[ -z "$spec_dir" ]]; then
        spec_dir=$(find_active_spec || true)
        if [[ -z "$spec_dir" ]]; then
            log_error "No active spec found."
            log_error "Specify a spec: cr fix specs/my-feature/"
            exit 1
        fi
    fi

    # Validate spec
    if [[ ! -f "$spec_dir/SPEC.md" ]]; then
        log_error "No SPEC.md found in $spec_dir"
        exit 1
    fi

    local spec_name
    spec_name=$(basename "$spec_dir")

    local abs_spec_dir
    abs_spec_dir=$(cd "$spec_dir" && pwd)

    # Determine what to fix
    local fix_label
    local todos_dirs=()

    if [[ -z "$fix_type" ]]; then
        # Fix all - code first, then design
        fix_label="All Issues"
        [[ -d "$abs_spec_dir/todos/code" ]] && todos_dirs+=("$abs_spec_dir/todos/code")
        [[ -d "$abs_spec_dir/todos/design" ]] && todos_dirs+=("$abs_spec_dir/todos/design")
    elif [[ "$fix_type" == "code" ]]; then
        fix_label="Code Issues"
        todos_dirs+=("$abs_spec_dir/todos/code")
    elif [[ "$fix_type" == "design" ]]; then
        fix_label="Design Issues"
        todos_dirs+=("$abs_spec_dir/todos/design")
    fi

    log_step "Creating Fix Spec: $fix_label"
    log_info "Source spec: $spec_name"

    # Check todos exist
    local todo_files=()
    for todos_dir in "${todos_dirs[@]}"; do
        if [[ -d "$todos_dir" ]]; then
            while IFS= read -r file; do
                [[ -n "$file" ]] && todo_files+=("$file")
            done < <(find "$todos_dir" -name "*.md" 2>/dev/null)
        fi
    done

    local todo_count=${#todo_files[@]}

    if [[ $todo_count -eq 0 ]]; then
        log_warn "No todos found to fix."
        echo ""
        echo "Run a review first:"
        echo "  cr review              # Code review"
        echo "  cr review --design     # Design review"
        exit 1
    fi

    log_info "Found $todo_count todos to convert"

    # Create fix spec directory within the parent spec
    local fix_dir="$abs_spec_dir/fixes"
    if [[ -n "$fix_type" ]]; then
        fix_dir="$abs_spec_dir/fixes/$fix_type"
    fi
    mkdir -p "$fix_dir"

    # Get absolute paths for todo files
    local abs_todo_files=""
    for file in "${todo_files[@]}"; do
        abs_todo_files+="$file"$'\n'
    done

    # Detect project type for quality gates
    local project_type
    project_type=$(detect_project_type ".")

    # Pre-compute dynamic content
    local today_date
    today_date=$(date '+%Y-%m-%d')

    # Generate quality gates based on available scripts
    local quality_gates=""
    case "$project_type" in
        bun)
            has_script "test" && quality_gates+="- [ ] Tests pass: \`bun test\`"$'\n'
            has_script "lint" && quality_gates+="- [ ] Lint clean: \`bun run lint\`"$'\n'
            if has_script "typecheck"; then
                quality_gates+="- [ ] Types check: \`bun run typecheck\`"
            elif [[ -f "tsconfig.json" ]]; then
                quality_gates+="- [ ] Types check: \`bunx tsc --noEmit\`"
            fi
            quality_gates="${quality_gates%$'\n'}"
            ;;
        npm|yarn|pnpm)
            has_script "test" && quality_gates+="- [ ] Tests pass: \`$project_type run test\`"$'\n'
            has_script "lint" && quality_gates+="- [ ] Lint clean: \`$project_type run lint\`"$'\n'
            if has_script "typecheck"; then
                quality_gates+="- [ ] Types check: \`$project_type run typecheck\`"
            elif [[ -f "tsconfig.json" ]]; then
                quality_gates+="- [ ] Types check: \`npx tsc --noEmit\`"
            fi
            quality_gates="${quality_gates%$'\n'}"
            ;;
        rails)
            quality_gates="- [ ] Tests pass: \`bin/rails test\`
- [ ] Lint clean: \`bundle exec rubocop\`"
            ;;
        python)
            quality_gates=""
            [[ -f "pytest.ini" || -f "pyproject.toml" ]] && quality_gates+="- [ ] Tests pass: \`pytest\`"$'\n'
            [[ -f "pyproject.toml" ]] && grep -q "ruff" pyproject.toml 2>/dev/null && \
                quality_gates+="- [ ] Lint clean: \`ruff check .\`"$'\n'
            [[ -f "pyproject.toml" ]] && grep -q "mypy" pyproject.toml 2>/dev/null && \
                quality_gates+="- [ ] Types check: \`mypy .\`"
            quality_gates="${quality_gates%$'\n'}"
            ;;
        *)
            quality_gates="- [ ] Tests pass
- [ ] Lint clean"
            ;;
    esac
    [[ -z "$quality_gates" ]] && quality_gates="- [ ] Add quality gates"

    local fix_type_label="${fix_type:-all}"

    log_info "Converting todos to fix SPEC..."
    echo ""

    # Use Claude to convert todos to SPEC format
    local conversion_prompt="Convert review findings into a SPEC.md for implementation.

PARENT SPEC: $spec_name
FIX TYPE: $fix_type_label

READ these todo files:
$abs_todo_files

CREATE the file: $fix_dir/SPEC.md

Follow this EXACT format:

---
name: ${spec_name}-fixes-${fix_type_label}
status: pending
created: $today_date
parent_spec: $spec_name
fix_type: $fix_type_label
todo_count: $todo_count
iteration_count: 0
project_type: $project_type
---

# Fix: $spec_name ($fix_type_label)

## Overview

This spec addresses $todo_count ${fix_type_label} findings from review of $spec_name.

## Requirements

[Convert each todo's Problem Statement into a requirement checkbox]

## Tasks

### Pending

#### Phase 1: Setup
- [ ] Task 1: Verify dependencies and quality gates work
  - Run: Install any missing dependencies
  - Verify: All lint/test commands execute

#### Phase 2: Fixes (ordered by priority - P1 first, then P2, then P3)

[For each todo file, create a task like this:]

- [ ] Task N: [Fix description from todo]
  - File: \`path/to/file.ts\` (from todo's Findings section)
  - Reference: \`[relative path to todo]\`
  - Acceptance:
    [Copy the Acceptance Criteria from the todo]

#### Phase 3: Verification
- [ ] Task N: Run full test suite and verify all fixes work
  - Run: Full test suite
  - Validate: All quality gates pass

### In Progress

### Completed

### Blocked

## Quality Gates

### Per-Task Gates
- [ ] Lint passes on changed files
- [ ] Types check on changed files
- [ ] Related tests pass

### Full Gates
$quality_gates

## Exit Criteria

- [ ] All requirements checked off
- [ ] All quality gates pass
- [ ] All tasks completed
- [ ] Code committed with meaningful messages

## Context

### Parent Spec
$spec_name

### Source Todos

| Priority | Todo File | Issue |
|----------|-----------|-------|
[List each todo with its priority and a brief issue description]

### Notes

These fixes originated from ${fix_type_label} review of $spec_name.
Re-run \`cr review\` after fixes to verify issues are resolved.

## Iteration Log

IMPORTANT RULES:
1. Order tasks by priority: P1 first, then P2, then P3
2. Each task should reference its source todo file
3. Copy acceptance criteria exactly from the todo files
4. Include file paths from the todo's Findings section
5. Do not add extra features - only fix the reported issues

Write the SPEC.md file now."

    # Run Claude to do the conversion
    echo "$conversion_prompt" | claude --dangerously-skip-permissions --print

    # Verify SPEC.md was created
    if [[ ! -f "$fix_dir/SPEC.md" ]]; then
        log_error "SPEC.md was not created. Please try again."
        exit 1
    fi

    # Create PROMPT.md for fix iterations
    cat > "$fix_dir/PROMPT.md" << 'FIXPROMPT'
# Ralph Loop - Fix Iteration

You are in an autonomous implementation loop fixing review findings.
Each iteration has fresh context. State persists ONLY through files.

---

## Phase 1: Orient

1. Read SPEC.md - your single source of truth
2. Read the referenced todo files for detailed context
3. Read AGENTS.md for build/test commands

---

## Phase 2: Select Task

1. If a task is "In Progress" → Continue it
2. Otherwise → Pick the first "Pending" task
3. Move task to "In Progress" BEFORE starting work

---

## Phase 3: Fix

1. Read the referenced todo file for full context
2. Implement the fix described in the todo
3. The fix should address the specific issue, nothing more
4. Run validation commands after the fix

---

## Phase 4: Validate

Run quality gates after EVERY fix:

```bash
bun lint [files-you-changed]
bun typecheck
bun test [related-tests]
```

If validation fails, fix it in the SAME iteration.

---

## Phase 5: Update State

1. Move task to "Completed" with iteration number
2. Update iteration_count in frontmatter
3. Add to "Iteration Log"

---

## Phase 6: Commit & Check Exit

1. Commit: `git commit -m "fix: [what]"`
2. Check ALL exit criteria
3. If ALL met: output `<loop-complete>All fixes complete.</loop-complete>`

---

## Completion Signal

When complete, output: `<loop-complete>All fixes complete.</loop-complete>`
FIXPROMPT

    # Create history directory
    mkdir -p "$fix_dir/.history"

    # Archive todos so they won't be re-read on next `cr fix`
    local archive_timestamp
    archive_timestamp=$(date '+%Y%m%d-%H%M%S')

    for todos_dir in "${todos_dirs[@]}"; do
        if [[ -d "$todos_dir" ]]; then
            local archive_dir="$todos_dir/_archived/$archive_timestamp"
            mkdir -p "$archive_dir"

            # Move all .md files (except in _archived) to archive
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    mv "$file" "$archive_dir/"
                fi
            done < <(find "$todos_dir" -maxdepth 1 -name "*.md" 2>/dev/null)

            log_info "Archived $(ls "$archive_dir"/*.md 2>/dev/null | wc -l | tr -d ' ') todos to ${todos_dir}/_archived/$archive_timestamp/"
        fi
    done

    log_success "Created fix spec from $todo_count todos"
    echo ""
    echo "Fix spec: $fix_dir/"
    echo ""
    echo "Next steps:"
    echo "  1. Review the spec: cat $fix_dir/SPEC.md"
    echo "  2. Implement fixes: cr implement $fix_dir"
    echo ""
}

# Legacy alias for backwards compatibility
cmd_spec_from_todos() {
    log_warn "spec-from-todos is deprecated. Use 'cr fix' instead."
    log_info "Converting to new format..."
    echo ""

    # For backwards compat, create a temporary spec and run fix
    # This won't work perfectly but gives users guidance
    log_error "Please use the new workflow:"
    echo ""
    echo "  1. Run review on a spec:  cr review specs/my-feature/"
    echo "  2. Create fix spec:       cr fix code"
    echo "  3. Implement fixes:       cr implement"
    echo ""
    exit 1
}

#=============================================================================
# COMPOUND COMMAND (Phase 6: Extract and preserve learnings)
#=============================================================================

cmd_compound() {
    local feature="$*"

    log_step "COMPOUND: Extract and Preserve Learnings"

    # Ensure knowledge directory exists
    mkdir -p "knowledge/learnings"
    mkdir -p "knowledge/patterns"

    # Find spec if feature name provided
    local spec_dir=""
    local spec_name=""
    if [[ -n "$feature" ]]; then
        # Try to find matching spec
        spec_dir=$(find "$SPECS_DIR" -maxdepth 1 -type d -name "*$feature*" 2>/dev/null | head -1)
        if [[ -n "$spec_dir" ]]; then
            spec_name=$(basename "$spec_dir")
            log_info "Found spec: $spec_name"
        fi
    fi

    # Gather context
    local existing_learnings=""
    if [[ -d "knowledge/learnings" ]] && [[ -n "$(find knowledge/learnings -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]]; then
        existing_learnings="$(printf '\n## Existing Learnings\nBuild on these:\n')$(find knowledge/learnings -maxdepth 1 -name '*.md' 2>/dev/null | while read -r f; do echo "- $f: $(head -1 "$f" | sed 's/^# //')"; done)"
    fi

    local spec_context=""
    if [[ -n "$spec_dir" ]] && [[ -f "$spec_dir/SPEC.md" ]]; then
        spec_context=$"\nRead $spec_dir/SPEC.md for implementation details and iteration log."
    fi

    echo ""
    echo -e "${CYAN}Extracting learnings from: ${feature:-recent work}${NC}"
    echo ""
    echo "This phase captures what we learned for future work."
    echo "Every feature should make subsequent features easier."
    echo ""
    echo "HARD QUESTIONS TO ANSWER:"
    echo "  - What did we learn that we'll forget in 3 months?"
    echo "  - What decisions did we make that future us will question?"
    echo "  - What patterns are emerging that should be codified?"
    echo "  - What mistakes are we at risk of repeating?"
    echo ""
    echo "Output: Learning documents in knowledge/learnings/"
    echo ""
    echo -e "${YELLOW}Starting Claude...${NC}"
    echo ""

    local compound_prompt
    compound_prompt=$(load_prompt "compound.txt")
    compound_prompt="${compound_prompt//__FEATURE__/${feature:-recent implementation work}}"
    compound_prompt="${compound_prompt//__SPEC_CONTEXT__/$spec_context}"
    compound_prompt="${compound_prompt//__EXISTING_LEARNINGS__/$existing_learnings}"
    compound_prompt="${compound_prompt//__DATE__/$(date '+%Y-%m-%d')}"
    compound_prompt="${compound_prompt//__FEATURE_SLUG__/${feature:-learnings}}"
    validate_prompt "$compound_prompt" "compound"

    # Run Claude interactively
    claude --dangerously-skip-permissions "$compound_prompt"

    echo ""
    log_success "Knowledge extraction complete!"
    echo ""

    # Check what was created
    local new_learnings
    new_learnings=$(find knowledge/learnings -maxdepth 1 -name "*.md" -mmin -5 2>/dev/null | wc -l)
    local new_patterns
    new_patterns=$(find knowledge/patterns -maxdepth 1 -name "*.md" -mmin -5 2>/dev/null | wc -l)

    if [[ $new_learnings -gt 0 ]] || [[ $new_patterns -gt 0 ]]; then
        log_success "Created $new_learnings learning(s) and $new_patterns pattern(s)"
        echo ""
        echo "Review your new knowledge:"
        find knowledge/learnings -maxdepth 1 -name "*.md" -mmin -5 2>/dev/null | while read -r f; do echo "  - $f"; done
        find knowledge/patterns -maxdepth 1 -name "*.md" -mmin -5 2>/dev/null | while read -r f; do echo "  - $f"; done
    else
        log_info "No new documents created. You can add learnings manually."
    fi

    echo ""
    echo "This feature has compounded - future work will be easier."
    echo ""
    echo "The full workflow:"
    echo "  CONVERSE → RESEARCH → PLAN → IMPLEMENT → REVIEW → COMPOUND ✓"
    echo ""
}

#=============================================================================
# DESIGN COMMAND
#=============================================================================

detect_dev_server() {
    # 1. Check .cr/project.json for configured dev_url first
    if [[ -f ".cr/project.json" ]] && command -v jq &>/dev/null; then
        local stored_url
        stored_url=$(jq -r '.dev_url // empty' .cr/project.json 2>/dev/null)
        if [[ -n "$stored_url" ]] && curl -s --connect-timeout 1 "$stored_url" > /dev/null 2>&1; then
            echo "$stored_url"
            return 0
        fi
    fi

    # 2. Prioritize port based on detected project type
    local priority_port=""
    local ports=()

    # Detect framework and try to extract custom port from config
    if ls astro.config.* 2>/dev/null | grep -q .; then
        # Try to extract port from astro.config.mjs/ts
        local astro_config
        astro_config=$(ls astro.config.* 2>/dev/null | head -1)
        if [[ -n "$astro_config" ]]; then
            # Look for server.port or port: in config
            local custom_port
            custom_port=$(grep -oE 'port["\s]*:["\s]*[0-9]+' "$astro_config" 2>/dev/null | grep -oE '[0-9]+' | head -1)
            if [[ -n "$custom_port" ]]; then
                priority_port="$custom_port"
            else
                priority_port=4321  # Astro default
            fi
        fi
    elif ls next.config.* 2>/dev/null | grep -q .; then
        priority_port=3000  # Next.js default
    elif ls vite.config.* 2>/dev/null | grep -q .; then
        # Try to extract port from vite.config
        local vite_config
        vite_config=$(ls vite.config.* 2>/dev/null | head -1)
        if [[ -n "$vite_config" ]]; then
            local custom_port
            custom_port=$(grep -oE 'port["\s]*:["\s]*[0-9]+' "$vite_config" 2>/dev/null | grep -oE '[0-9]+' | head -1)
            if [[ -n "$custom_port" ]]; then
                priority_port="$custom_port"
            else
                priority_port=5173  # Vite default
            fi
        fi
    elif ls nuxt.config.* 2>/dev/null | grep -q .; then
        priority_port=3000  # Nuxt default
    elif [[ -f "svelte.config.js" ]]; then
        priority_port=5173  # SvelteKit default
    elif [[ -f "angular.json" ]]; then
        priority_port=4200  # Angular default
    elif [[ -f "bin/rails" ]]; then
        priority_port=3000  # Rails default
    fi

    # 3. Build port list with priority port first
    if [[ -n "$priority_port" ]]; then
        ports=("$priority_port")
    fi

    # Add common ports and their variants (some tools auto-increment if port is busy)
    for p in 4321 4322 4323 4324 4325 4326 5173 5174 5175 5176 3000 3001 3002 8080 8081 8000 8001 4000 4001 4200 4201; do
        if [[ "$p" != "$priority_port" ]]; then
            ports+=("$p")
        fi
    done

    for port in "${ports[@]}"; do
        if curl -s --connect-timeout 1 "http://localhost:$port" > /dev/null 2>&1; then
            echo "http://localhost:$port"
            return 0
        fi
    done

    return 1
}

cmd_design() {
    local url=""
    local max_iterations=50  # Safety limit
    local force_iterations=false
    local continue_session=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --n)
                max_iterations="$2"
                force_iterations=true
                shift 2
                ;;
            --continue)
                continue_session=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                log_error "Usage: cr design [url] [--n iterations] [--continue]"
                exit 1
                ;;
            *)
                if [[ -z "$url" ]]; then
                    url="$1"
                fi
                shift
                ;;
        esac
    done

    log_step "Design Improvement Loop"

    # Auto-detect dev server if no URL provided
    if [[ -z "$url" ]]; then
        log_info "No URL provided, detecting dev server..."
        url=$(detect_dev_server)
        if [[ -z "$url" ]]; then
            log_error "No dev server detected. Start your dev server or provide a URL:"
            log_error "  cr design http://localhost:3000"
            log_error "  cr design http://localhost:5173 10"
            exit 1
        fi
        log_success "Found dev server at $url"
    fi

    # Validate URL is reachable
    if ! curl -s --connect-timeout 3 "$url" > /dev/null 2>&1; then
        log_error "Cannot reach $url - is your dev server running?"
        exit 1
    fi

    echo ""
    echo "URL:        $url"
    if [[ "$force_iterations" == "true" ]]; then
        echo "Iterations: $max_iterations (forced)"
        echo "Mode:       Forced (will run exactly $max_iterations iterations)"
    elif [[ "$continue_session" == "true" ]]; then
        echo "Mode:       Continue (resuming last session until all pages done)"
    else
        echo "Mode:       Auto (one page per iteration until all pages done)"
    fi
    echo ""
    echo "This will:"
    echo "  1. Discover ALL pages (nav, header, footer links)"
    echo "  2. Fix ONE page per iteration"
    echo "  3. Apply /frontend-design skill for distinctive design"
    echo "  4. Continue until all pages are polished"
    echo ""
    echo "Press Ctrl+C to stop at any time."
    echo ""

    # Create design history directory
    local design_dir="design-iterations"
    mkdir -p "$design_dir"

    local session_dir=""
    local state_file=""
    local starting_iteration=0

    # Handle --continue: find and resume last session
    if [[ "$continue_session" == "true" ]]; then
        # Find the most recent session directory
        local last_session
        last_session=$(ls -1t "$design_dir" 2>/dev/null | head -1)

        if [[ -z "$last_session" ]] || [[ ! -d "$design_dir/$last_session" ]]; then
            log_error "No previous session found to continue."
            log_error "Run 'cr design' first to create a session."
            exit 1
        fi

        session_dir="$design_dir/$last_session"
        state_file="$session_dir/DESIGN-STATE.md"

        if [[ ! -f "$state_file" ]]; then
            log_error "No DESIGN-STATE.md found in $session_dir"
            exit 1
        fi

        # Count existing iteration logs to determine starting point
        local existing_iterations
        existing_iterations=$(ls -1 "$session_dir"/*.md 2>/dev/null | grep -c "design.md" || echo "0")
        starting_iteration=$existing_iterations

        log_info "Continuing session: $session_dir"
        log_info "Previous iterations: $starting_iteration"

        # Count pending pages/views
        local pending_count
        pending_count=$(grep -c '^\- \[ \]' "$state_file" 2>/dev/null || echo "?")
        local complete_count
        complete_count=$(grep -c '^\- \[x\]' "$state_file" 2>/dev/null || echo "0")

        log_info "Complete: $complete_count, Pending: $pending_count (pages + view states)"
        echo ""

        # Show pending pages/views
        local pending_items
        pending_items=$(grep '^\- \[ \]' "$state_file" 2>/dev/null || true)
        if [[ -n "$pending_items" ]]; then
            echo "Pending pages/views:"
            echo "$pending_items"
            echo ""
        fi
    else
        # Create new session
        local timestamp
        timestamp=$(date '+%Y%m%d-%H%M%S')
        session_dir="$design_dir/$timestamp"
        mkdir -p "$session_dir"

        log_info "Design session: $session_dir"
        echo ""

        # Create persistent design state file
        state_file="$session_dir/DESIGN-STATE.md"
        cat > "$state_file" << 'STATE_EOF'
# Design State

This file tracks progress across design iterations. ONE page/view per iteration.

## Pages & View States to Update

<!-- After discovering pages AND view states, list them here with checkboxes -->
<!-- Example:
- [ ] / (Landing page)
- [ ] /dashboard:focus (Dashboard - Focus view)
- [ ] /dashboard:tree (Dashboard - Tree view)
- [ ] /dashboard:compare (Dashboard - Compare view)
- [ ] /dashboard:gallery (Dashboard - Gallery view)
- [ ] /dashboard:statistics (Dashboard - Statistics view)
- [ ] /dashboard:sidebar-collapsed (Dashboard - Collapsed sidebar)
-->

Pages/views not yet discovered. Run iteration 1 to crawl and populate this list.

## Global Styles (Iteration 1)

<!-- Document global CSS/component changes that affect all pages -->

## Changes by Page

<!-- Log what was changed for each page -->

## Notes

<!-- Any issues or observations -->
STATE_EOF
    fi

    local iteration=$starting_iteration

    while [[ $iteration -lt $max_iterations ]]; do
        iteration=$((iteration + 1))
        local iter_timestamp
        iter_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Check if there are still pending pages/views (skip on iteration 1 - not discovered yet)
        if [[ $iteration -gt 1 ]] && [[ -f "$state_file" ]]; then
            local pending_pages
            pending_pages=$(grep -c '^\- \[ \]' "$state_file" 2>/dev/null || echo "0")
            if [[ "$pending_pages" -eq 0 ]]; then
                # Double-check by looking for the completion tag wasn't already output
                if grep -q '\[x\]' "$state_file" 2>/dev/null; then
                    echo ""
                    log_success "All pages/views complete! Design polished after $((iteration - 1)) iterations."
                    echo ""
                    echo "Screenshots saved in: $session_dir/"
                    echo ""
                    echo "Next steps:"
                    echo "  1. Review the changes: git diff"
                    echo "  2. Run code review: cr review"
                    echo "  3. Commit if satisfied: git add -A && git commit -m 'style: polish UI design'"
                    echo ""
                    exit 0
                fi
            fi
        fi

        echo ""
        echo -e "${CYAN}${BOLD}=== Design Iteration $iteration (page $iteration) - $iter_timestamp ===${NC}"
        echo ""

        # Log file for this iteration
        local log_file="$session_dir/$(printf '%02d' $iteration)-design.md"

        # Build context from previous iteration
        local prev_context=""
        if [[ $iteration -gt 1 ]]; then
            local prev_log="$session_dir/$(printf '%02d' $((iteration - 1)))-design.md"
            if [[ -f "$prev_log" ]]; then
                # Extract summary from previous iteration (last 50 lines or key sections)
                local prev_summary
                prev_summary=$(tail -100 "$prev_log" | head -80)
                prev_context="
## Context from Previous Iteration

The previous iteration (iteration $((iteration - 1))) made these changes:

\`\`\`
$prev_summary
\`\`\`

IMPORTANT: Review what was done above. Build on these changes, don't undo them.
If issues were introduced, fix them. If improvements were made, maintain them.
"
            fi
        fi

        # Create the design prompt - ONE PAGE PER ITERATION
        local design_prompt="You are in iteration $iteration of a design improvement loop.

THIS ITERATION: Focus on ONE page only. Do not try to fix all pages at once.

TARGET URL: $url
STATE FILE: $state_file
SCREENSHOT DIR: $session_dir/
$prev_context
## Step 1: Read State & Identify Target Page

Read the state file:
\`\`\`bash
cat $state_file
\`\`\`

**If iteration 1 (pages/views not yet discovered):**
1. Crawl the site to discover all URL-based pages:
\`\`\`bash
agent-browser open $url
agent-browser eval \"Array.from(document.querySelectorAll('nav a, header a, footer a, [role=navigation] a, main a')).map(a => a.href).filter(h => h && h.startsWith(window.location.origin)).filter((v,i,a) => a.indexOf(v) === i)\"
\`\`\`

2. For EACH page, discover SPA view states:
\`\`\`bash
agent-browser snapshot -i  # Look for tabs, view switchers, sidebars
# Try keyboard shortcuts 1-5 to find view modes
agent-browser press 1
agent-browser snapshot -i  # Did view change?
agent-browser press 2
agent-browser snapshot -i  # Did view change?
# Continue until no more views
\`\`\`

3. Update the state file with ALL pages AND view states (mark all as [ ] pending):
   - Simple pages: \`- [ ] / (Landing)\`
   - SPA views: \`- [ ] /dashboard:focus (Dashboard - Focus view)\`
   - SPA views: \`- [ ] /dashboard:tree (Dashboard - Tree view)\`
   - Sidebar states: \`- [ ] /dashboard:sidebar-collapsed\`

4. Your target for this iteration is the FIRST item in the list

**If iteration 2+:**
1. Find the FIRST item marked [ ] (pending) in the state file
2. That is your ONE target page/view for this iteration
3. If it's a view state (has : in it), navigate to the page then activate that view

## Step 2: Screenshot Target Page/View (All Viewports)

Screenshot ONLY your target page/view at all viewport sizes:
\`\`\`bash
# Navigate to page
agent-browser open [target-page-url]

# If target is a view state (e.g., /dashboard:tree), activate it:
# - Press keyboard shortcut (1-5) or click the view tab
agent-browser press 2  # Example: activate tree view

agent-browser resize 1920 1080
agent-browser screenshot $session_dir/before-iter$iteration-[page-name]-[view]-1920.png

agent-browser resize 1440 900
agent-browser screenshot $session_dir/before-iter$iteration-[page-name]-[view]-1440.png

agent-browser resize 1024 768
agent-browser screenshot $session_dir/before-iter$iteration-[page-name]-[view]-1024.png

agent-browser resize 375 812
agent-browser screenshot $session_dir/before-iter$iteration-[page-name]-[view]-375.png
\`\`\`

Naming examples:
- \`before-iter3-landing-1920.png\` (simple page)
- \`before-iter3-dashboard-tree-1920.png\` (view state)
- \`before-iter3-dashboard-sidebar-collapsed-375.png\` (sidebar state)

## Step 3: Analyze Target Page/View

For your ONE target page/view, evaluate at each viewport:
- Is it bland, generic, or 'AI-looking'?
- Typography: hierarchy, font choices, spacing
- Color: too much gray? No personality?
- Layout: does it work at all viewport sizes?
- Responsive: text compression at large widths? Layout breaks?

## Step 4: Apply /frontend-design Philosophy

Make this ONE page distinctive:
- Bold, intentional choices (not safe defaults)
- Typography, color, spacing, visual rhythm
- Personality and craft
- Consistent with any global styles already established

**If iteration 1:** Also establish global styles (CSS variables, shared components) that will apply to all pages.

## Step 5: Make Improvements to Target Page

Fix the issues identified. For iteration 1, include global style changes.
Run any build/dev commands if needed.

## Step 6: Screenshot After (Target Page/View Only)

\`\`\`bash
agent-browser open [target-page-url]
# If view state, activate it again (press shortcut or click tab)

agent-browser resize 1920 1080
agent-browser screenshot $session_dir/after-iter$iteration-[page-name]-[view]-1920.png

agent-browser resize 1440 900
agent-browser screenshot $session_dir/after-iter$iteration-[page-name]-[view]-1440.png

agent-browser resize 1024 768
agent-browser screenshot $session_dir/after-iter$iteration-[page-name]-[view]-1024.png

agent-browser resize 375 812
agent-browser screenshot $session_dir/after-iter$iteration-[page-name]-[view]-375.png
\`\`\`

## Step 7: Compare Before/After

View both screenshots to verify improvement:
\`\`\`bash
cat $session_dir/before-iter$iteration-[page-name]-[view]-1920.png
cat $session_dir/after-iter$iteration-[page-name]-[view]-1920.png
\`\`\`

Check for:
- Visible improvement in design
- No regressions (text compression, layout breaks)
- Works at all viewport sizes

If issues found, fix them before proceeding.

## Step 8: Update State File

Mark your target page/view as complete and log changes:
\`\`\`bash
cat $state_file
# Then use Edit tool to update it
\`\`\`

Change the item from [ ] to [x] and add to Changes Made section:
- What you changed on this page/view
- Any global styles added (iteration 1)

## Step 9: Check Completion

Read the updated state file. If ALL pages/views are marked [x] complete:
Output: <design-complete>Design polished.</design-complete>

If there are still [ ] pending items, do NOT output the completion tag.
The next iteration will handle the next page/view.

IMPORTANT:
- ONE page/view per iteration - do not try to do multiple
- Iteration 1 should discover ALL pages AND view states (SPA-aware)
- Iteration 1 should also establish global styles
- View states on same page share CSS, so later views may need less work
- Always verify all 4 viewport sizes (1920, 1440, 1024, 375)
- Update state file before finishing so next iteration knows progress

Start by reading $state_file to find your target page/view for this iteration."

        # Initialize log file
        {
            echo "# Design Iteration $iteration"
            echo "Started: $iter_timestamp"
            echo "URL: $url"
            echo ""
            echo "## Output"
            echo ""
        } > "$log_file"

        # Run the design iteration
        if ! run_claude_with_retry "$design_prompt" "$log_file"; then
            log_warn "Iteration $iteration had issues. Continuing..."
            sleep 2
            continue
        fi

        # Check for completion signal (only exit early if not forced)
        # Match full tag with closing to avoid false positives
        if grep -qE "<design-complete>.*</design-complete>" "$log_file"; then
            if [[ "$force_iterations" == "true" ]]; then
                log_info "Design marked as polished, but continuing (--n forced $max_iterations iterations)"
            else
                echo ""
                log_success "All pages/views polished after $iteration iterations!"
                echo ""
                echo "Screenshots saved in: $session_dir/"
                echo ""
                echo "Next steps:"
                echo "  1. Review the changes: git diff"
                echo "  2. Run code review: cr review"
                echo "  3. Commit if satisfied: git add -A && git commit -m 'style: polish UI design'"
                echo ""
                exit 0
            fi
        fi

        # Brief pause between iterations
        log_info "Pausing before next iteration..."
        sleep 3
    done

    echo ""
    log_warn "Reached max iterations ($max_iterations). Some pages may still need work."
    echo ""
    # Show remaining pages
    if [[ -f "$state_file" ]]; then
        local remaining
        remaining=$(grep '^\- \[ \]' "$state_file" 2>/dev/null || true)
        if [[ -n "$remaining" ]]; then
            echo "Pages still pending:"
            echo "$remaining"
            echo ""
        fi
    fi
    echo "Options:"
    echo "  1. Continue: cr design --continue"
    echo "  2. Review changes: git diff"
    echo "  3. Run code review: cr review --design"
    echo ""
}

#=============================================================================
# STATUS COMMAND
#=============================================================================

cmd_status() {
    log_step "Compound Ralph Status"

    if [[ ! -d "$SPECS_DIR" ]]; then
        log_warn "No specs directory found. Run 'cr init' first."
        exit 0
    fi

    local specs_found=0

    echo "Spec                          Status      Iterations  Tasks"
    echo "----                          ------      ----------  -----"

    for spec_file in "$SPECS_DIR"/*/SPEC.md; do
        [[ -f "$spec_file" ]] || continue
        specs_found=$((specs_found + 1))

        local spec_dir
        spec_dir=$(dirname "$spec_file")
        local spec_name
        spec_name=$(basename "$spec_dir")

        # Extract metadata
        local status iteration_count
        status=$(grep "^status:" "$spec_file" | cut -d: -f2 | tr -d ' ' || echo "unknown")
        iteration_count=$(grep "^iteration_count:" "$spec_file" | cut -d: -f2 | tr -d ' ' || echo "0")

        # Count tasks
        local pending completed
        pending=$(grep -c "^\- \[ \]" "$spec_file" 2>/dev/null || true)
        completed=$(grep -c "^\- \[x\]" "$spec_file" 2>/dev/null || true)
        # Default to 0 if empty
        pending=${pending:-0}
        completed=${completed:-0}

        # Color-code status
        local status_display
        case "$status" in
            complete)  status_display="${GREEN}$status${NC}" ;;
            building)  status_display="${YELLOW}$status${NC}" ;;
            blocked)   status_display="${RED}$status${NC}" ;;
            *)         status_display="$status" ;;
        esac

        printf "%-30s %-18b %-12s %s/%s\n" "$spec_name" "$status_display" "$iteration_count" "$completed" "$((completed + pending))"
    done

    if [[ $specs_found -eq 0 ]]; then
        echo "(no specs found)"
    fi

    echo ""
}

#=============================================================================
# LEARNINGS COMMAND
#=============================================================================

cmd_learnings() {
    local category="${1:-}"
    local limit="${2:-20}"

    log_step "Project Learnings"

    if [[ ! -f ".cr/learnings.json" ]]; then
        log_warn "No learnings found. Run 'cr implement' to generate learnings."
        exit 0
    fi

    if [[ -n "$category" ]]; then
        echo "Category: $category (last $limit)"
        echo "---"
        get_learnings_summary "$category" "$limit"
    else
        echo "All categories (last $limit)"
        echo "---"
        get_learnings_summary "" "$limit"
    fi

    echo ""
    echo "Categories: environment, pattern, gotcha, fix, discovery, iteration_failure"
    echo "Usage: cr learnings [category] [limit]"
}

#=============================================================================
# RESET CONTEXT COMMAND
#=============================================================================

cmd_reset_context() {
    local spec_dir="${1:-}"

    if [[ -z "$spec_dir" ]]; then
        log_error "Usage: cr reset-context <spec-dir>"
        log_info "Example: cr reset-context specs/feat-task-manager/"
        exit 1
    fi

    # Normalize path
    spec_dir="${spec_dir%/}"  # Remove trailing slash
    if [[ ! -d "$spec_dir" ]]; then
        log_error "Spec directory not found: $spec_dir"
        exit 1
    fi

    local prompt_file="$spec_dir/PROMPT.md"
    if [[ ! -f "$prompt_file" ]]; then
        log_error "PROMPT.md not found in $spec_dir"
        exit 1
    fi

    log_warn "This will reset all accumulated context in $spec_dir/PROMPT.md"
    log_warn "Use this when the agent has learned harmful patterns (e.g., skipping quality gates)"
    echo ""

    # Create backup
    cp "$prompt_file" "$prompt_file.backup.$(date +%Y%m%d-%H%M%S)"
    log_info "Created backup of PROMPT.md"

    # Replace the context between markers with fresh empty context
    if grep -q "<!-- CONTEXT_START -->" "$prompt_file" 2>/dev/null; then
        local fresh_context="## Accumulated Context (from previous iterations)

### Learnings
(No learnings yet - this context was reset)

### Errors You've Fixed Before (Don't Repeat)
(None yet)

### Patterns Discovered in This Codebase
(None yet)"

        # Write fresh context to temp file
        local ctx_temp
        ctx_temp=$(mktemp)
        printf '%s\n' "$fresh_context" > "$ctx_temp"

        # Use awk to replace content between markers
        awk -v ctxfile="$ctx_temp" '
            BEGIN {
                while ((getline line < ctxfile) > 0) {
                    ctx = ctx (ctx ? "\n" : "") line
                }
                close(ctxfile)
            }
            /<!-- CONTEXT_START -->/ {
                print
                print ctx
                skip = 1
                next
            }
            /<!-- CONTEXT_END -->/ {
                skip = 0
            }
            !skip { print }
        ' "$prompt_file" > "$prompt_file.tmp" && mv "$prompt_file.tmp" "$prompt_file"

        rm -f "$ctx_temp"
        log_success "Reset accumulated context in PROMPT.md"
    else
        log_warn "No context markers found in PROMPT.md - nothing to reset"
    fi

    # Also reset .cr/learnings.json if it exists and relates to this spec
    local learnings_file=".cr/learnings.json"
    if [[ -f "$learnings_file" ]] && command -v jq &>/dev/null; then
        local spec_name
        spec_name=$(basename "$spec_dir")
        # Filter out learnings for this spec that contain harmful patterns
        jq --arg spec "$spec_name" '
            .learnings = [.learnings[] | select(
                (.spec != $spec) or
                ((.learning | test("pre-existing|skip|ignore|dismiss"; "i")) | not)
            )]
        ' "$learnings_file" > "$learnings_file.tmp" && mv "$learnings_file.tmp" "$learnings_file"
        log_info "Cleaned harmful learnings from .cr/learnings.json"
    fi

    log_success "Context reset complete"
    log_info "The agent will start fresh without harmful learned patterns"
    log_info "Run 'cr implement $spec_dir' to continue"
}

#=============================================================================
# HELP COMMAND
#=============================================================================

#=============================================================================
# TEST-GEN COMMAND (Generate E2E tests from feature specs)
#=============================================================================

cmd_test_gen() {
    local spec_file=""
    local output_file=""
    local example_dir="test/specs"
    local dry_run=false
    local process_all=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            --example-tests)
                example_dir="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --all)
                process_all=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: cr test-gen <spec-file> [--output <file>] [--dry-run]"
                exit 1
                ;;
            *)
                spec_file="$1"
                shift
                ;;
        esac
    done

    # Validate input
    if [[ -z "$spec_file" ]]; then
        log_error "Usage: cr test-gen <spec-file> [options]"
        log_error ""
        log_error "Options:"
        log_error "  -o, --output <file>    Output test file path"
        log_error "  --example-tests <dir>  Directory with example tests (default: test/specs)"
        log_error "  --dry-run              Show generated code without writing"
        log_error "  --all                  Process all SPEC.md files in directory"
        log_error ""
        log_error "Examples:"
        log_error "  cr test-gen specs/onboarding/SPEC.md"
        log_error "  cr test-gen specs/settings/SPEC.md -o test/specs/settings.e2e.js"
        exit 1
    fi

    # Handle --all flag (process directory)
    # Note: --all currently only passes --dry-run to recursive calls.
    # Custom --output or --example-tests are not propagated (uses defaults per spec).
    if [[ "$process_all" == true ]]; then
        if [[ ! -d "$spec_file" ]]; then
            log_error "With --all, argument must be a directory: $spec_file"
            exit 1
        fi
        
        log_step "Processing all specs in $spec_file"
        find "$spec_file" -name "SPEC.md" | while read -r spec; do
            log_info "Processing: $spec"
            cmd_test_gen "$spec" ${dry_run:+--dry-run}
        done
        return 0
    fi

    # Validate spec file exists
    if [[ ! -f "$spec_file" ]]; then
        log_error "Spec file not found: $spec_file"
        exit 1
    fi

    log_step "Generating E2E Tests from: $spec_file"

    # Derive output filename if not specified
    # Assumption: spec files typically follow specs/<feature>/SPEC.md structure.
    # For non-standard paths, use --output to specify explicitly.
    if [[ -z "$output_file" ]]; then
        # Extract feature name from path: specs/feature-name/SPEC.md -> feature-name
        local feature_name
        feature_name=$(dirname "$spec_file" | xargs basename)
        output_file="test/specs/${feature_name}.e2e.js"
        
        # Handle case where spec is directly named (not in subdirectory)
        if [[ "$feature_name" == "." ]] || [[ "$feature_name" == "specs" ]]; then
            feature_name=$(basename "$spec_file" .md | tr '[:upper:]' '[:lower:]')
            output_file="test/specs/${feature_name}.e2e.js"
        fi
    fi

    log_info "Output: $output_file"

    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"

    # Gather context
    local spec_content
    spec_content=$(cat "$spec_file")

    # Gather example tests for pattern learning
    # Limit to 2 examples to stay within context limits while providing pattern diversity
    local example_tests=""
    if [[ -d "$example_dir" ]]; then
        local example_count=0
        while IFS= read -r -d '' example_file; do
            example_tests+=$'\n\n--- Example: '"$example_file"$' ---\n'
            example_tests+=$(cat "$example_file")
            example_count=$((example_count + 1))
            if [[ $example_count -ge 2 ]]; then
                break
            fi
        done < <(find "$example_dir" -maxdepth 1 -name "*.e2e.js" -print0 2>/dev/null)
    fi

    if [[ -z "$example_tests" ]]; then
        log_warn "No example tests found in $example_dir"
        example_tests="No example tests available. Use standard WebdriverIO patterns."
    fi

    # Load wdio config summary
    local wdio_config="WebdriverIO with tauri-driver. Mocha framework, BDD style. 60s timeout."
    if [[ -f "wdio.conf.js" ]]; then
        wdio_config+=$'\n'"$(grep -E 'timeout|port|framework' wdio.conf.js 2>/dev/null || true)"
    fi

    # Load test conventions
    local test_conventions=""
    local conventions_file="$CR_DIR/templates/TEST-conventions.md"
    if [[ -f "$conventions_file" ]]; then
        test_conventions=$(cat "$conventions_file")
    else
        test_conventions="Use standard WebdriverIO patterns. See wdio.dev documentation."
    fi

    # Build prompt from template
    local prompt_template="$CR_DIR/prompts/test-gen.txt"
    local prompt

    if [[ ! -f "$prompt_template" ]]; then
        log_error "Prompt template not found: $prompt_template"
        log_error "Expected prompts/test-gen.txt to exist in CR_DIR"
        exit 1
    fi

    # Placeholders use __DOUBLE_UNDERSCORE__ convention (see prompts/ convention from PR #17)
    # Using bash ${//} for substitution is sufficient with this placeholder style because:
    # - __PLACEHOLDER__ pattern won't appear naturally in specs/code content
    # - No external dependencies (awk) required
    # - Handles special characters safely (backslashes, quotes, etc.)
    prompt=$(cat "$prompt_template")
    prompt="${prompt//__SPEC_CONTENT__/$spec_content}"
    prompt="${prompt//__EXAMPLE_TESTS__/$example_tests}"
    prompt="${prompt//__WDIO_CONFIG__/$wdio_config}"
    prompt="${prompt//__TEST_CONVENTIONS__/$test_conventions}"

    echo ""
    echo -e "${CYAN}Generating tests with Claude...${NC}"
    echo ""

    local temp_output
    temp_output=$(mktemp)
    trap "rm -f '$temp_output'" RETURN

    # Call Claude to generate tests
    echo "$prompt" | claude --dangerously-skip-permissions --print > "$temp_output" 2>&1
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Claude failed with exit code $exit_code"
        cat "$temp_output"
        exit 1
    fi

    local generated_code
    generated_code=$(cat "$temp_output")

    # Strip any markdown code fences if Claude included them
    # TODO: Markdown stripping is simple - only handles ```javascript, ```js, ``` patterns.
    # If Claude uses unusual fence syntax (~~~, capital letters), this may not strip them.
    # Current approach is sufficient for typical Claude output; add patterns if needed.
    generated_code=$(echo "$generated_code" | sed '/^```javascript$/d' | sed '/^```js$/d' | sed '/^```$/d')

    # Basic sanity check - code should not be empty
    if [[ -z "$generated_code" ]]; then
        log_error "Generated output is empty"
        exit 1
    fi

    if [[ "$dry_run" == true ]]; then
        log_info "=== DRY RUN - Would write to: $output_file ==="
        echo ""
        echo "$generated_code"
        echo ""
        log_info "=== END DRY RUN ==="
        return 0
    fi

    # Write the file
    echo "$generated_code" > "$output_file"
    log_success "Generated: $output_file"

    # Syntax check
    if command -v node &> /dev/null; then
        if node --check "$output_file" 2>/dev/null; then
            log_success "Syntax check passed"
        else
            log_warn "Syntax check failed - review generated code"
            node --check "$output_file" 2>&1 | head -10
        fi
    fi

    # Show summary
    local line_count
    line_count=$(wc -l < "$output_file")
    local test_count
    test_count=$(grep -c "it(" "$output_file" || echo "0")
    
    echo ""
    log_info "Summary:"
    echo "  Lines: $line_count"
    echo "  Tests: $test_count it() blocks"
    echo "  Output: $output_file"
    echo ""
    echo "Run tests with:"
    echo "  npm test -- --spec $output_file"
}

#=============================================================================
# INIT-TESTS COMMAND (Set up WebdriverIO E2E testing infrastructure)
#=============================================================================

cmd_init_tests() {
    local project_type="tauri"  # Currently only supports Tauri apps
    local test_dir="test/e2e"
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --test-dir)
                test_dir="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: cr init-tests [--force] [--test-dir <dir>]"
                exit 1
                ;;
            *)
                shift
                ;;
        esac
    done

    log_step "Initializing E2E test infrastructure"

    # Check if already initialized
    if [[ -f "wdio.conf.js" ]] && [[ "$force" != true ]]; then
        log_warn "wdio.conf.js already exists. Use --force to overwrite."
        exit 1
    fi

    # Detect package manager
    local pkg_manager="npm"
    if [[ -f "pnpm-lock.yaml" ]]; then
        pkg_manager="pnpm"
    elif [[ -f "yarn.lock" ]]; then
        pkg_manager="yarn"
    fi
    log_info "Detected package manager: $pkg_manager"

    # Check for Tauri project
    if [[ ! -d "src-tauri" ]]; then
        log_warn "No src-tauri directory found. This command is designed for Tauri apps."
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Detect binary name from Cargo.toml
    local binary_name="app"
    if [[ -f "src-tauri/Cargo.toml" ]]; then
        binary_name=$(grep -E "^name\s*=" src-tauri/Cargo.toml | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ')
        log_info "Detected binary name: $binary_name"
    fi

    # Create test directory
    mkdir -p "$test_dir"
    log_success "Created $test_dir/"

    # Create wdio.conf.js
    cat > wdio.conf.js << 'WDIOCONF'
import os from "os";
import path from "path";
import { spawn } from "child_process";
import { fileURLToPath } from "url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));

let tauriDriver;
let exit = false;

export const config = {
  host: "127.0.0.1",
  port: 4444,
  specs: ["./test/e2e/**/*.e2e.js"],
  maxInstances: 1,
  capabilities: [
    {
      maxInstances: 1,
      "tauri:options": {
        application: path.resolve(__dirname, "src-tauri/target/debug/BINARY_NAME"),
      },
    },
  ],
  reporters: ["spec"],
  framework: "mocha",
  mochaOpts: {
    ui: "bdd",
    timeout: 60000,
  },

  beforeSession: () => {
    tauriDriver = spawn(
      path.resolve(os.homedir(), ".cargo", "bin", "tauri-driver"),
      [],
      { stdio: [null, process.stdout, process.stderr] }
    );

    tauriDriver.on("error", (error) => {
      console.error("tauri-driver error:", error);
      process.exit(1);
    });
    tauriDriver.on("exit", (code) => {
      if (!exit) {
        console.error("tauri-driver exited with code:", code);
        process.exit(1);
      }
    });
  },

  afterSession: () => {
    exit = true;
    tauriDriver?.kill();
  },
};

function onShutdown(fn) {
  const cleanup = () => { try { fn(); } finally { process.exit(); } };
  ["exit", "SIGINT", "SIGTERM", "SIGHUP", "SIGBREAK"].forEach(sig => process.on(sig, cleanup));
}
onShutdown(() => { exit = true; tauriDriver?.kill(); });
WDIOCONF

    # Replace placeholder with actual binary name
    # Escape characters that are special in sed replacement (/ & \)
    local escaped_binary_name
    escaped_binary_name=$(printf '%s' "$binary_name" | sed 's/[\/&\\]/\\&/g')
    sed "s/BINARY_NAME/$escaped_binary_name/g" wdio.conf.js > wdio.conf.js.tmp && mv wdio.conf.js.tmp wdio.conf.js
    log_success "Created wdio.conf.js"

    # Create smoke test
    cat > "$test_dir/smoke.e2e.js" << 'SMOKETEST'
/**
 * Smoke test - verify E2E infrastructure works
 */
describe("Smoke Test", () => {
  it("should launch the app", async () => {
    const body = await $("body");
    await body.waitForExist({ timeout: 10000 });
    expect(await body.isExisting()).toBe(true);
  });

  it("should have content", async () => {
    const text = await $("body").getText();
    console.log("App content (first 200 chars):", text.slice(0, 200));
    expect(text.length).toBeGreaterThan(0);
  });
});
SMOKETEST
    log_success "Created $test_dir/smoke.e2e.js"

    # Create helper script
    mkdir -p scripts
    cat > scripts/run-e2e.sh << 'RUNSCRIPT'
#!/bin/bash
# Run E2E tests with WebdriverIO and tauri-driver
set -e

if [[ -z "$DISPLAY" ]]; then
    echo "No DISPLAY set. Starting Xvfb..."
    Xvfb :99 -screen 0 1280x1024x24 &
    XVFB_PID=$!
    export DISPLAY=:99
    sleep 2
    trap "kill $XVFB_PID 2>/dev/null" EXIT
fi

echo "Running E2E tests with DISPLAY=$DISPLAY"

if ! command -v tauri-driver &> /dev/null; then
    echo "Error: tauri-driver not found. Install: cargo install tauri-driver"
    exit 1
fi

BINARY="src-tauri/target/debug/$(grep -oP 'application:.*debug/\K[^"]+' wdio.conf.js 2>/dev/null || echo 'app')"
if [[ ! -f "$BINARY" ]]; then
    echo "Warning: Binary not found at $BINARY"
    echo "Build with: cd src-tauri && cargo build"
fi

npx wdio run wdio.conf.js "$@"
RUNSCRIPT
    chmod +x scripts/run-e2e.sh
    log_success "Created scripts/run-e2e.sh"

    # Install dependencies
    log_step "Installing WebdriverIO dependencies..."
    case "$pkg_manager" in
        pnpm)
            pnpm add -D @wdio/cli @wdio/local-runner @wdio/mocha-framework @wdio/spec-reporter 2>&1 | tail -5
            ;;
        yarn)
            yarn add -D @wdio/cli @wdio/local-runner @wdio/mocha-framework @wdio/spec-reporter 2>&1 | tail -5
            ;;
        *)
            npm install -D @wdio/cli @wdio/local-runner @wdio/mocha-framework @wdio/spec-reporter 2>&1 | tail -5
            ;;
    esac
    log_success "Installed WebdriverIO dependencies"

    # Add npm scripts to package.json
    if command -v jq &> /dev/null && [[ -f "package.json" ]]; then
        local tmp_pkg
        tmp_pkg=$(mktemp)
        jq '.scripts["test:e2e"] = "wdio run wdio.conf.js" | .scripts["test:e2e:headless"] = "DISPLAY=:99 wdio run wdio.conf.js"' package.json > "$tmp_pkg"
        mv "$tmp_pkg" package.json
        log_success "Added test:e2e scripts to package.json"
    else
        log_warn "Could not update package.json (jq not found). Add manually:"
        echo '  "test:e2e": "wdio run wdio.conf.js"'
    fi

    echo ""
    log_success "E2E test infrastructure initialized!"
    echo ""
    echo "Next steps:"
    echo "  1. Build your app:        cd src-tauri && cargo build"
    echo "  2. Start Xvfb (headless): Xvfb :99 -screen 0 1280x1024x24 &"
    echo "  3. Run smoke test:        DISPLAY=:99 $pkg_manager test:e2e"
    echo "  4. Generate tests:        cr test-gen specs/your-feature/SPEC.md"
    echo ""
    echo "Prerequisites:"
    echo "  - tauri-driver: cargo install tauri-driver"
    echo "  - webkit2gtk-driver: sudo apt install webkit2gtk-driver"
}

cmd_help() {
    cat << HELP
Compound Ralph - Autonomous Feature Implementation System
Version: $CR_VERSION

Combines compound-engineering's rich planning with the Ralph Loop technique
for autonomous, iterative feature implementation.

USAGE:
    cr <command> [arguments]

COMMANDS:
    init [path]         Initialize a project for Compound Ralph
                        Creates specs/, plans/, knowledge/, AGENTS.md
                        Auto-detects project type (bun, npm, rails, python, etc.)

    converse <topic>    Explore an idea through Socratic dialogue
        (alias: conv)   Surfaces assumptions, explores alternatives, clarifies
                        trade-offs BEFORE planning. Saves decision records to
                        knowledge/decisions/ for use in later planning.

    research <topic>    Deep investigation before planning
        (alias: res)    Analyzes codebase, researches best practices, assesses
                        feasibility. Saves research reports to knowledge/research/
                        for use in later planning.

    plan <description>  Create and deepen a feature plan
                        Automatically ingests knowledge/ context from prior
                        converse/research sessions into the planning prompt.
                        Runs /workflows:plan + /deepen-plan
                        Enriches with 40+ parallel research agents

    spec <plan-file>    Convert a plan to SPEC.md format
                        Creates specs/<feature>/ directory
                        Generates SPEC.md + PROMPT.md
                        Auto-detects quality gates

    implement [spec]    Start autonomous implementation loop
                        Reads SPEC.md, executes one task per iteration
                        Runs backpressure (tests, lint) each iteration
                        Auto-detects fix specs (fixes/code, fixes/design)
                        Continues until completion or max iterations

    review [spec]       Run comprehensive code review (spec-aware)
        [--design]      Include design review (requires dev server)
        [--design-only] Only run design review (SPA-aware)
        [--url URL]     Specify dev server URL for design review
        [--team]        Use Agent Teams for parallel review (experimental)
                        Spawns 3 competing reviewers (security, performance,
                        quality) that challenge each other's findings.
                        Higher token cost, but more thorough.
                        Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
        [--team-model]  Model to use for teammates (e.g., sonnet)
        [--dry-run]     Preview team structure without running (with --team)
                        Discovers pages via nav/footer + SPA view states
                        (tabs, keyboard shortcuts 1-5, sidebars, etc.)
                        Saves todos to: specs/<feature>/todos/code/
                                    or: specs/<feature>/todos/design/

    fix [type] [spec]   Convert todos to fix spec (spec-aware)
        [code]          Fix code review issues only
        [design]        Fix design review issues only
        (no arg)        Fix all issues
                        Creates: specs/<feature>/fixes/[code|design]/

    test-gen <spec>     Generate E2E tests from feature spec
        (alias: tg)     Reads SPEC.md, produces WebdriverIO test file
                        Uses LLM to translate requirements → test code
                        --output <file>  Specify output path
                        --example-tests  Directory with example tests
                        --dry-run        Show generated code only
                        --all            Process all specs in directory

    init-tests          Set up WebdriverIO E2E testing infrastructure
        (alias: init-e2e)  Creates wdio.conf.js, test directory, smoke test
                        Installs dependencies, adds npm scripts
                        --force          Overwrite existing config
                        --test-dir <dir> Custom test directory (default: test/e2e)

    compound [feature]  Extract and preserve learnings (Phase 6)
        (alias: comp)   Captures patterns, decisions, and pitfalls
                        Makes future work easier by compounding knowledge
                        Saves to: knowledge/learnings/, knowledge/patterns/

    design [url]        Proactive design improvement loop (SPA-aware)
        [--n N]         Force exactly N iterations (no early exit)
                        Default: exits early when design is polished
                        Auto-detects dev server if no URL
                        Discovers ALL pages AND view states
                        (nav links, keyboard shortcuts, tabs, sidebars)
                        Uses /frontend-design skill for distinctive UI
                        Saves screenshots to design-iterations/

    status              Show progress of all specs (including fixes)

    learnings [cat]     View project learnings from .cr/learnings.json
        [limit]         Number of entries to show (default: 20)
                        Categories: environment, pattern, gotcha, fix, discovery

    reset-context       Reset accumulated context for a stuck spec
        <spec-dir>      Use when agent has learned harmful patterns
                        (e.g., dismissing errors as "pre-existing")
                        Clears bad learnings, allows fresh start

    help                Show this help

PROJECT STRUCTURE:
    your-project/
    ├── knowledge/                  # Pre-planning knowledge (from converse/research)
    │   ├── decisions/              # Decision records from cr converse
    │   │   └── 2026-01-27-auth-approach.md
    │   └── research/               # Research reports from cr research
    │       └── oauth-providers.md
    ├── plans/                      # Rich plans from cr plan
    │   └── add-user-auth.md
    └── specs/                      # Implementation specs
        └── my-feature/
            ├── SPEC.md             # Feature spec (source of truth)
            ├── PROMPT.md
            ├── todos/
            │   ├── code/           # Code review findings
            │   │   └── 001-p1-issue.md
            │   └── design/         # Design review findings
            │       └── 001-p2-issue.md
            └── fixes/
                ├── code/           # Fix spec for code issues
                │   └── SPEC.md
                └── design/         # Fix spec for design issues
                    └── SPEC.md

WORKFLOW:
    1. cr init                           # Initialize project
    2. cr converse "auth approach"       # Explore ideas (optional)
    3. cr research "oauth providers"     # Investigate deeply (optional)
    4. cr plan "add user auth"           # Create plan (uses knowledge/)
    5. cr spec plans/add-user-auth.md    # Convert to spec
    6. cr implement                      # Build feature
    7. cr design                         # Polish UI (optional)
    8. cr review                         # Code review → todos/code/
    9. cr review --design                # Design review → todos/design/
   10. cr fix code                       # Create fix spec for code
   11. cr implement                      # Fix code issues
   12. cr fix design                     # Create fix spec for design
   13. cr implement                      # Fix design issues
   14. cr review                         # Verify clean

ENVIRONMENT VARIABLES:
    MAX_ITERATIONS      Maximum loop iterations (default: 50)
    ITERATION_DELAY     Seconds between iterations (default: 3)
    MAX_RETRIES         Retries per iteration on transient errors (default: 3)
    RETRY_DELAY         Initial retry delay in seconds, doubles each retry (default: 5)
    ITERATION_TIMEOUT   Max seconds per iteration before timeout (default: 600)
    MAX_CONSECUTIVE_FAILURES  Stop after N consecutive failures (default: 3)

RESILIENCE:
    - Per-iteration timeout prevents stuck iterations
    - Visible retry logging shows progress during failures
    - Consecutive failure limit prevents infinite loops
    - Graceful Ctrl+C handling for clean exits
    - Auto-resume: just run 'cr implement' again

PHILOSOPHY:
    Understand first, then plan, then build.
    Converse and research BEFORE committing to a plan.
    Planning is human-guided and rich.
    Implementation is autonomous and focused.
    Each iteration: fresh context + file-based state.
    Backpressure (tests, lint) lets agents self-correct.

INSPIRATION:
    https://ghuntley.com/ralph/ (original Ralph technique)
    https://ghuntley.com/pressure/ (backpressure concepts)

    Note: This tool implements its own loop - does not use the ralph-wiggum plugin.

HELP
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    check_prerequisites
    migrate_borg_to_cr

    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            cmd_init "$@"
            ;;
        converse|conv)
            cmd_converse "$@"
            ;;
        research|res)
            cmd_research "$@"
            ;;
        plan)
            cmd_plan "$@"
            ;;
        spec)
            cmd_spec "$@"
            ;;
        implement|build|run)
            cmd_implement "$@"
            ;;
        review)
            cmd_review "$@"
            ;;
        design)
            cmd_design "$@"
            ;;
        fix)
            cmd_fix "$@"
            ;;
        test-gen|testgen|tg)
            cmd_test_gen "$@"
            ;;
        init-tests|init-e2e)
            cmd_init_tests "$@"
            ;;
        compound|comp)
            cmd_compound "$@"
            ;;
        spec-from-todos)
            # Deprecated - show migration message
            cmd_spec_from_todos "$@"
            ;;
        status)
            cmd_status
            ;;
        learnings)
            cmd_learnings "$@"
            ;;
        reset-context)
            cmd_reset_context "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        version|--version|-v)
            echo "Compound Ralph v$CR_VERSION"
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run 'cr help' for usage."
            exit 1
            ;;
    esac
}

main "$@"
