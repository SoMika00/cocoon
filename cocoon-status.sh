#!/bin/bash
# Status script for 2 H100 workers

set -u

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

JSON=false

print_help() {
    cat <<'EOF'
Usage: cocoon-status.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing the overall COCOON node status. Suppresses all
                   human-readable output.

JSON schema (when --json is set):
  {
    "workers": [
      {"instance":0,"pid":12345,"pid_file":"logs/worker-0.pid","running":true},
      {"instance":1,"pid":null,"pid_file":"logs/worker-1.pid","running":false}
    ],
    "seal_server": {"running": true|false},
    "gpus": {"count": 2, "h100_count": 2},
    "configs": {"worker0_present": true|false, "worker1_present": true|false},
    "overall_status": "ok|degraded",
    "exit_code": 0|1
  }

overall_status is "ok" only when both workers are running, seal-server is
running, and both worker configs are present; otherwise "degraded". exit_code
mirrors overall_status (0 for ok, 1 for degraded).
EOF
}

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            print_help
            exit 0
            ;;
        --json)
            JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Gather worker state from PID files
# ---------------------------------------------------------------------------
worker_pid() {
    local instance=$1
    local pid_file="logs/worker-${instance}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" > /dev/null 2>&1; then
            printf '%s' "$pid"
            return 0
        fi
    fi
    printf ''
    return 1
}

W0_PID=$(worker_pid 0)
W1_PID=$(worker_pid 1)

if [[ -n "$W0_PID" ]]; then
    W0_RUNNING=true
else
    W0_RUNNING=false
    W0_PID=null
fi

if [[ -n "$W1_PID" ]]; then
    W1_RUNNING=true
else
    W1_RUNNING=false
    W1_PID=null
fi

# ---------------------------------------------------------------------------
# seal-server presence
# ---------------------------------------------------------------------------
if pgrep -f "seal-server" > /dev/null 2>&1; then
    SEAL_RUNNING=true
else
    SEAL_RUNNING=false
fi

# ---------------------------------------------------------------------------
# GPU detection
# ---------------------------------------------------------------------------
GPU_COUNT=$(lspci 2>/dev/null | grep -i nvidia | wc -l)
H100_COUNT=$(lspci 2>/dev/null | grep -i "H100\|GH100" | wc -l)

# ---------------------------------------------------------------------------
# Config file presence
# ---------------------------------------------------------------------------
if [[ -f "worker-0.conf" ]]; then
    CFG0_PRESENT=true
else
    CFG0_PRESENT=false
fi

if [[ -f "worker-1.conf" ]]; then
    CFG1_PRESENT=true
else
    CFG1_PRESENT=false
fi

# ---------------------------------------------------------------------------
# Determine overall status
# ---------------------------------------------------------------------------
if [[ "$W0_RUNNING" == true ]] && [[ "$W1_RUNNING" == true ]] && \
   [[ "$SEAL_RUNNING" == true ]] && \
   [[ "$CFG0_PRESENT" == true ]] && [[ "$CFG1_PRESENT" == true ]]; then
    OVERALL="ok"
    EXIT_CODE=0
else
    OVERALL="degraded"
    EXIT_CODE=1
fi

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if [[ "$JSON" == true ]]; then
    workers_json="[{\"instance\":0,\"pid\":$W0_PID,\"pid_file\":\"logs/worker-0.pid\",\"running\":$W0_RUNNING},{\"instance\":1,\"pid\":$W1_PID,\"pid_file\":\"logs/worker-1.pid\",\"running\":$W1_RUNNING}]"
    seal_json="{\"running\":$SEAL_RUNNING}"
    gpus_json="{\"count\":$GPU_COUNT,\"h100_count\":$H100_COUNT}"
    configs_json="{\"worker0_present\":$CFG0_PRESENT,\"worker1_present\":$CFG1_PRESENT}"

    printf '{"workers":%s,"seal_server":%s,"gpus":%s,"configs":%s,"overall_status":"%s","exit_code":%d}\n' \
        "$workers_json" "$seal_json" "$gpus_json" "$configs_json" "$OVERALL" "$EXIT_CODE"

    exit $EXIT_CODE
fi

# ---------------------------------------------------------------------------
# Human-readable mode (unchanged behavior)
# ---------------------------------------------------------------------------
echo -e "${BLUE}=== COCOON Node Status ===${NC}"
echo ""

# Workers
echo -e "${BLUE}Workers:${NC}"
for worker in 0 1; do
    pid_file="logs/worker-${worker}.pid"
    if [[ -f "$pid_file" ]]; then
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Worker ${worker} running (PID: ${pid})"
        else
            echo -e "  ${YELLOW}⚠${NC} Worker ${worker} not running (PID file present: ${pid:-unknown})"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Worker ${worker} not running (no PID file)"
    fi
done
echo ""

# seal-server
echo -e "${BLUE}seal-server:${NC}"
if [[ "$SEAL_RUNNING" == true ]]; then
    echo -e "  ${GREEN}✓${NC} seal-server is running"
else
    echo -e "  ${RED}✗${NC} seal-server is not running"
fi
echo ""

# GPUs
echo -e "${BLUE}GPUs:${NC}"
echo -e "  NVIDIA GPUs detected: ${GPU_COUNT}"
echo -e "  H100 GPUs detected: ${H100_COUNT}"
echo ""

# Configs
echo -e "${BLUE}Configs:${NC}"
if [[ "$CFG0_PRESENT" == true ]]; then
    echo -e "  ${GREEN}✓${NC} worker-0.conf present"
else
    echo -e "  ${RED}✗${NC} worker-0.conf missing"
fi
if [[ "$CFG1_PRESENT" == true ]]; then
    echo -e "  ${GREEN}✓${NC} worker-1.conf present"
else
    echo -e "  ${RED}✗${NC} worker-1.conf missing"
fi
echo ""

if [[ "$OVERALL" == "ok" ]]; then
    echo -e "${GREEN}Overall status: ok${NC}"
else
    echo -e "${RED}Overall status: degraded${NC}"
fi

exit $EXIT_CODE
