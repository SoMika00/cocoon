#!/bin/bash
# Watchdog for COCOON workers: monitors PIDs and /stats, restarts on failure

set -e

MAX_RETRIES=5
BACKOFF=10
DRY_RUN=false
LOG_FILE="logs/watchdog.log"

mkdir -p logs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 [--max-retries N] [--backoff SECONDS] [--dry-run]"
    echo "  --max-retries N   Max restart attempts per worker (default: 5)"
    echo "  --backoff SECONDS Sleep seconds between checks (default: 10)"
    echo "  --dry-run         Log intended actions without executing restarts"
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

check_and_restart() {
    local worker=$1
    local pid_file="logs/worker-${worker}.pid"
    local port=$((12000 + worker*10))
    local retries=0

    while [ $retries -lt $MAX_RETRIES ]; do
        if [ ! -f "$pid_file" ]; then
            log "PID file missing for worker $worker"
            restart_worker "$worker"
            ((retries++))
            sleep "$BACKOFF"
            continue
        fi

        pid=$(cat "$pid_file")
        if ! ps -p "$pid" > /dev/null 2>&1; then
            log "Process missing for worker $worker (PID $pid)"
            restart_worker "$worker"
            ((retries++))
            sleep "$BACKOFF"
            continue
        fi

        code=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:${port}/stats" || echo 000)
        if [ "$code" != "200" ]; then
            log "/stats non-200 ($code) for worker $worker"
            restart_worker "$worker"
            ((retries++))
            sleep "$BACKOFF"
            continue
        fi

        # Healthy
        return 0
    done

    log "Max retries ($MAX_RETRIES) reached for worker $worker - manual intervention needed"
}

log "Watchdog started (max-retries=$MAX_RETRIES, backoff=${BACKOFF}s, dry-run=$DRY_RUN)"

while true; do
    check_and_restart 0
    check_and_restart 1
    sleep "$BACKOFF"
done
