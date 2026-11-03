#!/usr/bin/env bash

# test-setup-gpu-vfio.sh - Unit-style tests for setup-gpu-vfio.sh
#
# Runs the helper in dry-run mode for both bind and unbind, validates that the
# JSON output conforms to the expected schema, and exits 0 when all checks pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/setup-gpu-vfio.sh"

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
        # Fallback: basic structural check (starts with { or [).
        [[ "$json" == \{* || "$json" == \[* ]]
    fi
}

# Validate the list JSON schema: an array of {pci_id, driver} objects.
validate_list_schema() {
    local json="$1"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list)
for obj in data:
    assert set(obj.keys()) == {"pci_id", "driver"}
    assert isinstance(obj["pci_id"], str)
    assert isinstance(obj["driver"], str)
' >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e 'type == "array" and all(.[]; has("pci_id") and has("driver"))' >/dev/null 2>&1
    else
        return 0
    fi
}

# Validate the bind/unbind JSON schema.
validate_action_schema() {
    local json="$1"
    local expected_command="$2"
    if command -v python3 >/dev/null 2>&1; then
        echo "$json" | python3 -c '
import sys, json
cmd = sys.argv[1]
data = json.load(sys.stdin)
assert set(data.keys()) == {"command", "dry_run", "results", "overall_status"}
assert data["command"] == cmd
assert isinstance(data["dry_run"], bool)
assert isinstance(data["results"], list)
assert data["overall_status"] in ("ok", "failed")
for r in data["results"]:
    assert set(r.keys()) == {"pci_id", "success", "action", "error"}
    assert isinstance(r["pci_id"], str)
    assert isinstance(r["success"], bool)
    assert isinstance(r["action"], str)
    assert isinstance(r["error"], str)
' "$expected_command" >/dev/null 2>&1
    elif command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -e --arg cmd "$expected_command" '
            .command == $cmd and
            (.dry_run | type == "boolean") and
            (.results | type == "array") and
            (.overall_status == "ok" or .overall_status == "failed") and
            all(.results[]; has("pci_id") and has("success") and has("action") and has("error"))
        ' >/dev/null 2>&1
    else
        return 0
    fi
}

echo "=== test-setup-gpu-vfio.sh ==="
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
# 2. list --json
# ---------------------------------------------------------------------------
echo "Test: list --json"
LIST_JSON=$("$HELPER" list --json 2>/dev/null)
LIST_EXIT=$?
if [[ $LIST_EXIT -eq 0 ]] && validate_json "$LIST_JSON" && validate_list_schema "$LIST_JSON"; then
    pass "list --json produces valid JSON array schema"
else
    fail "list --json schema validation failed (exit=$LIST_EXIT)"
fi

# ---------------------------------------------------------------------------
# 3. bind --dry-run --json
# ---------------------------------------------------------------------------
echo "Test: bind --dry-run --json"
BIND_JSON=$("$HELPER" bind 0000:01:00.0 0000:02:00.0 --dry-run --json 2>/dev/null)
BIND_EXIT=$?
if [[ $BIND_EXIT -eq 0 ]] && validate_json "$BIND_JSON" && validate_action_schema "$BIND_JSON" "bind"; then
    pass "bind --dry-run --json produces valid JSON schema"
else
    fail "bind --dry-run --json schema validation failed (exit=$BIND_EXIT)"
fi

# Verify dry_run flag is true in bind output.
if command -v python3 >/dev/null 2>&1; then
    DRY=$(echo "$BIND_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["dry_run"])' 2>/dev/null)
    if [[ "$DRY" == "True" ]]; then
        pass "bind --dry-run reports dry_run=true"
    else
        fail "bind --dry-run did not report dry_run=true"
    fi
elif command -v jq >/dev/null 2>&1; then
    DRY=$(echo "$BIND_JSON" | jq -r '.dry_run' 2>/dev/null)
    if [[ "$DRY" == "true" ]]; then
        pass "bind --dry-run reports dry_run=true"
    else
        fail "bind --dry-run did not report dry_run=true"
    fi
fi

# ---------------------------------------------------------------------------
# 4. unbind --dry-run --json
# ---------------------------------------------------------------------------
echo "Test: unbind --dry-run --json"
UNBIND_JSON=$("$HELPER" unbind 0000:01:00.0 0000:02:00.0 --dry-run --json 2>/dev/null)
UNBIND_EXIT=$?
if [[ $UNBIND_EXIT -eq 0 ]] && validate_json "$UNBIND_JSON" && validate_action_schema "$UNBIND_JSON" "unbind"; then
    pass "unbind --dry-run --json produces valid JSON schema"
else
    fail "unbind --dry-run --json schema validation failed (exit=$UNBIND_EXIT)"
fi

# ---------------------------------------------------------------------------
# 5. invalid PCI ID should fail
# ---------------------------------------------------------------------------
echo "Test: invalid PCI ID"
if "$HELPER" bind not-a-pci-id --dry-run --json >/dev/null 2>&1; then
    fail "bind with invalid PCI ID should exit non-zero"
else
    pass "bind with invalid PCI ID exits non-zero"
fi

# ---------------------------------------------------------------------------
# 6. missing command should fail
# ---------------------------------------------------------------------------
echo "Test: missing command"
if "$HELPER" >/dev/null 2>&1; then
    fail "no command should exit non-zero"
else
    pass "no command exits non-zero"
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
