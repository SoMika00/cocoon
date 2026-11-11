#!/usr/bin/env bash

# cocoon-status.sh – Consolidated health status for the entire COCOON node
#
# Aggregates the health of the whole node (prerequisites, GPU utilization,
# system health, and worker status) into a single machine-readable JSON report
# so that CI pipelines and monitoring tools can quickly assess node readiness.
#
# It invokes the existing sub-scripts with their --json flags:
#   - check-prerequisites.sh --json
#   - gpu-utilization.sh    --json
#   - system-health.sh      --json
#   - status-workers.sh     --json
#
# The merged report is emitted under top-level keys:
#   prerequisites, gpu_utilization, system_health, workers
# plus a computed `overall_status` field.
#
# overall_status is:
#   "ok"       when every sub-script exits 0 and reports no errors
#   "degraded" when any sub-script reports warnings but is still functional
#   "failed"   when any sub-script reports a failure (non-zero exit code or
#              its own overall_status == "failed")
#
# Exit codes:
#   0  overall_status == "ok"
#   1  otherwise (degraded or failed)
#   2  a required sub-script is missing, fails to run, or produces invalid JSON
#
# Requires `jq` (already required by other scripts).

set -u

# Colors for human-readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat <<'EOF'
Usage: cocoon-status.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Print the merged JSON report
  --human          Print a concise human-readable summary (default)

JSON schema (when --json is set):
  {
    "prerequisites":   <output of check-prerequisites.sh --json>,
    "gpu_utilization": <output of gpu-utilization.sh --json>,
    "system_health":   <output of system-health.sh --json>,
    "workers":         <output of status-workers.sh --json>,
    "overall_status":  "ok|degraded|failed"
  }

Exit codes:
  0  overall_status is "ok"
  1  overall_status is "degraded" or "failed"
  2  a required sub-script is missing, fails, or produces invalid JSON
EOF
}

# Parse arguments
MODE="human"
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        --json)
            MODE="json"
            shift
            ;;
        --human)
            MODE="human"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 2
            ;;
    esac
done

# Determine the repository root (directory containing this script).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure jq is available (required dependency).
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not found in PATH" >&2
    exit 2
fi

# Run a sub-script and capture its JSON output and exit code.
# On a missing script or invalid JSON, print an error and exit 2.
# Sets the global variables SUB_JSON and SUB_EXIT.
run_subreport() {
    local name="$1"
    local script="$2"

    if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
        echo "Error: required sub-script '$script' is missing or not executable" >&2
        exit 2
    fi

    local output
    output=$("$SCRIPT_DIR/$script" --json 2>/dev/null)
    SUB_EXIT=$?

    if ! echo "$output" | jq -e . >/dev/null 2>&1; then
        echo "Error: '$script --json' produced invalid JSON" >&2
        exit 2
    fi

    SUB_JSON="$output"
}

# Collect the four sub-reports.
run_subreport "prerequisites" "check-prerequisites.sh"
PREREQ_JSON="$SUB_JSON"
PREREQ_EXIT=$SUB_EXIT

run_subreport "gpu_utilization" "gpu-utilization.sh"
GPU_JSON="$SUB_JSON"
GPU_EXIT=$SUB_EXIT

run_subreport "system_health" "system-health.sh"
SYSTEM_JSON="$SUB_JSON"
SYSTEM_EXIT=$SUB_EXIT

run_subreport "workers" "status-workers.sh"
WORKERS_JSON="$SUB_JSON"
WORKERS_EXIT=$SUB_EXIT

# Compute overall_status.
#
# A component is considered a "failure" if:
#   - its sub-script exited non-zero, OR
#   - its own overall_status field is "failed".
#
# A component is considered "degraded" (warning) if its own overall_status is
# "degraded" (or any other non-ok, non-failed value) while still exiting 0.
#
# overall_status is:
#   "failed"   if any component failed
#   "degraded" if any component is degraded/warned
#   "ok"       otherwise
OVERALL_STATUS=$(jq -n \
    --argjson prereq "$PREREQ_JSON" \
    --argjson gpu "$GPU_JSON" \
    --argjson system "$SYSTEM_JSON" \
    --argjson workers "$WORKERS_JSON" \
    --arg prereq_exit "$PREREQ_EXIT" \
    --arg gpu_exit "$GPU_EXIT" \
    --arg system_exit "$SYSTEM_EXIT" \
    --arg workers_exit "$WORKERS_EXIT" \
    '
    def failed($exit):
        ($exit != "0") or ((.overall_status // "") == "failed");
    def degraded($exit):
        ($exit == "0") and ((.overall_status // "") == "degraded");

    if ($prereq | failed($prereq_exit)) or
       ($gpu | failed($gpu_exit)) or
       ($system | failed($system_exit)) or
       ($workers | failed($workers_exit))
    then "failed"
    elif ($prereq | degraded($prereq_exit)) or
         ($gpu | degraded($gpu_exit)) or
         ($system | degraded($system_exit)) or
         ($workers | degraded($workers_exit))
    then "degraded"
    else "ok"
    end')

# Build the merged JSON object.
MERGED_JSON=$(jq -n \
    --argjson prereq "$PREREQ_JSON" \
    --argjson gpu "$GPU_JSON" \
    --argjson system "$SYSTEM_JSON" \
    --argjson workers "$WORKERS_JSON" \
    --arg overall "$OVERALL_STATUS" \
    '{prerequisites: $prereq, gpu_utilization: $gpu, system_health: $system, workers: $workers, overall_status: $overall}')

if [[ "$MODE" == "json" ]]; then
    printf '%s\n' "$MERGED_JSON"
else
    # Human-readable summary
    PREREQ_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$PREREQ_JSON")
    GPU_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$GPU_JSON")
    SYSTEM_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$SYSTEM_JSON")
    WORKERS_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$WORKERS_JSON")

    echo -e "${BLUE}=== COCOON Node Consolidated Status ===${NC}"
    echo ""

    printf "%-20s %s\n" "Component" "Status"
    printf "%-20s %s\n" "--------------------" "----------"

    print_status() {
        local label="$1"
        local status="$2"
        case "$status" in
            ok)
                printf "%-20s %b\n" "$label" "${GREEN}ok${NC}"
                ;;
            degraded)
                printf "%-20s %b\n" "$label" "${YELLOW}degraded${NC}"
                ;;
            *)
                printf "%-20s %b\n" "$label" "${RED}$status${NC}"
                ;;
        esac
    }

    print_status "Prerequisites" "$PREREQ_STATUS"
    print_status "GPU utilization" "$GPU_STATUS"
    print_status "System health" "$SYSTEM_STATUS"
    print_status "Workers" "$WORKERS_STATUS"

    echo ""
    case "$OVERALL_STATUS" in
        ok)
            echo -e "${GREEN}Overall status: ok${NC}"
            ;;
        degraded)
            echo -e "${YELLOW}Overall status: degraded${NC}"
            ;;
        *)
            echo -e "${RED}Overall status: failed${NC}"
            ;;
    esac
fi

if [[ "$OVERALL_STATUS" == "ok" ]]; then
    exit 0
else
    exit 1
fi
