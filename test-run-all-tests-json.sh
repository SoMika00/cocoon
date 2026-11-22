#!/usr/bin/env bash

# test-run-all-tests-json.sh - Unit-style tests for run-all-tests.sh
#
# Verifies the stable JSON contract of run-all-tests.sh by validating that
# --help exits 0, an unknown option exits non-zero, and --json produces valid
# JSON matching the expected schema.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/run-all-tests.sh"

PASS=0
FAIL=0

pass() {
    echo "  PASS: $1"
    ((PASS++))
}

fail() {
    echo "  FAIL: $1"
    ((FAIL++))
}

# Validate that a string is valid JSON using python3 (if available) or jq.
validate_json() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e . >/dev/null 2>&1
    else
        [[ "$json" == \{* ]]
    fi
}

# Validate the run-all-tests JSON schema.
validate_schema() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert set(data.keys()) == {"tests", "summary", "overall_status", "exit_code"}
assert isinstance(data["tests"], list)
for t in data["tests"]:
    assert set(t.keys()) == {"name", "status", "exit_code"}
    assert isinstance(t["name"], str)
    assert t["status"] in ("pass", "fail")
    assert t["exit_code"] in (0, 1)
s = data["summary"]
assert set(s.keys()) == {"passed", "failed", "total"}
assert s["passed"] + s["failed"] == s["total"]
assert s["total"] == len(data["tests"])
assert data["overall_status"] in ("ok", "failed")
assert data["exit_code"] in (0, 1)
if s["failed"] > 0:
    assert data["overall_status"] == "failed"
    assert data["exit_code"] == 1
else:
    assert data["overall_status"] == "ok"
    assert data["exit_code"] == 0
' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e '
            (keys | sort) == ["exit_code", "overall_status", "summary", "tests"] and
            (.tests | type == "array") and
            all(.tests[]; (keys | sort) == ["exit_code", "name", "status"]) and
            all(.tests[]; .status == "pass" or .status == "fail") and
            all(.tests[]; .exit_code == 0 or .exit_code == 1) and
            (.summary | (keys | sort) == ["failed", "passed", "total"]) and
            (.summary.passed + .summary.failed == .summary.total) and
            (.summary.total == (.tests | length)) and
            (.overall_status == "ok" or .overall_status == "failed") and
            (.exit_code == 0 or .exit_code == 1)
        ' >/dev/null 2>&1
    else
        return 0
    fi
}

# Extract a JSON field using python3 (preferred) or jq.
get_field() {
    local json="$1"
    local field="$2"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)$field)" 2>/dev/null
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r "$field" 2>/dev/null
    else
        echo ""
    fi
}

echo "=== test-run-all-tests-json.sh ==="
echo ""

# Check the helper exists and is executable.
if [[ ! -x "$HELPER" ]]; then
    echo "FAIL: $HELPER is missing or not executable"
    exit 1
fi
pass "helper script exists and is executable"

# ---------------------------------------------------------------------------
# 1. --help
# ---------------------------------------------------------------------------
echo "Test: --help"
if "$HELPER" --help >/dev/null 2>&1; then
    pass "--help exits 0"
else
    fail "--help exits non-zero"
fi

# ---------------------------------------------------------------------------
# 2. unknown option
# ---------------------------------------------------------------------------
echo "Test: unknown option"
if "$HELPER" --definitely-not-an-option >/dev/null 2>&1; then
    fail "unknown option should exit non-zero"
else
    pass "unknown option exits non-zero"
fi

# ---------------------------------------------------------------------------
# 3. --json produces valid JSON matching the schema
# ---------------------------------------------------------------------------
echo "Test: --json schema"
JSON_OUTPUT=$("$HELPER" --json 2>/dev/null)
JSON_EXIT=$?

if validate_json "$JSON_OUTPUT" && validate_schema "$JSON_OUTPUT"; then
    pass "--json produces valid JSON schema (exit=$JSON_EXIT)"
else
    fail "--json schema validation failed (exit=$JSON_EXIT)"
fi

# Verify summary consistency and overall_status/exit_code relationship.
TOTAL=$(get_field "$JSON_OUTPUT" "['summary']['total']")
PASSED=$(get_field "$JSON_OUTPUT" "['summary']['passed']")
FAILED=$(get_field "$JSON_OUTPUT" "['summary']['failed']")
OVERALL=$(get_field "$JSON_OUTPUT" "['overall_status']")
EXIT_CODE=$(get_field "$JSON_OUTPUT" "['exit_code']")

if [[ "$TOTAL" == "$((PASSED + FAILED))" ]]; then
    pass "summary.passed + summary.failed == summary.total"
else
    fail "summary totals inconsistent (total=$TOTAL passed=$PASSED failed=$FAILED)"
fi

if [[ "$FAILED" == "0" ]]; then
    if [[ "$OVERALL" == "ok" ]] && [[ "$EXIT_CODE" == "0" ]]; then
        pass "all-pass run reports overall_status=ok and exit_code=0"
    else
        fail "all-pass run should report ok/0 (overall=$OVERALL exit_code=$EXIT_CODE)"
    fi
else
    if [[ "$OVERALL" == "failed" ]] && [[ "$EXIT_CODE" == "1" ]]; then
        pass "failed run reports overall_status=failed and exit_code=1"
    else
        fail "failed run should report failed/1 (overall=$OVERALL exit_code=$EXIT_CODE)"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
