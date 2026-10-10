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
MODE=""
WATCHDOG=false
JSON=false

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
        --mode)
            MODE="$2"
            shift 2
            ;;
        --watchdog)
            WATCHDOG=true
            shift
            ;;
        --json)
            JSON=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--dry-run] [--wait-ready] [--timeout N] [--mode production|test|fake-ton] [--watchdog] [--json]"
            echo "  --force       Skip prerequisite validation (not recommended)"
            echo "  --dry-run     Validate prerequisites, print planned commands and exit without starting workers"
            echo "  --wait-ready  Poll worker /stats endpoints until both respond with 200 (or timeout)"
            echo "  --timeout N   Seconds to wait for ready (default: 120)"
            echo "  --mode MODE   Launch mode: production, test, or fake-ton (non-interactive)"
            echo "  --watchdog    Start watchdog.sh in background after workers launch"
            echo "  --json        Emit a single machine-readable JSON object on stdout instead of human output"
            echo ""
            echo "JSON schema (when --json is set):"
            echo "  {"
            echo "    \"mode\": \"production|test|fake-ton\","
            echo "    \"dry_run\": true|false,"
            echo "    \"cocoon_dir\": \"<path>\","
            echo "    \"gpus\": {\"worker0\": \"0000:01:00.0\", \"worker1\": \"0000:02:00.0\"},"
            echo "    \"workers\": ["
            echo "      {\"instance\":0,\"pid\":12345,\"port\":12000,\"log\":\"logs/worker-0.log\",\"pid_file\":\"logs/worker-0.pid\"},"
            echo "      {\"instance\":1,\"pid\":12346,\"port\":12010,\"log\":\"logs/worker-1.log\",\"pid_file\":\"logs/worker-1.pid\"}"
            echo "    ],"
            echo "    \"watchdog\": {\"started\": true|false, \"pid\": 12347|null},"
            echo "    \"validation\": {\"passed\": true|false, \"errors\": [\"...\"]},"
            echo "    \"overall_status\": \"ok|failed|dry-run\""
            echo "  }"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
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

# Collect validation errors for JSON output
VALIDATION_ERRORS=()

validate_prerequisites() {
    local errors=0

    if [ "$JSON" != true ]; then
        echo "=== Prerequisite Validation ==="
        echo ""
    fi

    # 1. Check seal-server process
    if ! pgrep -f "seal-server" > /dev/null; then
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} seal-server is not running"
            echo "  Next step: Start it with: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
        fi
        VALIDATION_ERRORS+=("seal-server is not running")
        ((errors++))
    else
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} seal-server is running"
        fi
    fi

    # 2. Check worker config files and required keys
    for worker in 0 1; do
        conf="worker-${worker}.conf"
        if [ ! -f "$conf" ]; then
            # Try parent dir
            if [ -f "../$conf" ]; then
                cp "../$conf" .
                if [ "$JSON" != true ]; then
                    echo -e "${GREEN}✓${NC} Copied $conf from parent"
                fi
            else
                if [ "$JSON" != true ]; then
                    echo -e "${RED}✗${NC} $conf not found"
                    echo "  Next step: Run setup-h100.sh or create from worker.conf.template"
                fi
                VALIDATION_ERRORS+=("$conf not found")
                ((errors++))
                continue
            fi
        fi

        # Check for non-placeholder values
        for key in owner_address node_wallet_key hf_token root_contract_address; do
            val=$(grep "^${key}" "$conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
            if [ -z "$val" ] || [[ "$val" == YOUR_* ]] || [[ "$val" == "[PRIVATE]" ]]; then
                if [ "$JSON" != true ]; then
                    echo -e "${RED}✗${NC} $conf: $key has placeholder or empty value"
                    echo "  Next step: Edit $conf and set a real value for $key"
                fi
                VALIDATION_ERRORS+=("$conf: $key has placeholder or empty value")
                ((errors++))
            fi
        done
        if [ $errors -eq 0 ] && [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} $conf validated"
        fi
    done

    # root_contract_address mismatch check against distribution example
    if [ -f "worker.conf.example" ]; then
        EXAMPLE_ROOT=$(grep "^root_contract_address" worker.conf.example 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
        if [ -n "$EXAMPLE_ROOT" ] && [[ "$EXAMPLE_ROOT" != YOUR_* ]]; then
            for worker in 0 1; do
                conf="worker-${worker}.conf"
                if [ -f "$conf" ]; then
                    ACTUAL_ROOT=$(grep "^root_contract_address" "$conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
                    if [ -n "$ACTUAL_ROOT" ] && [ "$ACTUAL_ROOT" != "$EXAMPLE_ROOT" ]; then
                        if [ "$JSON" != true ]; then
                            echo -e "${YELLOW}⚠${NC} root_contract_address mismatch in $conf (expected: $EXAMPLE_ROOT)"
                            echo "  Suggested fix: sed -i 's|root_contract_address = .*|root_contract_address = $EXAMPLE_ROOT|' worker-*.conf worker.conf.example"
                        fi
                    fi
                fi
            done
        fi
    fi

    # 3. Check both H100 GPUs via lspci
    GPU_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
    if [ "$GPU_COUNT" -lt 2 ]; then
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} Less than 2 H100 GPUs detected (found: $GPU_COUNT)"
            echo "  Next step: Verify hardware / lspci | grep -i nvidia"
        fi
        VALIDATION_ERRORS+=("Less than 2 H100 GPUs detected (found: $GPU_COUNT)")
        ((errors++))
    else
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} Both H100 GPUs detected"
        fi
    fi

    # 4. Verify binaries are executable
    if [ -f "./scripts/cocoon-launch" ]; then
        if [ ! -x "./scripts/cocoon-launch" ]; then
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}⚠${NC} cocoon-launch not executable (fixing...)"
            fi
            chmod +x "./scripts/cocoon-launch"
        fi
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} cocoon-launch binary present and executable"
        fi
    else
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} cocoon-launch not found"
            echo "  Next step: Ensure COCOON distribution is extracted in current dir"
        fi
        VALIDATION_ERRORS+=("cocoon-launch not found")
        ((errors++))
    fi

    if [ -f "./bin/seal-server" ]; then
        if [ ! -x "./bin/seal-server" ]; then
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}⚠${NC} seal-server not executable (fixing...)"
            fi
            chmod +x "./bin/seal-server"
        fi
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} seal-server binary present and executable"
        fi
    else
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} seal-server binary not found"
            echo "  Next step: Download/extract COCOON distribution"
        fi
        VALIDATION_ERRORS+=("seal-server binary not found")
        ((errors++))
    fi

    if [ "$JSON" != true ]; then
        echo ""
    fi
    if [ $errors -gt 0 ]; then
        if [ "$JSON" != true ]; then
            echo -e "${RED}Validation failed with $errors error(s).${NC}"
            echo "Use --force to bypass (not recommended)."
        fi
        return 1
    fi
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}All prerequisites validated successfully.${NC}"
    fi
    return 0
}

# Emit the JSON summary object
emit_json() {
    local overall="$1"
    local mode_str="$2"
    local gpu0="$3"
    local gpu1="$4"
    local worker0_pid="$5"
    local worker1_pid="$6"
    local watchdog_started="$7"
    local watchdog_pid="$8"
    local validation_passed="$9"

    local cocoon_dir_esc
    cocoon_dir_esc=$(json_escape "$COCOON_DIR")

    local mode_esc
    mode_esc=$(json_escape "$mode_str")

    local gpu0_esc
    gpu0_esc=$(json_escape "$gpu0")
    local gpu1_esc
    gpu1_esc=$(json_escape "$gpu1")

    # Build workers array
    local workers_json="["
    if [ "$DRY_RUN" = true ]; then
        workers_json+="{\"instance\":0,\"pid\":null,\"port\":12000,\"log\":\"logs/worker-0.log\",\"pid_file\":\"logs/worker-0.pid\",\"command\":\"./scripts/cocoon-launch $MODE_FLAGS --instance 0 --gpu $gpu0 worker-0.conf\"}"
        workers_json+=",{\"instance\":1,\"pid\":null,\"port\":12010,\"log\":\"logs/worker-1.log\",\"pid_file\":\"logs/worker-1.pid\",\"command\":\"./scripts/cocoon-launch $MODE_FLAGS --instance 1 --gpu $gpu1 worker-1.conf\"}"
    else
        workers_json+="{\"instance\":0,\"pid\":$worker0_pid,\"port\":12000,\"log\":\"logs/worker-0.log\",\"pid_file\":\"logs/worker-0.pid\"}"
        workers_json+=",{\"instance\":1,\"pid\":$worker1_pid,\"port\":12010,\"log\":\"logs/worker-1.log\",\"pid_file\":\"logs/worker-1.pid\"}"
    fi
    workers_json+="]"

    # Build validation object
    local validation_json="{\"passed\":$validation_passed,\"errors\":["
    local first=true
    for err in "${VALIDATION_ERRORS[@]}"; do
        local err_esc
        err_esc=$(json_escape "$err")
        if [ "$first" = true ]; then
            first=false
        else
            validation_json+=","
        fi
        validation_json+="\"$err_esc\""
    done
    validation_json+="]}"

    # Build watchdog object
    local watchdog_json
    if [ "$watchdog_started" = true ]; then
        watchdog_json="{\"started\":true,\"pid\":$watchdog_pid}"
    else
        watchdog_json="{\"started\":false,\"pid\":null}"
    fi

    printf '{"mode":"%s","dry_run":%s,"cocoon_dir":"%s","gpus":{"worker0":"%s","worker1":"%s"},"workers":%s,"watchdog":%s,"validation":%s,"overall_status":"%s"}\n' \
        "$mode_esc" "$DRY_RUN" "$cocoon_dir_esc" "$gpu0_esc" "$gpu1_esc" "$workers_json" "$watchdog_json" "$validation_json" "$overall"
}

if [ "$JSON" != true ]; then
    echo "=== COCOON H100 Workers Launcher ==="
    echo ""
fi

# Check if we're in the right directory
# Try release-8728fe7 first, then current directory
if [ -f "./release-8728fe7/scripts/cocoon-launch" ]; then
    COCOON_DIR="./release-8728fe7"
elif [ -f "./scripts/cocoon-launch" ]; then
    COCOON_DIR="."
else
    if [ "$JSON" = true ]; then
        VALIDATION_ERRORS+=("cocoon-launch script not found")
        emit_json "failed" "${MODE:-production}" "" "" null null false null false
        exit 1
    fi
    echo -e "${RED}Error: cocoon-launch script not found${NC}"
    echo "Please run this script from the cocoon directory"
    exit 1
fi

cd "$COCOON_DIR"

# Run validation unless --force
VALIDATION_PASSED=true
if [ "$FORCE" != true ]; then
    if ! validate_prerequisites; then
        VALIDATION_PASSED=false
        if [ "$JSON" = true ]; then
            # Detect GPUs for JSON output even on failure
            GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
            GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')
            emit_json "failed" "${MODE:-production}" "$GPU1" "$GPU2" null null false null false
            exit 1
        fi
        exit 1
    fi
else
    if [ "$JSON" != true ]; then
        echo -e "${YELLOW}--force specified: skipping prerequisite validation${NC}"
    fi
fi

if [ "$DRY_RUN" = true ]; then
    # Detect GPUs
    GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
    GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')

    # Determine MODE_FLAGS for dry-run command display
    MODE_FLAGS=""
    if [ -n "$MODE" ]; then
        case "$MODE" in
            production) MODE_FLAGS="" ;;
            test) MODE_FLAGS="--test" ;;
            fake-ton) MODE_FLAGS="--test --fake-ton" ;;
        esac
    fi

    if [ "$JSON" = true ]; then
        emit_json "dry-run" "${MODE:-production}" "$GPU1" "$GPU2" null null false null "$VALIDATION_PASSED"
        exit 0
    fi

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
    if [ "$JSON" != true ]; then
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
fi

# Check if config files exist
if [ ! -f "worker-0.conf" ]; then
    # Try to copy from parent directory
    if [ -f "../worker-0.conf" ]; then
        cp ../worker-0.conf .
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}Copied worker-0.conf from parent directory${NC}"
        fi
    else
        if [ "$JSON" = true ]; then
            VALIDATION_ERRORS+=("worker-0.conf not found")
            GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
            GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')
            emit_json "failed" "${MODE:-production}" "$GPU1" "$GPU2" null null false null false
            exit 1
        fi
        echo -e "${RED}Error: worker-0.conf not found${NC}"
        echo "Please create configuration files first"
        exit 1
    fi
fi

if [ ! -f "worker-1.conf" ]; then
    # Try to copy from parent directory
    if [ -f "../worker-1.conf" ]; then
        cp ../worker-1.conf .
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}Copied worker-1.conf from parent directory${NC}"
        fi
    else
        if [ "$JSON" = true ]; then
            VALIDATION_ERRORS+=("worker-1.conf not found")
            GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
            GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')
            emit_json "failed" "${MODE:-production}" "$GPU1" "$GPU2" null null false null false
            exit 1
        fi
        echo -e "${RED}Error: worker-1.conf not found${NC}"
        echo "Please create configuration files first"
        exit 1
    fi
fi

# Detect GPUs
GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')

if [ "$JSON" != true ]; then
    echo "GPU Configuration:"
    echo "  Worker 0: $GPU1"
    echo "  Worker 1: $GPU2"
    echo ""
fi

# Determine MODE_FLAGS
MODE_FLAGS=""
if [ -n "$MODE" ]; then
    case "$MODE" in
        production)
            MODE_FLAGS=""
            if [ "$JSON" != true ]; then
                echo -e "${GREEN}Launching in PRODUCTION mode${NC}"
            fi
            ;;
        test)
            MODE_FLAGS="--test"
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}Launching in TEST mode (real TON)${NC}"
            fi
            ;;
        fake-ton)
            MODE_FLAGS="--test --fake-ton"
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}Launching in TEST mode (fake TON)${NC}"
            fi
            ;;
        *)
            if [ "$JSON" = true ]; then
                VALIDATION_ERRORS+=("Invalid --mode value: $MODE")
                emit_json "failed" "$MODE" "$GPU1" "$GPU2" null null false null false
                exit 1
            fi
            echo -e "${RED}Invalid --mode value: $MODE${NC}"
            echo "Valid values: production, test, fake-ton"
            echo "Usage: $0 [--mode production|test|fake-ton] ..."
            exit 1
            ;;
    esac
else
    if [ "$JSON" = true ]; then
        # Non-interactive JSON mode defaults to production
        MODE="production"
        MODE_FLAGS=""
    else
        # Ask for mode (interactive)
        echo "Select launch mode:"
        echo "1) Production mode (requires seal-server)"
        echo "2) Test mode (with debug shell, real TON)"
        echo "3) Test mode (with debug shell, fake TON)"
        read -p "Choice [1-3]: " -n 1 -r
        echo ""

        case $REPLY in
            1)
                MODE_FLAGS=""
                MODE="production"
                echo -e "${GREEN}Launching in PRODUCTION mode${NC}"
                ;;
            2)
                MODE_FLAGS="--test"
                MODE="test"
                echo -e "${YELLOW}Launching in TEST mode (real TON)${NC}"
                ;;
            3)
                MODE_FLAGS="--test --fake-ton"
                MODE="fake-ton"
                echo -e "${YELLOW}Launching in TEST mode (fake TON)${NC}"
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                exit 1
                ;;
        esac
    fi
fi

if [ "$JSON" != true ]; then
    echo ""
    echo "Starting workers..."
    echo ""
fi

# Create log directory
mkdir -p logs

# Launch worker 0
if [ "$JSON" != true ]; then
    echo -e "${GREEN}Starting Worker 0 (GPU: $GPU1)...${NC}"
fi
nohup ./scripts/cocoon-launch $MODE_FLAGS --instance 0 --gpu $GPU1 worker-0.conf > logs/worker-0.log 2>&1 &
WORKER0_PID=$!
if [ "$JSON" != true ]; then
    echo "Worker 0 PID: $WORKER0_PID"
fi

# Wait a bit before starting second worker
sleep 2

# Launch worker 1
if [ "$JSON" != true ]; then
    echo -e "${GREEN}Starting Worker 1 (GPU: $GPU2)...${NC}"
fi
nohup ./scripts/cocoon-launch $MODE_FLAGS --instance 1 --gpu $GPU2 worker-1.conf > logs/worker-1.log 2>&1 &
WORKER1_PID=$!
if [ "$JSON" != true ]; then
    echo "Worker 1 PID: $WORKER1_PID"
fi

if [ "$JSON" != true ]; then
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
fi

# Save PIDs to file
echo "$WORKER0_PID" > logs/worker-0.pid
echo "$WORKER1_PID" > logs/worker-1.pid

WATCHDOG_STARTED=false
WATCHDOG_PID=null
if [ "$WATCHDOG" = true ]; then
    if [ "$JSON" != true ]; then
        echo ""
        echo -e "${GREEN}Starting watchdog...${NC}"
    fi
    nohup ./watchdog.sh > logs/watchdog.log 2>&1 &
    WATCHDOG_PID=$!
    WATCHDOG_STARTED=true
    if [ "$JSON" != true ]; then
        echo "Watchdog PID: $WATCHDOG_PID"
    fi
fi

# Wait-ready polling (skipped in dry-run)
if [ "$WAIT_READY" = true ]; then
    if [ "$JSON" != true ]; then
        echo ""
        echo "Waiting for workers to become ready (timeout: ${TIMEOUT}s)..."
    fi
    start_time=$(date +%s)
    delay=5
    while true; do
        code0=$(curl -s --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:12000/stats || echo 000)
        code1=$(curl -s --max-time 2 -o /dev/null -w "%{http_code}" http://localhost:12010/stats || echo 000)
        if [ "$code0" = "200" ] && [ "$code1" = "200" ]; then
            if [ "$JSON" != true ]; then
                echo -e "${GREEN}Both workers are ready.${NC}"
            fi
            break
        fi
        now=$(date +%s)
        elapsed=$((now - start_time))
        if [ "$elapsed" -ge "$TIMEOUT" ]; then
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}Timeout reached (${TIMEOUT}s). Workers may still be initializing.${NC}"
            fi
            break
        fi
        sleep "$delay"
    done
fi

if [ "$JSON" = true ]; then
    emit_json "ok" "$MODE" "$GPU1" "$GPU2" "$WORKER0_PID" "$WORKER1_PID" "$WATCHDOG_STARTED" "$WATCHDOG_PID" "$VALIDATION_PASSED"
fi
