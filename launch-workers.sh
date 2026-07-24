#!/bin/bash
# Launch script for 2 H100 workers

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

FORCE=false
DRY_RUN=false
WAIT_READY=false
TIMEOUT=120

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --wait-ready)
            WAIT_READY=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--dry-run] [--wait-ready] [--timeout N]"
            echo "  --force       Skip prerequisite validation (not recommended)"
            echo "  --dry-run     Validate prerequisites, print planned commands and exit without starting workers"
            echo "  --wait-ready  Poll worker /stats endpoints until both respond with 200 (or timeout)"
            echo "  --timeout N   Seconds to wait for ready (default: 120)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

validate_prerequisites() {
    local errors=0

    echo "=== Prerequisite Validation ==="
    echo ""

    # 1. Check seal-server process
    if ! pgrep -f "seal-server" > /dev/null; then
        echo -e "${RED}✗${NC} seal-server is not running"
        echo "  Next step: Start it with: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
        ((errors++))
    else
        echo -e "${GREEN}✓${NC} seal-server is running"
    fi

    # 2. Check worker config files and required keys
    for worker in 0 1; do
        conf="worker-${worker}.conf"
        if [ ! -f "$conf" ]; then
            # Try parent dir
            if [ -f "../$conf" ]; then
                cp "../$conf" .
                echo -e "${GREEN}✓${NC} Copied $conf from parent"
            else
                echo -e "${RED}✗${NC} $conf not found"
                echo "  Next step: Run setup-h100.sh or create from worker.conf.template"
                ((errors++))
                continue
            fi
        fi

        # Check for non-placeholder values
        for key in owner_address node_wallet_key hf_token root_contract_address; do
            val=$(grep "^${key}" "$conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
            if [ -z "$val" ] || [[ "$val" == YOUR_* ]] || [[ "$val" == "[PRIVATE]" ]]; then
                echo -e "${RED}✗${NC} $conf: $key has placeholder or empty value"
                echo "  Next step: Edit $conf and set a real value for $key"
                ((errors++))
            fi
        done
        if [ $errors -eq 0 ]; then
            echo -e "${GREEN}✓${NC} $conf validated"
        fi
    done

    # 3. Check both H100 GPUs via lspci
    GPU_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
    if [ "$GPU_COUNT" -lt 2 ]; then
        echo -e "${RED}✗${NC} Less than 2 H100 GPUs detected (found: $GPU_COUNT)"
        echo "  Next step: Verify hardware / lspci | grep -i nvidia"
        ((errors++))
    else
        echo -e "${GREEN}✓${NC} Both H100 GPUs detected"
    fi

    # 4. Verify binaries are executable
    if [ -f "./scripts/cocoon-launch" ]; then
        if [ ! -x "./scripts/cocoon-launch" ]; then
            echo -e "${YELLOW}⚠${NC} cocoon-launch not executable (fixing...)"
            chmod +x "./scripts/cocoon-launch"
        fi
        echo -e "${GREEN}✓${NC} cocoon-launch binary present and executable"
    else
        echo -e "${RED}✗${NC} cocoon-launch not found"
        echo "  Next step: Ensure COCOON distribution is extracted in current dir"
        ((errors++))
    fi

    if [ -f "./bin/seal-server" ]; then
        if [ ! -x "./bin/seal-server" ]; then
            echo -e "${YELLOW}⚠${NC} seal-server not executable (fixing...)"
            chmod +x "./bin/seal-server"
        fi
        echo -e "${GREEN}✓${NC} seal-server binary present and executable"
    else
        echo -e "${RED}✗${NC} seal-server binary not found"
        echo "  Next step: Download/extract COCOON distribution"
        ((errors++))
    fi

    echo ""
    if [ $errors -gt 0 ]; then
        echo -e "${RED}Validation failed with $errors error(s).${NC}"
        echo "Use --force to bypass (not recommended)."
        return 1
    fi
    echo -e "${GREEN}All prerequisites validated successfully.${NC}"
    return 0
}

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

# Run validation unless --force
if [ "$FORCE" != true ]; then
    if ! validate_prerequisites; then
        exit 1
    fi
else
    echo -e "${YELLOW}--force specified: skipping prerequisite validation${NC}"
fi

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== DRY RUN: Planned commands ==="
    echo ""
    echo "# Worker 0"
    echo "./scripts/cocoon-launch $MODE_FLAGS --instance 0 --gpu $GPU1 worker-0.conf > logs/worker-0.log 2>&1 &"
    echo ""
    echo "# Worker 1"
    echo "./scripts/cocoon-launch $MODE_FLAGS --instance 1 --gpu $GPU2 worker-1.conf > logs/worker-1.log 2>&1 &"
    echo ""
    echo -e "${GREEN}Dry-run completed successfully. No processes started, no logs/PID files written.${NC}"
    exit 0
fi

# Check if seal-server is running (still warn even with force)
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

# Wait-ready polling (skipped in dry-run)
if [ "$WAIT_READY" = true ]; then
    echo ""
    echo "Waiting for workers to become ready (timeout: ${TIMEOUT}s)..."
    start_time=$(date +%s)
    delay=5
    while true; do
        code0=$(curl -s --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:12000/stats || echo 000)
        code1=$(curl -s --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:12010/stats || echo 000)
        if [ "$code0" = "200" ] && [ "$code1" = "200" ]; then
            echo -e "${GREEN}Workers ready${NC}"
            exit 0
        fi
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if [ $elapsed -ge $TIMEOUT ]; then
            echo -e "${RED}Error: Timeout after ${TIMEOUT}s waiting for workers${NC}"
            exit 1
        fi
        echo "Retry attempt, waiting ${delay}s before next poll..."
        sleep $delay
        delay=$((delay * 2))
        if [ $delay -gt 30 ]; then
            delay=30
        fi
    done
fi
