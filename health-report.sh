#!/usr/bin/env bash

# health-report.sh – Unified health report for the COCOON node
#
# Aggregates GPU utilization, worker status, and system health into a single
# consolidated JSON report. It invokes the existing sub-scripts:
#   - gpu-utilization.sh --json
#   - status-workers.sh --json
#   - system-health.sh --json
#
# The merged report is emitted under top-level keys `gpu`, `workers`, and
# `system`, plus a computed `overall_status` field.
#
# overall_status is "ok" only when:
#   - every GPU reports healthy == true,
#   - every worker reports running == true,
#   - system-health reports overall_status == "ok".
# Otherwise it is "degraded".
#
# Exit codes:
#   0  overall_status == "ok"
#   1  overall_status == "degraded"
#   2  a required sub-script is missing, fails, or produces invalid JSON
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
Usage: health-report.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Print the merged JSON report (default)
  --human          Print a concise human-readable summary

JSON schema (when --json is set):
  {
    "gpu":     <output of gpu-utilization.sh --json>,
    "workers": <output of status-workers.sh --json>,
    "system":  <output of system-health.sh --json>,
    "overall_status": "ok|degraded"
  }

Exit codes:
  0  overall_status is "ok"
  1  overall_status is "degraded"
  2  a required sub-script is missing, fails, or produces invalid JSON
EOF
}

# Parse arguments
MODE="json"
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

# Run a sub-script and capture its JSON output. On any failure (missing script,
# non-zero exit code, or invalid JSON), print an error and exit 2.
run_subreport() {
    local name="$1"
    local script="$2"

    if [[ ! -x "$SCRIPT_DIR/$script" ]]; then
        echo "Error: required sub-script '$script' is missing or not executable" >&2
        exit 2
    fi

    local output
    if ! output=$("$SCRIPT_DIR/$script" --json 2>/dev/null); then
        echo "Error: '$script --json' exited with a non-zero status" >&2
        exit 2
    fi

    if ! echo "$output" | jq -e . >/dev/null 2>&1; then
        echo "Error: '$script --json' produced invalid JSON" >&2
        exit 2
    fi

    printf '%s' "$output"
}

# Collect the three sub-reports.
GPU_JSON=$(run_subreport "gpu" "gpu-utilization.sh")
WORKERS_JSON=$(run_subreport "workers" "status-workers.sh")
SYSTEM_JSON=$(run_subreport "system" "system-health.sh")

# Compute overall_status using jq.
#
#   gpu_ok      -> all GPUs healthy (true when the gpus array is empty or all
#                  entries have healthy == true)
#   workers_ok  -> all workers running (true when the workers array is empty or
#                  all entries have running == true)
#   system_ok   -> system.overall_status == "ok"
OVERALL_STATUS=$(jq -n \
    --argjson gpu "$GPU_JSON" \
    --argjson workers "$WORKERS_JSON" \
    --argjson system "$SYSTEM_JSON" \
    '(
        ($gpu.gpus // []) | all(.healthy == true)
      ) and (
        ($workers.workers // []) | all(.running == true)
      ) and (
        ($system.overall_status // "") == "ok"
      ) | if . then "ok" else "degraded" end')

# Build the merged JSON object.
MERGED_JSON=$(jq -n \
    --argjson gpu "$GPU_JSON" \
    --argjson workers "$WORKERS_JSON" \
    --argjson system "$SYSTEM_JSON" \
    --arg overall "$OVERALL_STATUS" \
    '{gpu: $gpu, workers: $workers, system: $system, overall_status: $overall}')

if [[ "$MODE" == "json" ]]; then
    printf '%s\n' "$MERGED_JSON"
else
    # Human-readable summary
    GPU_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$GPU_JSON")
    WORKERS_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$WORKERS_JSON")
    SYSTEM_STATUS=$(jq -r '.overall_status // "unknown"' <<< "$SYSTEM_JSON")

    echo -e "${BLUE}=== COCOON Health Report ===${NC}"
    echo ""

    printf "%-20s %s\n" "Component" "Status"
    printf "%-20s %s\n" "--------------------" "----------"

    if [[ "$GPU_STATUS" == "ok" ]]; then
        printf "%-20s %b\n" "GPU utilization" "${GREEN}ok${NC}"
    else
        printf "%-20s %b\n" "GPU utilization" "${RED}$GPU_STATUS${NC}"
    fi

    if [[ "$WORKERS_STATUS" == "ok" ]]; then
        printf "%-20s %b\n" "Workers" "${GREEN}ok${NC}"
    else
        printf "%-20s %b\n" "Workers" "${RED}$WORKERS_STATUS${NC}"
    fi

    if [[ "$SYSTEM_STATUS" == "ok" ]]; then
        printf "%-20s %b\n" "System health" "${GREEN}ok${NC}"
    else
        printf "%-20s %b\n" "System health" "${RED}$SYSTEM_STATUS${NC}"
    fi

    echo ""
    if [[ "$OVERALL_STATUS" == "ok" ]]; then
        echo -e "${GREEN}Overall status: ok${NC}"
    else
        echo -e "${RED}Overall status: degraded${NC}"
    fi
fi

if [[ "$OVERALL_STATUS" == "ok" ]]; then
    exit 0
else
    exit 1
fi
