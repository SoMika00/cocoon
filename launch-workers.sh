#!/bin/bash
# Launch script for 2 H100 workers

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== COCOON H100 Workers Launcher ==="
echo ""

# Check if we're in the right directory
# Try release-8728fe7 first, then current directory
if [ -f "./release-8728fe7/scripts/cocoon-launch" ]; then
    COCOON_DIR="./release-8728fe7"
elif [ -f "./scripts/cocoon-launch" ]; then
    COCOON_DIR="."
else
    echo -e "${RED}Error: cocoon-launch script not found${NC}"
    echo "Please run this script from the cocoon directory"
    exit 1
fi

cd "$COCOON_DIR"

# Check if seal-server is running
if ! pgrep -f "seal-server" > /dev/null; then
    echo -e "${YELLOW}Warning: seal-server does not appear to be running${NC}"
    echo "seal-server is required for production mode."
    echo "Start it with: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if config files exist
if [ ! -f "worker-0.conf" ]; then
    # Try to copy from parent directory
    if [ -f "../worker-0.conf" ]; then
        cp ../worker-0.conf .
        echo -e "${GREEN}Copied worker-0.conf from parent directory${NC}"
    else
        echo -e "${RED}Error: worker-0.conf not found${NC}"
        echo "Please create configuration files first"
        exit 1
    fi
fi

if [ ! -f "worker-1.conf" ]; then
    # Try to copy from parent directory
    if [ -f "../worker-1.conf" ]; then
        cp ../worker-1.conf .
        echo -e "${GREEN}Copied worker-1.conf from parent directory${NC}"
    else
        echo -e "${RED}Error: worker-1.conf not found${NC}"
        echo "Please create configuration files first"
        exit 1
    fi
fi

# Detect GPUs
GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')

echo "GPU Configuration:"
echo "  Worker 0: $GPU1"
echo "  Worker 1: $GPU2"
echo ""

# Ask for mode
echo "Select launch mode:"
echo "1) Production mode (requires seal-server)"
echo "2) Test mode (with debug shell, real TON)"
echo "3) Test mode (with debug shell, fake TON)"
read -p "Choice [1-3]: " -n 1 -r
echo ""

MODE_FLAGS=""
case $REPLY in
    1)
        MODE_FLAGS=""
        echo -e "${GREEN}Launching in PRODUCTION mode${NC}"
        ;;
    2)
        MODE_FLAGS="--test"
        echo -e "${YELLOW}Launching in TEST mode (real TON)${NC}"
        ;;
    3)
        MODE_FLAGS="--test --fake-ton"
        echo -e "${YELLOW}Launching in TEST mode (fake TON)${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo "Starting workers..."
echo ""

# Create log directory
mkdir -p logs

# Launch worker 0
echo -e "${GREEN}Starting Worker 0 (GPU: $GPU1)...${NC}"
nohup ./scripts/cocoon-launch $MODE_FLAGS --instance 0 --gpu $GPU1 worker-0.conf > logs/worker-0.log 2>&1 &
WORKER0_PID=$!
echo "Worker 0 PID: $WORKER0_PID"

# Wait a bit before starting second worker
sleep 2

# Launch worker 1
echo -e "${GREEN}Starting Worker 1 (GPU: $GPU2)...${NC}"
nohup ./scripts/cocoon-launch $MODE_FLAGS --instance 1 --gpu $GPU2 worker-1.conf > logs/worker-1.log 2>&1 &
WORKER1_PID=$!
echo "Worker 1 PID: $WORKER1_PID"

echo ""
echo -e "${GREEN}=== Workers Started ===${NC}"
echo ""
echo "Worker 0:"
echo "  PID: $WORKER0_PID"
echo "  GPU: $GPU1"
echo "  Port: 12000"
echo "  Log: logs/worker-0.log"
echo ""
echo "Worker 1:"
echo "  PID: $WORKER1_PID"
echo "  GPU: $GPU2"
echo "  Port: 12010"
echo "  Log: logs/worker-1.log"
echo ""
echo "Monitor workers:"
echo "  tail -f logs/worker-0.log"
echo "  tail -f logs/worker-1.log"
echo ""
echo "Check stats:"
echo "  curl http://localhost:12000/stats  # Worker 0"
echo "  curl http://localhost:12010/stats  # Worker 1"
echo ""
echo "Stop workers:"
echo "  kill $WORKER0_PID $WORKER1_PID"

# Save PIDs to file
echo "$WORKER0_PID" > logs/worker-0.pid
echo "$WORKER1_PID" > logs/worker-1.pid

