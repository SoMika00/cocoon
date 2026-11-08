#!/usr/bin/env bash

# test-health-report-json.sh - Unit-style tests for health-report.sh --json
#
# Verifies the stable JSON contract of health-report.sh by stubbing its three
# sub-scripts (gpu-utilization.sh, status-workers.sh, system-health.sh) in a
# temp dir and asserting the merged output and exit codes.
#
# Mirrors the style of test-verify-config-json.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/health-report.sh"

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

# Assert that the merged JSON has exactly the keys {gpu, workers, system, overall_status}.
validate_keys() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert set(data.keys()) == {"gpu", "workers", "system", "overall_status"}
' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e '
            (keys | sort) == ["gpu", "overall_status", "system", "workers"]
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

echo "=== test-health-report-json.sh ==="
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
# 3. Merged JSON contract with healthy stubs
# ---------------------------------------------------------------------------
echo "Test: merged JSON with healthy stubs"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Copy health-report.sh into the temp dir so it resolves sub-scripts relative
# to its own location.
cp "$HELPER" "$TMPDIR_TEST/health-report.sh"
chmod +x "$TMPDIR_TEST/health-report.sh"

# Stub gpu-utilization.sh: all GPUs healthy.
cat > "$TMPDIR_TEST/gpu-utilization.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf '{"gpus":[{"index":0,"healthy":true}],"summary":{"total":1,"healthy":1,"unhealthy":0,"temp_threshold":85},"overall_status":"ok","exit_code":0}\n'
    exit 0
fi
exit 0
STUB
chmod +x "$TMPDIR_TEST/gpu-utilization.sh"

# Stub status-workers.sh: all workers running.
cat > "$TMPDIR_TEST/status-workers.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf '{"seal_server":{"running":true,"pid":1},"workers":[{"instance":0,"running":true},{"instance":1,"running":true}],"gpus":[],"overall_status":"ok"}\n'
    exit 0
fi
exit 0
STUB
chmod +x "$TMPDIR_TEST/status-workers.sh"

# Stub system-health.sh: overall_status ok.
cat > "$TMPDIR_TEST/system-health.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf '{"checks":[],"summary":{"passed":0,"failed":0,"total":0},"overall_status":"ok"}\n'
    exit 0
fi
exit 0
STUB
chmod +x "$TMPDIR_TEST/system-health.sh"

HEALTHY_JSON=$(cd "$TMPDIR_TEST" && ./health-report.sh --json 2>/dev/null)
HEALTHY_EXIT=$?

if [[ $HEALTHY_EXIT -eq 0 ]] && validate_json "$HEALTHY_JSON" && validate_keys "$HEALTHY_JSON"; then
    pass "healthy stubs produce valid merged JSON with exact keys (exit=$HEALTHY_EXIT)"
else
    fail "healthy stubs merged JSON validation failed (exit=$HEALTHY_EXIT)"
fi

OVERALL=$(get_field "$HEALTHY_JSON" "['overall_status']")
if [[ "$OVERALL" == "ok" ]]; then
    pass "overall_status == ok when all stubs healthy"
else
    fail "overall_status should be ok, got '$OVERALL'"
fi

# ---------------------------------------------------------------------------
# 4. Degraded when any stub reports a failure
# ---------------------------------------------------------------------------
echo "Test: degraded when a stub reports a failure"

# Make system-health.sh report a failure.
cat > "$TMPDIR_TEST/system-health.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf '{"checks":[],"summary":{"passed":0,"failed":1,"total":1},"overall_status":"failed"}\n'
    exit 1
fi
exit 1
STUB
chmod +x "$TMPDIR_TEST/system-health.sh"

DEGRADED_JSON=$(cd "$TMPDIR_TEST" && ./health-report.sh --json 2>/dev/null)
DEGRADED_EXIT=$?

if [[ $DEGRADED_EXIT -eq 1 ]] && validate_json "$DEGRADED_JSON" && validate_keys "$DEGRADED_JSON"; then
    pass "failing stub produces valid merged JSON with exact keys (exit=$DEGRADED_EXIT)"
else
    fail "failing stub merged JSON validation failed (exit=$DEGRADED_EXIT)"
fi

OVERALL=$(get_field "$DEGRADED_JSON" "['overall_status']")
if [[ "$OVERALL" == "degraded" ]]; then
    pass "overall_status == degraded when a stub reports a failure"
else
    fail "overall_status should be degraded, got '$OVERALL'"
fi

# ---------------------------------------------------------------------------
# 5. Exit code 2 when a required sub-script is missing
# ---------------------------------------------------------------------------
echo "Test: exit 2 when a required sub-script is missing"

# Restore healthy system-health stub, then remove gpu-utilization.sh.
cat > "$TMPDIR_TEST/system-health.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf '{"checks":[],"summary":{"passed":0,"failed":0,"total":0},"overall_status":"ok"}\n'
    exit 0
fi
exit 0
STUB
chmod +x "$TMPDIR_TEST/system-health.sh"

rm -f "$TMPDIR_TEST/gpu-utilization.sh"

(cd "$TMPDIR_TEST" && ./health-report.sh --json >/dev/null 2>&1)
MISSING_EXIT=$?

if [[ $MISSING_EXIT -eq 2 ]]; then
    pass "missing sub-script exits 2"
else
    fail "missing sub-script should exit 2, got $MISSING_EXIT"
fi

# ---------------------------------------------------------------------------
# 6. Exit code 2 when a sub-script emits invalid JSON
# ---------------------------------------------------------------------------
echo "Test: exit 2 when a sub-script emits invalid JSON"

# Restore gpu-utilization.sh but make it emit invalid JSON.
cat > "$TMPDIR_TEST/gpu-utilization.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
    printf 'this is not valid json\n'
    exit 0
fi
exit 0
STUB
chmod +x "$TMPDIR_TEST/gpu-utilization.sh"

(cd "$TMPDIR_TEST" && ./health-report.sh --json >/dev/null 2>&1)
INVALID_EXIT=$?

if [[ $INVALID_EXIT -eq 2 ]]; then
    pass "invalid JSON sub-script exits 2"
else
    fail "invalid JSON sub-script should exit 2, got $INVALID_EXIT"
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
