#!/usr/bin/env bash

# system-health.sh – Comprehensive health check for COCOON deployment
#
# This script validates configuration files, seal‑server, QEMU binary with TDX support,
# and the worker processes. It is non‑interactive and returns a clear exit code.
# Use "--json" to emit JSON output suitable for CI pipelines.

set -u

# Colors for pretty output (only used in non‑JSON mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

print_help() {
    cat <<'EOF'
Usage: system-health.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing each check with status, detail, and remediation hint.

JSON schema (when --json is set):
  {
    "checks": [
      {"name":"config","status":"pass|fail","detail":"...","hint":"..."},
      {"name":"seal_server","status":"pass|fail","detail":"pid=1234","hint":"Start: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"},
      {"name":"qemu","status":"pass|fail","detail":"QEMU emulator version 10.1.0","hint":"Compile with ./compile-qemu-tdx.sh"},
      {"name":"tdx","status":"pass|fail","detail":"tdx machine present","hint":"Rebuild QEMU with TDX support"},
      {"name":"workers","status":"pass|fail","detail":"worker0=alive worker1=missing","hint":"Run ./launch-workers.sh"}
    ],
    "summary": {"passed": 3, "failed": 2, "total": 5},
    "overall_status": "ok|failed"
  }

Exit code is 0 when overall_status is "ok", 1 otherwise (in both modes).
EOF
}

# Parse optional flags
OUTPUT_JSON=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=1
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
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

# Per-check result storage: name, status (pass|fail), detail, hint
# We use parallel arrays to preserve ordering.
CHECK_NAMES=()
CHECK_STATUS=()
CHECK_DETAIL=()
CHECK_HINT=()

add_check() {
    local name="$1"
    local status="$2"
    local detail="$3"
    local hint="$4"
    CHECK_NAMES+=("$name")
    CHECK_STATUS+=("$status")
    CHECK_DETAIL+=("$detail")
    CHECK_HINT+=("$hint")
}

OVERALL_STATUS=0   # 0 = success, 1 = failure

# ---------------------------------------------------------------------------
# 1. Validate all worker-*.conf files using validate-config.sh (non‑dry‑run)
# ---------------------------------------------------------------------------
CONFIG_DETAIL=""
CONFIG_HINT=""
if ./validate-config.sh > /dev/null 2>&1; then
    CONFIG_STATUS="pass"
    CONFIG_DETAIL="all worker-*.conf files valid"
    CONFIG_HINT="No action required"
else
    CONFIG_STATUS="fail"
    CONFIG_DETAIL="one or more worker-*.conf files invalid"
    CONFIG_HINT="Run ./validate-config.sh for details"
    OVERALL_STATUS=1
fi
add_check "config" "$CONFIG_STATUS" "$CONFIG_DETAIL" "$CONFIG_HINT"

# ---------------------------------------------------------------------------
# 2. Verify that seal‑server process is running (pgrep)
# ---------------------------------------------------------------------------
SEAL_PID=$(pgrep -f "seal-server" | head -1)
if [[ -n "$SEAL_PID" ]]; then
    SEAL_STATUS="pass"
    SEAL_DETAIL="pid=$SEAL_PID"
    SEAL_HINT="No action required"
else
    SEAL_STATUS="fail"
    SEAL_DETAIL="seal-server not running"
    SEAL_HINT="Start: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
    OVERALL_STATUS=1
fi
add_check "seal_server" "$SEAL_STATUS" "$SEAL_DETAIL" "$SEAL_HINT"

# ---------------------------------------------------------------------------
# 3. Check that the QEMU binary exists and obtain its version
# ---------------------------------------------------------------------------
QEMU_BIN="/usr/local/bin/qemu-system-x86_64"
QEMU_VERSION=""
if [[ -x "$QEMU_BIN" ]]; then
    QEMU_VERSION=$($QEMU_BIN --version | head -1)
    QEMU_STATUS="pass"
    QEMU_DETAIL="$QEMU_VERSION"
    QEMU_HINT="No action required"
else
    QEMU_STATUS="fail"
    QEMU_DETAIL="$QEMU_BIN not found or not executable"
    QEMU_HINT="Compile with ./compile-qemu-tdx.sh"
    OVERALL_STATUS=1
fi
add_check "qemu" "$QEMU_STATUS" "$QEMU_DETAIL" "$QEMU_HINT"

# ---------------------------------------------------------------------------
# 4. Verify that the QEMU binary reports TDX support via "-machine help"
# ---------------------------------------------------------------------------
if [[ -x "$QEMU_BIN" ]] && $QEMU_BIN -machine help 2>/dev/null | grep -qi tdx; then
    TDX_STATUS="pass"
    TDX_DETAIL="tdx machine present"
    TDX_HINT="No action required"
else
    TDX_STATUS="fail"
    TDX_DETAIL="tdx machine not present"
    TDX_HINT="Rebuild QEMU with TDX support"
    OVERALL_STATUS=1
fi
add_check "tdx" "$TDX_STATUS" "$TDX_DETAIL" "$TDX_HINT"

# ---------------------------------------------------------------------------
# 5. Ensure both worker processes are running (PID files in logs/)
# ---------------------------------------------------------------------------
workers_ok=1
worker_details=()
for i in 0 1; do
    pidfile="logs/worker-${i}.pid"
    if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            worker_details+=("worker${i}=alive")
        else
            worker_details+=("worker${i}=missing")
            workers_ok=0
        fi
    else
        worker_details+=("worker${i}=missing")
        workers_ok=0
    fi
done
WORKERS_DETAIL=$(printf '%s ' "${worker_details[@]}")
WORKERS_DETAIL="${WORKERS_DETAIL% }"
if [[ $workers_ok -eq 1 ]]; then
    WORKERS_STATUS="pass"
    WORKERS_HINT="No action required"
else
    WORKERS_STATUS="fail"
    WORKERS_HINT="Run ./launch-workers.sh"
    OVERALL_STATUS=1
fi
add_check "workers" "$WORKERS_STATUS" "$WORKERS_DETAIL" "$WORKERS_HINT"

# ---------------------------------------------------------------------------
# Output handling – table or JSON
# ---------------------------------------------------------------------------
if [[ $OUTPUT_JSON -eq 1 ]]; then
    # Build checks array
    checks_json="["
    passed=0
    failed=0
    for idx in "${!CHECK_NAMES[@]}"; do
        name_esc=$(json_escape "${CHECK_NAMES[$idx]}")
        status_esc=$(json_escape "${CHECK_STATUS[$idx]}")
        detail_esc=$(json_escape "${CHECK_DETAIL[$idx]}")
        hint_esc=$(json_escape "${CHECK_HINT[$idx]}")
        if [[ "${CHECK_STATUS[$idx]}" == "pass" ]]; then
            ((passed++))
        else
            ((failed++))
        fi
        if [[ $idx -gt 0 ]]; then
            checks_json+=","
        fi
        checks_json+="{\"name\":\"$name_esc\",\"status\":\"$status_esc\",\"detail\":\"$detail_esc\",\"hint\":\"$hint_esc\"}"
    done
    checks_json+="]"

    total=${#CHECK_NAMES[@]}
    if [[ $OVERALL_STATUS -eq 0 ]]; then
        overall="ok"
    else
        overall="failed"
    fi

    printf '{"checks":%s,"summary":{"passed":%d,"failed":%d,"total":%d},"overall_status":"%s"}\n' \
        "$checks_json" "$passed" "$failed" "$total" "$overall"
else
    printf "%b=== COCOON System Health Check ===%b\n\n" "$YELLOW" "$NC"
    printf "%-20s %s\n" "Check" "Result"
    printf "%-20s %s\n" "--------------------" "------"
    printf "%-20s %s\n" "Config validation" "${CHECK_STATUS[0]^^}"
    printf "%-20s %s\n" "Seal‑server" "${CHECK_STATUS[1]^^}"
    if [[ -x "$QEMU_BIN" ]]; then
        printf "%-20s %s (%s)\n" "QEMU binary" "${CHECK_STATUS[2]^^}" "$QEMU_VERSION"
    else
        printf "%-20s %s\n" "QEMU binary" "${CHECK_STATUS[2]^^}"
    fi
    printf "%-20s %s\n" "QEMU TDX support" "${CHECK_STATUS[3]^^}"
    printf "%-20s %s\n" "Worker processes" "${CHECK_STATUS[4]^^}"

    if [[ $OVERALL_STATUS -eq 0 ]]; then
        printf "\n%bAll checks passed.%b\n" "$GREEN" "$NC"
    else
        printf "\n%bSome checks failed. See above for details.%b\n" "$RED" "$NC"
    fi
fi

exit $OVERALL_STATUS
