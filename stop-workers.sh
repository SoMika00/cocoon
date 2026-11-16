#!/bin/bash
# Stop script for 2 H100 workers

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
Usage: stop-workers.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing the shutdown result for both workers and the
                   watchdog. Suppresses all human-readable output.

JSON schema (when --json is set):
  {
    "workers": [
      {"instance":0,"pid":12345,"pid_file":"logs/worker-0.pid","was_running":true,"stopped":true},
      {"instance":1,"pid":null,"pid_file":"logs/worker-1.pid","was_running":false,"stopped":false}
    ],
    "watchdog": {"was_running":true,"stopped":true},
    "overall_status": "ok|degraded",
    "exit_code": 0|1
  }

overall_status is "ok" when every worker that was running is now stopped and
the watchdog (if running) is stopped; otherwise "degraded". exit_code mirrors
overall_status (0 for ok, 1 for degraded).
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
# Stop a single worker by PID file. Sets global variables describing the
# worker's state for this shutdown:
#   W_PID          (PID read from pid file, or null)
#   W_WAS_RUNNING  (true|false)
#   W_STOPPED      (true|false)
# ---------------------------------------------------------------------------
stop_worker() {
    local instance=$1
    local pid_file="logs/worker-${instance}.pid"

    W_PID=null
    W_WAS_RUNNING=false
    W_STOPPED=false

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
            W_PID="$pid"
            if ps -p "$pid" > /dev/null 2>&1; then
                W_WAS_RUNNING=true
                if kill "$pid" 2>/dev/null; then
                    W_STOPPED=true
                else
                    W_STOPPED=false
                fi
            else
                # PID file present but process not running
                W_WAS_RUNNING=false
                W_STOPPED=false
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Stop the watchdog process (if any). Sets global variables:
#   WD_WAS_RUNNING  (true|false)
#   WD_STOPPED      (true|false)
# ---------------------------------------------------------------------------
stop_watchdog() {
    WD_WAS_RUNNING=false
    WD_STOPPED=false

    local wd_pid
    wd_pid=$(pgrep -f "watchdog.sh" 2>/dev/null | head -n1 || true)
    if [[ -n "$wd_pid" ]]; then
        WD_WAS_RUNNING=true
        if kill "$wd_pid" 2>/dev/null; then
            WD_STOPPED=true
        else
            WD_STOPPED=false
        fi
    fi
}

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if [[ "$JSON" == true ]]; then
    stop_worker 0
    W0_PID=$W_PID
    W0_WAS_RUNNING=$W_WAS_RUNNING
    W0_STOPPED=$W_STOPPED

    stop_worker 1
    W1_PID=$W_PID
    W1_WAS_RUNNING=$W_WAS_RUNNING
    W1_STOPPED=$W_STOPPED

    stop_watchdog

    # Determine overall status: ok when every running worker is stopped and
    # the watchdog (if running) is stopped.
    OVERALL="ok"
    EXIT_CODE=0

    if [[ "$W0_WAS_RUNNING" == true && "$W0_STOPPED" != true ]]; then
        OVERALL="degraded"
        EXIT_CODE=1
    fi
    if [[ "$W1_WAS_RUNNING" == true && "$W1_STOPPED" != true ]]; then
        OVERALL="degraded"
        EXIT_CODE=1
    fi
    if [[ "$WD_WAS_RUNNING" == true && "$WD_STOPPED" != true ]]; then
        OVERALL="degraded"
        EXIT_CODE=1
    fi

    workers_json="["
    workers_json+="{\"instance\":0,\"pid\":$W0_PID,\"pid_file\":\"logs/worker-0.pid\",\"was_running\":$W0_WAS_RUNNING,\"stopped\":$W0_STOPPED}"
    workers_json+=",{\"instance\":1,\"pid\":$W1_PID,\"pid_file\":\"logs/worker-1.pid\",\"was_running\":$W1_WAS_RUNNING,\"stopped\":$W1_STOPPED}"
    workers_json+="]"

    watchdog_json="{\"was_running\":$WD_WAS_RUNNING,\"stopped\":$WD_STOPPED}"

    printf '{"workers":%s,"watchdog":%s,"overall_status":"%s","exit_code":%d}\n' \
        "$workers_json" "$watchdog_json" "$OVERALL" "$EXIT_CODE"

    exit $EXIT_CODE
fi

# ---------------------------------------------------------------------------
# Human-readable mode (unchanged behavior)
# ---------------------------------------------------------------------------
echo -e "${BLUE}=== Arrêt des Workers COCOON ===${NC}"
echo ""

# Stop workers
for worker in 0 1; do
    pid_file="logs/worker-${worker}.pid"
    if [[ -f "$pid_file" ]]; then
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}Arrêt du worker ${worker} (PID: ${pid})...${NC}"
            if kill "$pid" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} Worker ${worker} arrêté"
            else
                echo -e "${RED}✗${NC} Échec de l'arrêt du worker ${worker}"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Worker ${worker} non en cours d'exécution (PID: ${pid:-inconnu})"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Fichier PID manquant pour worker ${worker} (${pid_file})"
    fi
done

echo ""

# Stop watchdog
wd_pid=$(pgrep -f "watchdog.sh" 2>/dev/null | head -n1 || true)
if [[ -n "$wd_pid" ]]; then
    echo -e "${YELLOW}Arrêt du watchdog (PID: ${wd_pid})...${NC}"
    if kill "$wd_pid" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Watchdog arrêté"
    else
        echo -e "${RED}✗${NC} Échec de l'arrêt du watchdog"
    fi
else
    echo -e "${YELLOW}⚠${NC} Watchdog non détecté"
fi

echo ""
echo -e "${GREEN}Arrêt terminé.${NC}"
