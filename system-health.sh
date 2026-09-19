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

# Parse optional flag
OUTPUT_JSON=0
if [[ "${1-}" == "--json" ]]; then
  OUTPUT_JSON=1
fi

# Helper to record result
declare -A RESULT
OVERALL_STATUS=0   # 0 = success, 1 = failure

# ---------------------------------------------------------------------------
# 1. Validate all worker-*.conf files using validate-config.sh (non‑dry‑run)
# ---------------------------------------------------------------------------
if ./validate-config.sh > /dev/null 2>&1; then
  RESULT[config]="PASS"
else
  RESULT[config]="FAIL"
  OVERALL_STATUS=1
fi

# ---------------------------------------------------------------------------
# 2. Verify that seal‑server process is running (pgrep)
# ---------------------------------------------------------------------------
if pgrep -f "seal-server" > /dev/null; then
  RESULT[seal_server]="PASS"
else
  RESULT[seal_server]="FAIL"
  OVERALL_STATUS=1
fi

# ---------------------------------------------------------------------------
# 3. Check that the QEMU binary exists and obtain its version
# ---------------------------------------------------------------------------
QEMU_BIN="/usr/local/bin/qemu-system-x86_64"
if [[ -x "$QEMU_BIN" ]]; then
  QEMU_VERSION=$($QEMU_BIN --version | head -1)
  RESULT[qemu]="PASS"
else
  RESULT[qemu]="FAIL"
  OVERALL_STATUS=1
fi

# ---------------------------------------------------------------------------
# 4. Verify that the QEMU binary reports TDX support via "-machine help"
# ---------------------------------------------------------------------------
if [[ -x "$QEMU_BIN" ]] && $QEMU_BIN -machine help 2>/dev/null | grep -qi tdx; then
  RESULT[tdx]="PASS"
else
  RESULT[tdx]="FAIL"
  OVERALL_STATUS=1
fi

# ---------------------------------------------------------------------------
# 5. Ensure both worker processes are running (PID files in logs/)
# ---------------------------------------------------------------------------
workers_ok=1
for i in 0 1; do
  pidfile="logs/worker-${i}.pid"
  if [[ -f "$pidfile" ]]; then
    pid=$(cat "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      workers_ok=0
    fi
  else
    workers_ok=0
  fi
done
if [[ $workers_ok -eq 1 ]]; then
  RESULT[workers]="PASS"
else
  RESULT[workers]="FAIL"
  OVERALL_STATUS=1
fi

# ---------------------------------------------------------------------------
# Output handling – table or JSON
# ---------------------------------------------------------------------------
if [[ $OUTPUT_JSON -eq 1 ]]; then
  # Build JSON manually (bash associative arrays are unordered, but order is not critical)
  json="{"
  json+="\"config\": \"${RESULT[config]}\","
  json+="\"seal_server\": \"${RESULT[seal_server]}\","
  json+="\"qemu\": \"${RESULT[qemu]}\","
  json+="\"qemu_version\": \"${QEMU_VERSION:-null}\","
  json+="\"tdx\": \"${RESULT[tdx]}\","
  json+="\"workers\": \"${RESULT[workers]}\","
  json+="\"overall_status\": $(($OVERALL_STATUS == 0 ? 0 : 1))"
  json+="}"
  echo -e "$json"
else
  printf "%b=== COCOON System Health Check ===%b\n\n" "$YELLOW" "$NC"
  printf "% -20s %s\n" "Check" "Result"
  printf "% -20s %s\n" "--------------------" "------"
  printf "% -20s %b%s%b\n" "Config validation" "${RESULT[config]}" "${RESULT[config]}" "${NC}"
  printf "% -20s %b%s%b\n" "Seal‑server" "${RESULT[seal_server]}" "${NC}"
  if [[ -x "$QEMU_BIN" ]]; then
    printf "% -20s %b%s%b (%s)\n" "QEMU binary" "${RESULT[qemu]}" "${NC}" "$QEMU_VERSION"
  else
    printf "% -20s %b%s%b\n" "QEMU binary" "${RESULT[qemu]}" "${NC}"
  fi
  printf "% -20s %b%s%b\n" "QEMU TDX support" "${RESULT[tdx]}" "${NC}"
  printf "% -20s %b%s%b\n" "Worker processes" "${RESULT[workers]}" "${NC}"

  if [[ $OVERALL_STATUS -eq 0 ]]; then
    printf "\n%bAll checks passed.%b\n" "$GREEN" "$NC"
  else
    printf "\n% bSome checks failed. See above for details.%b\n" "$RED" "$NC"
  fi
fi

exit $OVERALL_STATUS
