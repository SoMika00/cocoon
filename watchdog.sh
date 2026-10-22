#!/bin/bash
# Watchdog for COCOON workers: monitors PIDs and /stats, restarts on failure

set -e

MAX_RETRIES=5
BACKOFF=10
DRY_RUN=false
JSON=false
ONCE=false
LOG_FILE="logs/watchdog.log"

mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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

usage() {
    echo "Usage: $0 [--max-retries N] [--backoff SECONDS] [--dry-run] [--json] [--once]"
    echo "  --max-retries N   Max restart attempts per worker (default: 5)"
    echo "  --backoff SECONDS Sleep seconds between checks (default: 10)"
    echo "  --dry-run         Log intended actions without executing restarts"
    echo "  --json            Emit a single machine-readable JSON object on stdout"
    echo "                    describing config and per-worker health/restart state."
    echo "                    Implies a single monitoring pass (same as --once)."
    echo "  --once            Run exactly one monitoring pass and exit (no infinite loop)"
    echo ""
    echo "JSON schema (when --json is set):"
    echo "  {"
    echo "    \"config\": {\"max_retries\": 5, \"backoff\": 10, \"dry_run\": false},"
    echo "    \"workers\": ["
    echo "      {\"instance\":0,\"pid\":12345,\"pid_file\":\"logs/worker-0.pid\",\"port\":12000,\"process_alive\":true,\"stats_http_code\":200,\"healthy\":true,\"restarts\":0},"
    echo "      {\"instance\":1,\"pid\":null,\"pid_file\":\"logs/worker-1.pid\",\"port\":12010,\"process_alive\":false,\"stats_http_code\":0,\"healthy\":false,\"restarts\":1}"
    echo "    ],"
    echo "    \"overall_status\": \"ok|degraded\","
    echo "    \"exit_code\": 0|1"
    echo "  }"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --backoff)
            BACKOFF="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON=true
            ONCE=true
            shift
            ;;
        --once)
            ONCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

restart_worker() {
    local worker=$1
    local pid_file="logs/worker-${worker}.pid"
    local conf="worker-${worker}.conf"
    local gpu
    if [ "$worker" = "0" ]; then
        gpu=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
    else
        gpu=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')
    fi

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would restart worker $worker (gpu=$gpu)"
        return 0
    fi

    log "Restarting worker $worker..."
    if [ -f "$pid_file" ]; then
        old_pid=$(cat "$pid_file")
        kill "$old_pid" 2>/dev/null || true
    fi

    nohup ./scripts/cocoon-launch --instance "$worker" --gpu "$gpu" "$conf" > "logs/worker-${worker}.log" 2>&1 &
    new_pid=$!
    echo "$new_pid" > "$pid_file"
    log "Worker $worker restarted with PID $new_pid (attempts left: $((MAX_RETRIES-1)))"
}

# check_worker performs a single health check for one worker and, if unhealthy,
# attempts a restart. It sets the following global variables describing the
# worker's state for the current pass:
#   W_PROCESS_ALIVE  (true|false)
#   W_STATS_CODE     (HTTP status code, 0 if not reachable)
#   W_HEALTHY        (true|false)
#   W_RESTARTS       (number of restart attempts performed this pass)
#   W_PID            (current PID or null)
check_worker() {
    local worker=$1
    local pid_file="logs/worker-${worker}.pid"
    local port=$((12000 + worker*10))

    W_PROCESS_ALIVE=false
    W_STATS_CODE=0
    W_HEALTHY=false
    W_RESTARTS=0
    W_PID=null

    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            W_PROCESS_ALIVE=true
            W_PID="$pid"
        fi
    fi

    if [ "$W_PROCESS_ALIVE" = true ]; then
        code=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:${port}/stats" 2>/dev/null || echo 000)
        W_STATS_CODE="$code"
        if [ "$code" = "200" ]; then
            W_HEALTHY=true
        fi
    fi

    # If unhealthy, attempt restarts up to MAX_RETRIES
    if [ "$W_HEALTHY" != true ]; then
        local retries=0
        while [ $retries -lt $MAX_RETRIES ]; do
            if [ "$W_PROCESS_ALIVE" != true ]; then
                log "Process missing for worker $worker"
            elif [ ! -f "$pid_file" ]; then
                log "PID file missing for worker $worker"
            else
                log "/stats non-200 ($W_STATS_CODE) for worker $worker"
            fi
            restart_worker "$worker"
            ((retries++))
            W_RESTARTS=$retries

            # Re-check state after restart
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file")
                if ps -p "$pid" > /dev/null 2>&1; then
                    W_PROCESS_ALIVE=true
                    W_PID="$pid"
                else
                    W_PROCESS_ALIVE=false
                    W_PID=null
                fi
            else
                W_PROCESS_ALIVE=false
                W_PID=null
            fi

            if [ "$W_PROCESS_ALIVE" = true ]; then
                code=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:${port}/stats" 2>/dev/null || echo 000)
                W_STATS_CODE="$code"
                if [ "$code" = "200" ]; then
                    W_HEALTHY=true
                    break
                fi
            fi

            sleep "$BACKOFF"
        done

        if [ "$W_HEALTHY" != true ]; then
            log "Max retries ($MAX_RETRIES) reached for worker $worker - manual intervention needed"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Single monitoring pass
# ---------------------------------------------------------------------------
run_pass() {
    check_worker 0
    W0_PROCESS_ALIVE=$W_PROCESS_ALIVE
    W0_STATS_CODE=$W_STATS_CODE
    W0_HEALTHY=$W_HEALTHY
    W0_RESTARTS=$W_RESTARTS
    W0_PID=$W_PID

    check_worker 1
    W1_PROCESS_ALIVE=$W_PROCESS_ALIVE
    W1_STATS_CODE=$W_STATS_CODE
    W1_HEALTHY=$W_HEALTHY
    W1_RESTARTS=$W_RESTARTS
    W1_PID=$W_PID
}

log "Watchdog started (max-retries=$MAX_RETRIES, backoff=${BACKOFF}s, dry-run=$DRY_RUN)"

if [ "$JSON" = true ]; then
    run_pass

    # Determine overall status and exit code
    if [ "$W0_HEALTHY" = true ] && [ "$W1_HEALTHY" = true ] && [ "$W0_RESTARTS" -eq 0 ] && [ "$W1_RESTARTS" -eq 0 ]; then
        OVERALL="ok"
        EXIT_CODE=0
    else
        OVERALL="degraded"
        EXIT_CODE=1
    fi

    # Build workers array
    workers_json="["
    workers_json+="{\"instance\":0,\"pid\":$W0_PID,\"pid_file\":\"logs/worker-0.pid\",\"port\":12000,\"process_alive\":$W0_PROCESS_ALIVE,\"stats_http_code\":$W0_STATS_CODE,\"healthy\":$W0_HEALTHY,\"restarts\":$W0_RESTARTS}"
    workers_json+=",{\"instance\":1,\"pid\":$W1_PID,\"pid_file\":\"logs/worker-1.pid\",\"port\":12010,\"process_alive\":$W1_PROCESS_ALIVE,\"stats_http_code\":$W1_STATS_CODE,\"healthy\":$W1_HEALTHY,\"restarts\":$W1_RESTARTS}"
    workers_json+="]"

    printf '{"config":{"max_retries":%s,"backoff":%s,"dry_run":%s},"workers":%s,"overall_status":"%s","exit_code":%d}\n' \
        "$MAX_RETRIES" "$BACKOFF" "$DRY_RUN" "$workers_json" "$OVERALL" "$EXIT_CODE"

    exit $EXIT_CODE
fi

# ---------------------------------------------------------------------------
# Human-readable mode (unchanged behavior)
# ---------------------------------------------------------------------------
while true; do
    check_worker 0
    check_worker 1
    if [ "$ONCE" = true ]; then
        break
    fi
    sleep "$BACKOFF"
done
