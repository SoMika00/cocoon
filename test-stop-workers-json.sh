#!/usr/bin/env bash

# test-stop-workers-json.sh - Unit-style tests for stop-workers.sh --json
#
# Verifies the stable JSON contract of stop-workers.sh by running it in a temp
# dir with no PID files present, validating the JSON schema, and checking that
# --help exits 0 and an unknown option exits non-zero.
#
# Mirrors the style of test-health-report-json.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/stop-workers.sh"

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

# Validate the stop-workers JSON schema.
validate_schema() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert set(data.keys()) == {"workers", "watchdog", "overall_status", "exit_code"}
assert isinstance(data["workers"], list)
assert len(data["workers"]) == 2
for w in data["workers"]:
    assert set(w.keys()) == {"instance", "pid", "pid_file", "was_running", "stopped"}
    assert isinstance(w["instance"], int)
    assert w["pid"] is None or isinstance(w["pid"], int)
    assert isinstance(w["pid_file"], str)
    assert isinstance(w["was_running"], bool)
    assert isinstance(w["stopped"], bool)
wd = data["watchdog"]
assert set(wd.keys()) == {"was_running", "stopped"}
assert isinstance(wd["was_running"], bool)
assert isinstance(wd["stopped"], bool)
assert data["overall_status"] in ("ok", "degraded")
assert data["exit_code"] in (0, 1)
' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e '
            (keys | sort) == ["exit_code", "overall_status", "watchdog", "workers"] and
            (.workers | type == "array") and
            (.workers | length == 2) and
            all(.workers[]; (keys | sort) == ["instance", "pid", "pid_file", "stopped", "was_running"]) and
            all(.workers[]; (.pid == null) or (.pid | type == "number")) and
            all(.workers[]; (.was_running | type == "boolean") and (.stopped | type == "boolean")) and
            (.watchdog | (keys | sort) == ["stopped", "was_running"]) and
            (.watchdog.was_running | type == "boolean") and
            (.watchdog.stopped | type == "boolean") and
            (.overall_status == "ok" or .overall_status == "degraded") and
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

echo "=== test-stop-workers-json.sh ==="
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
# 3. --json in a temp dir with no PID files
# ---------------------------------------------------------------------------
echo "Test: --json in temp dir (no PID files)"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

JSON_OUTPUT=$(cd "$TMPDIR_TEST" && "$HELPER" --json 2>/dev/null)
JSON_EXIT=$?

if [[ $JSON_EXIT -eq 0 ]] && validate_json "$JSON_OUTPUT" && validate_schema "$JSON_OUTPUT"; then
    pass "--json produces valid JSON schema (exit=$JSON_EXIT)"
else
    fail "--json schema validation failed (exit=$JSON_EXIT)"
fi

# Verify overall_status is "ok" and exit_code is 0 when nothing to stop.
OVERALL=$(get_field "$JSON_OUTPUT" "['overall_status']")
EXIT_CODE=$(get_field "$JSON_OUTPUT" "['exit_code']")
if [[ "$OVERALL" == "ok" ]] && [[ "$EXIT_CODE" == "0" ]]; then
    pass "empty temp dir reports overall_status=ok and exit_code=0"
else
    fail "empty temp dir should report ok/0, got overall=$OVERALL exit_code=$EXIT_CODE"
fi

# Verify each worker reports pid=null, was_running=false, stopped=false.
W0_PID=$(get_field "$JSON_OUTPUT" "['workers'][0]['pid']")
W0_RUN=$(get_field "$JSON_OUTPUT" "['workers'][0]['was_running']")
W0_STOP=$(get_field "$JSON_OUTPUT" "['workers'][0]['stopped']")
W1_PID=$(get_field "$JSON_OUTPUT" "['workers'][1]['pid']")
W1_RUN=$(get_field "$JSON_OUTPUT" "['workers'][1]['was_running']")
W1_STOP=$(get_field "$JSON_OUTPUT" "['workers'][1]['stopped']")

if [[ "$W0_PID" == "None" || "$W0_PID" == "null" ]] && [[ "$W0_RUN" == "False" || "$W0_RUN" == "false" ]] && [[ "$W0_STOP" == "False" || "$W0_STOP" == "false" ]]; then
    pass "worker 0 reports pid=null, was_running=false, stopped=false"
else
    fail "worker 0 unexpected values (pid=$W0_PID run=$W0_RUN stop=$W0_STOP)"
fi

if [[ "$W1_PID" == "None" || "$W1_PID" == "null" ]] && [[ "$W1_RUN" == "False" || "$W1_RUN" == "false" ]] && [[ "$W1_STOP" == "False" || "$W1_STOP" == "false" ]]; then
    pass "worker 1 reports pid=null, was_running=false, stopped=false"
else
    fail "worker 1 unexpected values (pid=$W1_PID run=$W1_RUN stop=$W1_STOP)"
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
