#!/bin/bash
# Script pour vérifier le statut des workers COCOON

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMEOUT=3

print_help() {
    cat <<'EOF'
Usage: status-workers.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Output a single machine-readable JSON object describing
                   seal-server, both workers, HTTP stats, and GPU utilization.
                   Exits 0 when overall_status is "ok", non-zero otherwise.

Without --json, prints a human-readable colored status report.
EOF
}

# Parse arguments
OUTPUT_JSON=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 2
            ;;
    esac
done

fetch_stats() {
    local port=$1
    local name=$2
    echo -e "${BLUE}Stats for ${name} (port ${port}):${NC}"
    local stats
    stats=$(curl -s --max-time ${TIMEOUT} http://localhost:${port}/stats 2>/dev/null || echo "ERROR")
    if [[ "$stats" == "ERROR" ]] || [[ -z "$stats" ]]; then
        echo -e "  ${YELLOW}not ready${NC} (connection error or timeout)"
        return
    fi
    # Try to extract key metrics (works for both text and JSON)
    local status requests gpu
    if echo "$stats" | grep -q '{' ; then
        # Likely JSON, basic extraction without jq
        status=$(echo "$stats" | grep -o '"status"[^,}]*' | head -1 | cut -d: -f2 | tr -d ' "')
        requests=$(echo "$stats" | grep -o '"requests[^"]*"[^,}]*' | head -1 | cut -d: -f2 | tr -d ' "')
        gpu=$(echo "$stats" | grep -oE '"gpu[^"]*"[^,}]*' | head -3 | tr '\n' ' ' | tr -d ' "')
    else
        status=$(echo "$stats" | grep -iE 'status|ready' | head -1 | tr -d '\r')
        requests=$(echo "$stats" | grep -iE 'request|served' | head -1 | tr -d '\r')
        gpu=$(echo "$stats" | grep -iE 'gpu|util' | head -2 | tr '\n' ' ' | tr -d '\r')
    fi
    echo -e "  Status: ${GREEN}${status:-unknown}${NC}"
    echo -e "  Requests: ${YELLOW}${requests:-0}${NC}"
    if [[ -n "$gpu" ]]; then
        echo -e "  GPU: ${GREEN}${gpu}${NC}"
    fi
    echo "$stats" | head -5 | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if $OUTPUT_JSON; then
    # seal-server
    if pgrep -f "seal-server" > /dev/null; then
        SEAL_PID=$(pgrep -f "seal-server" | head -1)
        SEAL_RUNNING=true
    else
        SEAL_PID=null
        SEAL_RUNNING=false
    fi

    # Workers
    WORKER0_PID=$(pgrep -f "cocoon-launch.*instance.*0" | head -1)
    WORKER1_PID=$(pgrep -f "cocoon-launch.*instance.*1" | head -1)

    build_worker_json() {
        local instance=$1
        local pid=$2
        local port=$3
        local running
        local http_code=0
        local reachable=false

        if [[ -n "$pid" ]]; then
            running=true
        else
            running=false
            pid=null
        fi

        if [[ -n "$pid" ]] && [[ "$pid" != "null" ]]; then
            http_code=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "http://localhost:${port}/stats" 2>/dev/null || echo 0)
            if [[ "$http_code" == "200" ]]; then
                reachable=true
            fi
        fi

        echo "{\"instance\":$instance,\"running\":$running,\"pid\":$pid,\"port\":$port,\"stats_http_code\":$http_code,\"stats_reachable\":$reachable}"
    }

    WORKER0_JSON=$(build_worker_json 0 "$WORKER0_PID" 12000)
    WORKER1_JSON=$(build_worker_json 1 "$WORKER1_PID" 12010)

    # GPUs
    GPUS_JSON="[]"
    if command -v nvidia-smi &> /dev/null; then
        gpus='['
        first=true
        for pci in 0000:01:00.0 0000:02:00.0; do
            gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits -i "$pci" 2>/dev/null || true)
            if [[ -n "$gpu_info" ]]; then
                util=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
                mem_used=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
                mem_total=$(echo "$gpu_info" | cut -d',' -f3 | tr -d ' ')
                temp=$(echo "$gpu_info" | cut -d',' -f4 | tr -d ' ')
                if $first; then
                    first=false
                else
                    gpus+=','
                fi
                gpus+="{\"pci\":\"$pci\",\"utilization\":$util,\"memory_used\":$mem_used,\"memory_total\":$mem_total,\"temperature\":$temp}"
            fi
        done
        gpus+=']'
        GPUS_JSON="$gpus"
    fi

    # overall_status
    if [[ "$SEAL_RUNNING" == "true" ]] && ([[ -n "$WORKER0_PID" ]] || [[ -n "$WORKER1_PID" ]]); then
        OVERALL="ok"
        EXIT_CODE=0
    else
        OVERALL="degraded"
        EXIT_CODE=1
    fi

    printf '{"seal_server":{"running":%s,"pid":%s},"workers":[%s,%s],"gpus":%s,"overall_status":"%s"}\n' \
        "$SEAL_RUNNING" "$SEAL_PID" "$WORKER0_JSON" "$WORKER1_JSON" "$GPUS_JSON" "$OVERALL"

    exit $EXIT_CODE
fi

# ---------------------------------------------------------------------------
# Human-readable mode (unchanged)
# ---------------------------------------------------------------------------
echo -e "${BLUE}=== Statut des Workers COCOON ===${NC}"

echo ""

# Vérifier seal-server
echo -e "${BLUE}1. Seal-Server:${NC}"
if pgrep -f "seal-server" > /dev/null; then
    PID=$(pgrep -f "seal-server")
    echo -e "${GREEN}✓${NC} En cours d'exécution (PID: $PID)"
else
    echo -e "${RED}✗${NC} Non détecté"
fi
echo ""

# Vérifier les workers
echo -e "${BLUE}2. Workers:${NC}"
WORKER0=$(pgrep -f "cocoon-launch.*instance.*0" | head -1)
WORKER1=$(pgrep -f "cocoon-launch.*instance.*1" | head -1)

if [ -n "$WORKER0" ]; then
    echo -e "${GREEN}✓${NC} Worker 0 en cours d'exécution (PID: $WORKER0)"
else
    echo -e "${RED}✗${NC} Worker 0 non détecté"
fi

if [ -n "$WORKER1" ]; then
    echo -e "${GREEN}✓${NC} Worker 1 en cours d'exécution (PID: $WORKER1)"
else
    echo -e "${RED}✗${NC} Worker 1 non détecté"
fi
echo ""

# HTTP stats summary (new section)
echo -e "${BLUE}3. HTTP Stats Summary:${NC}"
fetch_stats 12000 "Worker 0"
echo ""
fetch_stats 12010 "Worker 1"
echo ""

# Vérifier les ports HTTP (legacy quick check)
echo -e "${BLUE}4. Endpoints HTTP (quick check):${NC}"
if curl -s --max-time 2 http://localhost:12000/stats > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Worker 0: http://localhost:12000/stats (actif)"
else
    echo -e "${YELLOW}⚠${NC} Worker 0: http://localhost:12000/stats (en cours d'initialisation)"
fi

if curl -s --max-time 2 http://localhost:12010/stats > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Worker 1: http://localhost:12010/stats (actif)"
else
    echo -e "${YELLOW}⚠${NC} Worker 1: http://localhost:12010/stats (en cours d'initialisation)"
fi
echo ""

# Afficher les dernières lignes des logs
echo -e "${BLUE}5. Dernières lignes des logs:${NC}"
echo -e "${YELLOW}Worker 0:${NC}"
tail -3 logs/worker-0.log 2>/dev/null || echo "  (log non disponible)"
echo ""
echo -e "${YELLOW}Worker 1:${NC}"
tail -3 logs/worker-1.log 2>/dev/null || echo "  (log non disponible)"
echo ""

# GPU utilization monitor (section 6)
echo -e "${BLUE}6. GPU Utilization (NVIDIA H100):${NC}"
if command -v nvidia-smi &> /dev/null; then
    for pci in 0000:01:00.0 0000:02:00.0; do
        gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits -i $pci 2>/dev/null || echo "N/A")
        if [[ "$gpu_info" == "N/A" ]] || [[ -z "$gpu_info" ]]; then
            echo -e "  ${YELLOW}⚠${NC} GPU $pci: nvidia-smi query failed"
        else
            util=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
            mem_used=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
            mem_total=$(echo "$gpu_info" | cut -d',' -f3 | tr -d ' ')
            if [ "$util" -ge 80 ]; then
                color=$RED
            elif [ "$util" -ge 50 ]; then
                color=$YELLOW
            else
                color=$GREEN
            fi
            echo -e "  GPU $pci: ${color}${util}% util${NC}, ${mem_used}/${mem_total} MiB mem"
        fi
    done
else
    echo -e "  ${YELLOW}⚠${NC} nvidia-smi not found (NVIDIA drivers may be absent)"
fi
echo ""

# Commandes utiles
echo -e "${BLUE}Commandes utiles:${NC}"
echo "  Voir les logs: tail -f logs/worker-0.log"
echo "  Stats Worker 0: curl http://localhost:12000/stats"
echo "  Stats Worker 1: curl http://localhost:12010/stats"
echo "  Arrêter: ./stop-workers.sh"
