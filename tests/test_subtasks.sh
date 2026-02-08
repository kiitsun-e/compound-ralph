#!/usr/bin/env bash
#
# Tests for sub-task counting and continuation marker support.
# Run: bash tests/test_subtasks.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CR_DIR="$(dirname "$SCRIPT_DIR")"

# Source only the functions we need from cr (skip the main dispatch)
# We extract the functions by sourcing cr in a subshell that doesn't execute main
eval "$(sed -n '/^count_tasks()/,/^}/p' "$CR_DIR/cr")"
eval "$(sed -n '/^all_tasks_complete()/,/^}/p' "$CR_DIR/cr")"
eval "$(sed -n '/^get_continuation_marker()/,/^}/p' "$CR_DIR/cr")"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $description"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $description (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Sub-task counting tests ==="
echo ""

# Test 1: Simple flat tasks (no sub-tasks)
echo "Test 1: Flat tasks only"
cat > "$TMPDIR/spec1.md" << 'EOF'
## Tasks
- [ ] Task 1: Setup
- [ ] Task 2: Implementation
- [x] Task 3: Done already
EOF
assert_eq "pending count" "2" "$(count_tasks "$TMPDIR/spec1.md" "pending")"
assert_eq "completed count" "1" "$(count_tasks "$TMPDIR/spec1.md" "completed")"
assert_eq "all count" "3" "$(count_tasks "$TMPDIR/spec1.md" "all")"
echo ""

# Test 2: Parent with sub-tasks (none complete)
echo "Test 2: Parent with sub-tasks (none complete)"
cat > "$TMPDIR/spec2.md" << 'EOF'
## Tasks
- [ ] Task 1: Build auth system
  - [ ] Create user model
  - [ ] Add login endpoint
  - [ ] Add JWT generation
- [x] Task 2: Simple task done
EOF
assert_eq "pending count" "3" "$(count_tasks "$TMPDIR/spec2.md" "pending")"
assert_eq "completed count" "1" "$(count_tasks "$TMPDIR/spec2.md" "completed")"
assert_eq "all count" "4" "$(count_tasks "$TMPDIR/spec2.md" "all")"
echo ""

# Test 3: Parent with sub-tasks (partially complete)
echo "Test 3: Parent with sub-tasks (partially complete)"
cat > "$TMPDIR/spec3.md" << 'EOF'
## Tasks
- [ ] Task 1: Build auth system
  - [x] Create user model
  - [ ] Add login endpoint
  - [x] Add JWT generation
EOF
assert_eq "pending count" "1" "$(count_tasks "$TMPDIR/spec3.md" "pending")"
assert_eq "completed count" "2" "$(count_tasks "$TMPDIR/spec3.md" "completed")"
echo ""

# Test 4: Parent with all sub-tasks complete
echo "Test 4: Parent with all sub-tasks complete"
cat > "$TMPDIR/spec4.md" << 'EOF'
## Tasks
- [x] Task 1: Build auth system
  - [x] Create user model
  - [x] Add login endpoint
  - [x] Add JWT generation
EOF
assert_eq "pending count" "0" "$(count_tasks "$TMPDIR/spec4.md" "pending")"
assert_eq "completed count" "3" "$(count_tasks "$TMPDIR/spec4.md" "completed")"
echo ""

# Test 5: Mixed flat and sub-tasks
echo "Test 5: Mixed flat and sub-tasks"
cat > "$TMPDIR/spec5.md" << 'EOF'
## Tasks
- [x] Task 1: Setup (flat, done)
- [ ] Task 2: Auth system
  - [x] Sub 2a done
  - [ ] Sub 2b pending
- [ ] Task 3: Another flat pending
- [x] Task 4: Flat done
  - [x] Sub 4a done
  - [x] Sub 4b done
EOF
assert_eq "pending count" "2" "$(count_tasks "$TMPDIR/spec5.md" "pending")"
assert_eq "completed count" "4" "$(count_tasks "$TMPDIR/spec5.md" "completed")"
echo ""

# Test 6: all_tasks_complete function
echo "Test 6: all_tasks_complete function"
cat > "$TMPDIR/spec6_incomplete.md" << 'EOF'
- [x] Task 1
  - [x] Sub 1a
  - [ ] Sub 1b
EOF
cat > "$TMPDIR/spec6_complete.md" << 'EOF'
- [x] Task 1
  - [x] Sub 1a
  - [x] Sub 1b
EOF
if all_tasks_complete "$TMPDIR/spec6_incomplete.md"; then
    assert_eq "incomplete spec returns false" "false" "true"
else
    assert_eq "incomplete spec returns false" "false" "false"
fi
if all_tasks_complete "$TMPDIR/spec6_complete.md"; then
    assert_eq "complete spec returns true" "true" "true"
else
    assert_eq "complete spec returns true" "true" "false"
fi
echo ""

# Test 7: 4-space indented sub-tasks
echo "Test 7: 4-space indented sub-tasks"
cat > "$TMPDIR/spec7.md" << 'EOF'
## Tasks
- [ ] Task 1: Big feature
    - [ ] Sub with 4-space indent
    - [x] Another 4-space sub done
EOF
assert_eq "pending count (4-space)" "1" "$(count_tasks "$TMPDIR/spec7.md" "pending")"
assert_eq "completed count (4-space)" "1" "$(count_tasks "$TMPDIR/spec7.md" "completed")"
echo ""

echo "=== Continuation marker tests ==="
echo ""

# Test 8: No continuation marker
echo "Test 8: No continuation marker"
cat > "$TMPDIR/spec8.md" << 'EOF'
## Notes
Just some notes here.
EOF
assert_eq "no marker returns empty" "" "$(get_continuation_marker "$TMPDIR/spec8.md")"
echo ""

# Test 9: Has continuation marker
echo "Test 9: Has continuation marker"
cat > "$TMPDIR/spec9.md" << 'EOF'
## Notes
Some notes.
<!-- CONTINUATION: Built user model. Still need login endpoint and JWT. Working in src/auth/ -->
More notes.
EOF
result=$(get_continuation_marker "$TMPDIR/spec9.md")
assert_eq "extracts marker text" "Built user model. Still need login endpoint and JWT. Working in src/auth/" "$result"
echo ""

# Test 10: Empty spec
echo "Test 10: Empty spec file"
cat > "$TMPDIR/spec10.md" << 'EOF'
## Tasks
No tasks here.
EOF
assert_eq "empty pending" "0" "$(count_tasks "$TMPDIR/spec10.md" "pending")"
assert_eq "empty completed" "0" "$(count_tasks "$TMPDIR/spec10.md" "completed")"
echo ""

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
