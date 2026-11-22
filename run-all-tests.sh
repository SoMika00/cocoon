#!/usr/bin/env bash

# run-all-tests.sh - Unified test runner for all COCOON test-*.sh scripts
#
# Discovers every test-*.sh file in this script's directory, executes each one
# sequentially, and reports a PASS/FAIL summary. Supports a human-readable
# (colorized) table and a `--json` mode suitable for CI pipelines.
#
# Exit code is 0 when all tests pass, 1 otherwise (in both modes).

set -u

# Colors for human-readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat <<'EOF'
Usage: run-all-tests.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing each discovered test with status and exit code.

JSON schema (when --json is set):
  {
    "tests": [
      {"name": "test-foo.sh", "status": "pass|fail", "exit_code": 0|1}
    ],
    "summary": {"passed": N, "failed": M, "total": T},
    "overall_status": "ok|failed",
    "exit_code": 0|1
  }

Exit code is 0 when overall_status is "ok", 1 otherwise (in both modes).
EOF
}

# Parse arguments
OUTPUT_JSON=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 2
            ;;
    esac
done

# JSON escaping helper (pure bash, no jq dependency)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Determine the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover test scripts via glob, sorted for determinism.
shopt -s nullglob
TEST_FILES=("$SCRIPT_DIR"/test-*.sh)
shopt -u nullglob

# Sort the discovered test files by basename for deterministic ordering.
if [[ ${#TEST_FILES[@]} -gt 0 ]]; then
    IFS=$'\n' TEST_FILES=($(printf '%s\n' "${TEST_FILES[@]}" | sort)); unset IFS
fi

# Storage for results (parallel arrays)
TEST_NAMES=()
TEST_STATUS=()
TEST_EXIT_CODES=()
TEST_DETAILS=()

PASSED=0
FAILED=0

# Run each test sequentially, capturing its exit code and last summary line.
for test_file in "${TEST_FILES[@]}"; do
    name="$(basename "$test_file")"
    TEST_NAMES+=("$name")

    # Capture output so we can extract the last summary line for human mode.
    output=""
    if "$test_file" > /tmp/run-all-tests-$$.log 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    output=$(cat /tmp/run-all-tests-$$.log 2>/dev/null || true)
    rm -f /tmp/run-all-tests-$$.log

    # Extract the last non-empty line as the detail/summary line.
    detail=""
    while IFS= read -r line; do
        [[ -n "$line" ]] && detail="$line"
    done <<< "$output"

    if [[ $exit_code -eq 0 ]]; then
        TEST_STATUS+=("pass")
        ((PASSED++))
    else
        TEST_STATUS+=("fail")
        ((FAILED++))
    fi
    TEST_EXIT_CODES+=("$exit_code")
    TEST_DETAILS+=("$detail")
done

TOTAL=$((PASSED + FAILED))

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if [[ "$OUTPUT_JSON" == true ]]; then
    tests_json="["
    for idx in "${!TEST_NAMES[@]}"; do
        name_esc=$(json_escape "${TEST_NAMES[$idx]}")
        status_esc=$(json_escape "${TEST_STATUS[$idx]}")
        if [[ $idx -gt 0 ]]; then
            tests_json+=","
        fi
        tests_json+="{\"name\":\"$name_esc\",\"status\":\"$status_esc\",\"exit_code\":${TEST_EXIT_CODES[$idx]}}"
    done
    tests_json+="]"

    if [[ $FAILED -eq 0 ]]; then
        overall="ok"
        exit_code=0
    else
        overall="failed"
        exit_code=1
    fi

    printf '{"tests":%s,"summary":{"passed":%d,"failed":%d,"total":%d},"overall_status":"%s","exit_code":%d}\n' \
        "$tests_json" "$PASSED" "$FAILED" "$TOTAL" "$overall" "$exit_code"
    exit $exit_code
fi

# ---------------------------------------------------------------------------
# Human-readable mode (colorized table)
# ---------------------------------------------------------------------------
echo -e "${BLUE}=== COCOON Test Suite ===${NC}"
echo ""

# Print table header
printf "%-40s %-10s %s\n" "Test" "Status" "Detail"
printf "%-40s %-10s %s\n" "----------------------------------------" "----------" "----------------------------------------"

for idx in "${!TEST_NAMES[@]}"; do
    name="${TEST_NAMES[$idx]}"
    status="${TEST_STATUS[$idx]}"
    detail="${TEST_DETAILS[$idx]}"

    if [[ "$status" == "pass" ]]; then
        status_colored="${GREEN}PASS${NC}"
    else
        status_colored="${RED}FAIL${NC}"
    fi

    printf "%-40s %b %s\n" "$name" "$status_colored" "$detail"
done

echo ""
echo -e "=== Results: ${PASSED} passed, ${FAILED} failed ==="

if [[ $FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi
