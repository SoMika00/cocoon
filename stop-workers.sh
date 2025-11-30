#!/bin/bash
# Stop COCOON workers

set -e

echo "=== Stopping COCOON Workers ==="
echo ""

if [ -f "logs/worker-0.pid" ]; then
    PID0=$(cat logs/worker-0.pid)
    if ps -p $PID0 > /dev/null 2>&1; then
        echo "Stopping Worker 0 (PID: $PID0)..."
        kill $PID0
        echo "✓ Worker 0 stopped"
    else
        echo "Worker 0 not running"
    fi
    rm -f logs/worker-0.pid
else
    echo "Worker 0 PID file not found"
fi

if [ -f "logs/worker-1.pid" ]; then
    PID1=$(cat logs/worker-1.pid)
    if ps -p $PID1 > /dev/null 2>&1; then
        echo "Stopping Worker 1 (PID: $PID1)..."
        kill $PID1
        echo "✓ Worker 1 stopped"
    else
        echo "Worker 1 not running"
    fi
    rm -f logs/worker-1.pid
else
    echo "Worker 1 PID file not found"
fi

# Also try to kill any remaining cocoon processes
REMAINING=$(pgrep -f "cocoon-launch" || true)
if [ -n "$REMAINING" ]; then
    echo ""
    echo "Found remaining cocoon processes, killing them..."
    pkill -f "cocoon-launch" || true
fi

echo ""
echo "=== Workers Stopped ==="

