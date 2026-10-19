#!/usr/bin/env bash

# ci-validate.sh – CI helper that runs all COCOON deployment checks
#
# This script executes the project's prerequisite, configuration, and system
# health checks sequentially, collects their exit codes, and reports a concise
# summary. It supports a human-readable (colorized) table and a `--json` mode
# suitable for CI pipelines.
#
# Checks executed (in order):
#   1. check-prerequisites.sh  – prerequisite validation
#   2. validate-config.sh      – worker-*.conf configuration validation
#   3. system-health.sh        – system health check
#
# Exit code is 0 when all checks pass, 1 otherwise (in both modes).

set -u

# Colors for human-readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat <<'EOF'
Usage: ci-validate.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing each check with status and remediation hint.

JSON schema (when --json is set):
  {
    "checks": [
      {"name": "prerequisites", "status": "pass|fail", "hint": "..."},
      {"name": "config",        "status": "pass|fail", "hint": "..."},
      {"name": "system_health", "status": "pass|fail", "hint": "..."}
    ],
    "overall_status": "passed|failed",
    "exit_code": 0|1
  }

Exit code is 0 when overall_status is "passed", 1 otherwise (in both modes).
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

# Determine the repository root (directory containing this script).
# This allows the script to be invoked from any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ordered list of checks: name, script path, and a remediation hint shown on FAIL.
# Each entry is a triple separated by '|'.
CHECKS=(
    "prerequisites|check-prerequisites.sh|Review the prerequisite output above and resolve any hard failures (e.g. missing QEMU)."
    "config|validate-config.sh|Run ./validate-config.sh for details and fix invalid worker-*.conf values."
    "system_health|system-health.sh|Run ./system-health.sh for details and follow the per-check remediation hints."
)

# Storage for results (parallel arrays)
CHECK_NAMES=()
CHECK_STATUS=()
CHECK_HINTS=()

OVERALL_EXIT=0

# Run each check sequentially, capturing its exit code.
for entry in "${CHECKS[@]}"; do
    IFS='|' read -r name script hint <<< "$entry"
    CHECK_NAMES+=("$name")

    # Capture the script's output so we can surface it in human mode.
    output=""
    if "$SCRIPT_DIR/$script" > /tmp/ci-validate-$$.log 2>&1; then
        status="pass"
        CHECK_STATUS+=("pass")
        CHECK_HINTS+=("")
    else
        status="fail"
        CHECK_STATUS+=("fail")
        CHECK_HINTS+=("$hint")
        OVERALL_EXIT=1
    fi
    output=$(cat /tmp/ci-validate-$$.log 2>/dev/null || true)
    rm -f /tmp/ci-validate-$$.log

    # Store output for potential human-mode display (not needed for JSON).
    CHECK_OUTPUTS+=("$output")
done

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if [[ "$OUTPUT_JSON" == true ]]; then
    checks_json="["
    for idx in "${!CHECK_NAMES[@]}"; do
        name_esc=$(json_escape "${CHECK_NAMES[$idx]}")
        status_esc=$(json_escape "${CHECK_STATUS[$idx]}")
        hint_esc=$(json_escape "${CHECK_HINTS[$idx]}")
        if [[ $idx -gt 0 ]]; then
            checks_json+=","
        fi
        checks_json+="{\"name\":\"$name_esc\",\"status\":\"$status_esc\",\"hint\":\"$hint_esc\"}"
    done
    checks_json+="]"

    if [[ $OVERALL_EXIT -eq 0 ]]; then
        overall="passed"
    else
        overall="failed"
    fi

    printf '{"checks":%s,"overall_status":"%s","exit_code":%d}\n' \
        "$checks_json" "$overall" "$OVERALL_EXIT"
    exit $OVERALL_EXIT
fi

# ---------------------------------------------------------------------------
# Human-readable mode (colorized table)
# ---------------------------------------------------------------------------
echo -e "${BLUE}=== COCOON CI Validation ===${NC}"
echo ""

# Print table header
printf "%-20s %-10s %s\n" "Check" "Status" "Hint"
printf "%-20s %-10s %s\n" "--------------------" "----------" "----------------------------------------"

for idx in "${!CHECK_NAMES[@]}"; do
    name="${CHECK_NAMES[$idx]}"
    status="${CHECK_STATUS[$idx]}"
    hint="${CHECK_HINTS[$idx]}"

    if [[ "$status" == "pass" ]]; then
        status_colored="${GREEN}PASS${NC}"
        hint_colored=""
    else
        status_colored="${RED}FAIL${NC}"
        hint_colored="${YELLOW}$hint${NC}"
    fi

    printf "%-20s %b %b\n" "$name" "$status_colored" "$hint_colored"
done

echo ""
if [[ $OVERALL_EXIT -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
else
    echo -e "${RED}One or more checks failed.${NC}"
fi

exit $OVERALL_EXIT
