#!/usr/bin/env bash

# test-verify-config-json.sh - Unit-style tests for verify-config.sh --json
#
# Runs verify-config.sh --json in a temp dir with no distribution present,
# validates that the JSON output conforms to the expected schema, and checks
# that --help exits 0 and an unknown option exits non-zero.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/verify-config.sh"

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

# Validate the verify-config JSON schema.
validate_schema() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert set(data.keys()) == {"checks", "summary", "overall_status", "exit_code"}
assert isinstance(data["checks"], list)
for c in data["checks"]:
    assert set(c.keys()) == {"name", "status", "detail", "hint"}
    assert isinstance(c["name"], str)
    assert c["status"] in ("pass", "warn", "fail")
    assert isinstance(c["detail"], str)
    assert isinstance(c["hint"], str)
s = data["summary"]
assert set(s.keys()) == {"passed", "warned", "failed", "total"}
assert s["passed"] + s["warned"] + s["failed"] == s["total"]
assert s["total"] == len(data["checks"])
assert data["overall_status"] in ("ok", "degraded", "failed")
assert data["exit_code"] in (0, 1)
# overall_status logic
if s["failed"] > 0:
    assert data["overall_status"] == "failed"
    assert data["exit_code"] == 1
elif s["warned"] > 0:
    assert data["overall_status"] == "degraded"
    assert data["exit_code"] == 0
else:
    assert data["overall_status"] == "ok"
    assert data["exit_code"] == 0
' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e '
            (has("checks") and has("summary") and has("overall_status") and has("exit_code")) and
            (.checks | type == "array") and
            all(.checks[]; has("name") and has("status") and has("detail") and has("hint")) and
            all(.checks[]; .status == "pass" or .status == "warn" or .status == "fail") and
            (.summary | has("passed") and has("warned") and has("failed") and has("total")) and
            (.summary.passed + .summary.warned + .summary.failed == .summary.total) and
            (.summary.total == (.checks | length)) and
            (.overall_status == "ok" or .overall_status == "degraded" or .overall_status == "failed") and
            (.exit_code == 0 or .exit_code == 1)
        ' >/dev/null 2>&1
    else
        return 0
    fi
}

echo "=== test-verify-config-json.sh ==="
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
# 3. --json in a temp dir with no distribution present
# ---------------------------------------------------------------------------
echo "Test: --json in temp dir (no distribution)"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

JSON_OUTPUT=$(cd "$TMPDIR_TEST" && "$HELPER" --json 2>/dev/null)
JSON_EXIT=$?

if [[ $JSON_EXIT -eq 1 ]] && validate_json "$JSON_OUTPUT" && validate_schema "$JSON_OUTPUT"; then
    pass "--json produces valid JSON schema (exit=$JSON_EXIT)"
else
    fail "--json schema validation failed (exit=$JSON_EXIT)"
fi

# Verify that with no distribution present, there is at least one fail check
# and overall_status is "failed".
if command -v python3 >/dev/null 2>&1; then
    OVERALL=$(echo "$JSON_OUTPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["overall_status"])' 2>/dev/null)
    FAILED=$(echo "$JSON_OUTPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["summary"]["failed"])' 2>/dev/null)
    if [[ "$OVERALL" == "failed" ]] && [[ "$FAILED" -gt 0 ]]; then
        pass "no-distribution run reports overall_status=failed with failed>0"
    else
        fail "no-distribution run did not report failed status (overall=$OVERALL failed=$FAILED)"
    fi
elif command -v jq >/dev/null 2>&1; then
    OVERALL=$(echo "$JSON_OUTPUT" | jq -r '.overall_status' 2>/dev/null)
    FAILED=$(echo "$JSON_OUTPUT" | jq -r '.summary.failed' 2>/dev/null)
    if [[ "$OVERALL" == "failed" ]] && [[ "$FAILED" -gt 0 ]]; then
        pass "no-distribution run reports overall_status=failed with failed>0"
    else
        fail "no-distribution run did not report failed status (overall=$OVERALL failed=$FAILED)"
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
