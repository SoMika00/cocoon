#!/bin/bash
# Script de vérification complète de la configuration COCOON

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat <<'EOF'
Usage: verify-config.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing every verification check with status, detail,
                   and remediation hint.

JSON schema (when --json is set):
  {
    "checks": [
      {"name":"...","status":"pass|warn|fail","detail":"...","hint":"..."}
    ],
    "summary": {"passed":N,"warned":N,"failed":N,"total":N},
    "overall_status": "ok|degraded|failed",
    "exit_code": 0|1
  }

overall_status is "failed" when any check is fail, "degraded" when only
warnings exist, and "ok" otherwise. exit_code mirrors the existing human-mode
exit logic (1 when ERRORS>0, else 0).
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
JSON=false
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
            print_help
            exit 2
            ;;
    esac
done

# Per-check result storage: name, status (pass|warn|fail), detail, hint
CHECK_NAMES=()
CHECK_STATUS=()
CHECK_DETAIL=()
CHECK_HINT=()

add_check() {
    local name="$1"
    local status="$2"
    local detail="$3"
    local hint="$4"
    CHECK_NAMES+=("$name")
    CHECK_STATUS+=("$status")
    CHECK_DETAIL+=("$detail")
    CHECK_HINT+=("$hint")
}

ERRORS=0
WARNINGS=0

# Fonction pour vérifier un fichier
check_file() {
    local file="$1"
    local name="$2"
    if [ -f "$file" ]; then
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} $file"
        fi
        add_check "$name" "pass" "$file present" "No action required"
        return 0
    else
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} $file (manquant)"
        fi
        ((ERRORS++))
        add_check "$name" "fail" "$file missing" "Ensure the COCOON distribution is extracted"
        return 1
    fi
}

# Fonction pour vérifier une valeur dans un fichier
check_config_value() {
    local file=$1
    local key=$2
    local expected=$3
    local name=$4

    if [ -f "$file" ]; then
        value=$(grep "^${key}" "$file" | cut -d'=' -f2 | tr -d ' ' | head -1)
        if [ "$value" = "$expected" ] || [ -z "$expected" ]; then
            if [ -n "$value" ] && [ "$value" != "YOUR_"* ] && [ "$value" != "[PRIVATE]" ]; then
                if grep -q "^# AUTO-GENERATED" "$file"; then
                    if [ "$JSON" != true ]; then
                        echo -e "${GREEN}✓${NC} $key = [AUTO-GENERATED secure key - secret hidden]"
                    fi
                    add_check "$name" "pass" "$key configured (auto-generated, secret hidden)" "No action required"
                else
                    if [ "$JSON" != true ]; then
                        echo -e "${GREEN}✓${NC} $key = $value"
                    fi
                    add_check "$name" "pass" "$key = $value" "No action required"
                fi
                return 0
            else
                if [ "$JSON" != true ]; then
                    echo -e "${RED}✗${NC} $key n'est pas configuré correctement"
                fi
                ((ERRORS++))
                add_check "$name" "fail" "$key not configured correctly" "Set a real value for $key in $file"
                return 1
            fi
        else
            if [ "$JSON" != true ]; then
                echo -e "${YELLOW}⚠${NC} $key = $value (attendu: $expected)"
            fi
            ((WARNINGS++))
            add_check "$name" "warn" "$key = $value (expected: $expected)" "Set $key to $expected in $file"
            return 1
        fi
    else
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} Fichier $file non trouvé"
        fi
        ((ERRORS++))
        add_check "$name" "fail" "$file not found" "Ensure the COCOON distribution is extracted"
        return 1
    fi
}

if [ "$JSON" != true ]; then
    echo -e "${BLUE}=== Vérification de la Configuration COCOON ===${NC}"
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}1. Vérification des fichiers de la distribution...${NC}"
fi
check_file "release-8728fe7/bin/seal-server" "dist_seal_server"
check_file "release-8728fe7/bin/enclave.signed.so" "dist_enclave"
check_file "release-8728fe7/bin/health-client" "dist_health_client"
check_file "release-8728fe7/scripts/cocoon-launch" "dist_cocoon_launch"
check_file "release-8728fe7/spec/mainnet-base-ton-config.json" "dist_ton_config"
check_file "release-8728fe7/worker.conf.example" "dist_worker_example"
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}2. Vérification des fichiers de configuration...${NC}"
fi
check_file "release-8728fe7/worker-0.conf" "config_worker0_file"
check_file "release-8728fe7/worker-1.conf" "config_worker1_file"
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}3. Vérification de la configuration Worker 0...${NC}"
fi
if [ -f "release-8728fe7/worker-0.conf" ]; then
    check_config_value "release-8728fe7/worker-0.conf" "type" "worker" "worker0_type"
    check_config_value "release-8728fe7/worker-0.conf" "owner_address" "" "worker0_owner_address"
    check_config_value "release-8728fe7/worker-0.conf" "gpu" "0000:01:00.0" "worker0_gpu"
    check_config_value "release-8728fe7/worker-0.conf" "node_wallet_key" "" "worker0_node_wallet_key"
    check_config_value "release-8728fe7/worker-0.conf" "hf_token" "" "worker0_hf_token"
    check_config_value "release-8728fe7/worker-0.conf" "root_contract_address" "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k" "worker0_root_contract_address"
    check_config_value "release-8728fe7/worker-0.conf" "instance" "0" "worker0_instance"
    check_config_value "release-8728fe7/worker-0.conf" "ton_config" "spec/mainnet-base-ton-config.json" "worker0_ton_config"
fi
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}4. Vérification de la configuration Worker 1...${NC}"
fi
if [ -f "release-8728fe7/worker-1.conf" ]; then
    check_config_value "release-8728fe7/worker-1.conf" "type" "worker" "worker1_type"
    check_config_value "release-8728fe7/worker-1.conf" "owner_address" "" "worker1_owner_address"
    check_config_value "release-8728fe7/worker-1.conf" "gpu" "0000:02:00.0" "worker1_gpu"
    check_config_value "release-8728fe7/worker-1.conf" "node_wallet_key" "" "worker1_node_wallet_key"
    check_config_value "release-8728fe7/worker-1.conf" "hf_token" "" "worker1_hf_token"
    check_config_value "release-8728fe7/worker-1.conf" "root_contract_address" "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k" "worker1_root_contract_address"
    check_config_value "release-8728fe7/worker-1.conf" "instance" "1" "worker1_instance"
    check_config_value "release-8728fe7/worker-1.conf" "ton_config" "spec/mainnet-base-ton-config.json" "worker1_ton_config"
fi
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}5. Vérification de la cohérence des configurations...${NC}"
fi
if [ -f "release-8728fe7/worker-0.conf" ] && [ -f "release-8728fe7/worker-1.conf" ]; then
    OWNER0=$(grep "^owner_address" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    OWNER1=$(grep "^owner_address" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$OWNER0" = "$OWNER1" ]; then
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} owner_address identique dans les deux workers"
        fi
        add_check "consistency_owner_address" "pass" "owner_address identical across workers" "No action required"
    else
        if [ "$JSON" != true ]; then
            echo -e "${YELLOW}⚠${NC} owner_address différent entre les workers"
        fi
        ((WARNINGS++))
        add_check "consistency_owner_address" "warn" "owner_address differs between workers" "Use the same owner_address in both worker configs"
    fi

    KEY0=$(grep "^node_wallet_key" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    KEY1=$(grep "^node_wallet_key" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$KEY0" = "$KEY1" ]; then
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} node_wallet_key identique dans les deux workers"
        fi
        add_check "consistency_node_wallet_key" "pass" "node_wallet_key identical across workers" "No action required"
    else
        if [ "$JSON" != true ]; then
            echo -e "${YELLOW}⚠${NC} node_wallet_key différent entre les workers"
        fi
        ((WARNINGS++))
        add_check "consistency_node_wallet_key" "warn" "node_wallet_key differs between workers" "Use the same node_wallet_key in both worker configs"
    fi

    ROOT0=$(grep "^root_contract_address" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    ROOT1=$(grep "^root_contract_address" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$ROOT0" = "$ROOT1" ] && [ "$ROOT0" = "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k" ]; then
        if [ "$JSON" != true ]; then
            echo -e "${GREEN}✓${NC} root_contract_address correct et identique (officiel)"
        fi
        add_check "consistency_root_contract_address" "pass" "root_contract_address correct and identical (official)" "No action required"
    else
        if [ "$JSON" != true ]; then
            echo -e "${RED}✗${NC} root_contract_address incorrect ou différent"
        fi
        ((ERRORS++))
        add_check "consistency_root_contract_address" "fail" "root_contract_address incorrect or differs" "Set root_contract_address to the official value in both worker configs"
    fi
fi
if [ "$JSON" != true ]; then
    echo ""
fi

# Cross-check against worker.conf.example if present
if [ -f "release-8728fe7/worker.conf.example" ]; then
    EXAMPLE_ROOT=$(grep "^root_contract_address" release-8728fe7/worker.conf.example 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
    if [ -n "$EXAMPLE_ROOT" ] && [[ "$EXAMPLE_ROOT" != YOUR_* ]]; then
        for conf in release-8728fe7/worker-0.conf release-8728fe7/worker-1.conf; do
            if [ -f "$conf" ]; then
                ACTUAL=$(grep "^root_contract_address" "$conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -1)
                if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "$EXAMPLE_ROOT" ]; then
                    if [ "$JSON" != true ]; then
                        echo -e "${YELLOW}⚠${NC} root_contract_address mismatch vs worker.conf.example in $conf"
                        echo "  Suggested fix: sed -i 's|root_contract_address = .*|root_contract_address = $EXAMPLE_ROOT|' worker-*.conf worker.conf.example"
                    fi
                    ((WARNINGS++))
                    add_check "crosscheck_root_contract_${conf##*/}" "warn" "root_contract_address mismatch vs worker.conf.example in $conf" "sed -i 's|root_contract_address = .*|root_contract_address = $EXAMPLE_ROOT|' worker-*.conf worker.conf.example"
                fi
            fi
        done
    fi
fi
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}6. Vérification des GPUs...${NC}"
fi
GPU_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
if [ "$GPU_COUNT" -ge 2 ]; then
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} $GPU_COUNT GPU(s) H100 détecté(s)"
        lspci | grep -i "H100\|GH100" | awk '{print "  - 0000:" $1}'
    fi
    add_check "gpu_detection" "pass" "$GPU_COUNT H100 GPU(s) detected" "No action required"
else
    if [ "$JSON" != true ]; then
        echo -e "${RED}✗${NC} Moins de 2 GPUs H100 détectés"
    fi
    ((ERRORS++))
    add_check "gpu_detection" "fail" "Fewer than 2 H100 GPUs detected (found: $GPU_COUNT)" "Verify hardware / lspci | grep -i nvidia"
fi
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}7. Vérification des permissions...${NC}"
fi
if [ -x "release-8728fe7/bin/seal-server" ]; then
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} seal-server exécutable"
    fi
    add_check "permissions_seal_server" "pass" "seal-server executable" "No action required"
else
    if [ "$JSON" != true ]; then
        echo -e "${YELLOW}⚠${NC} seal-server non exécutable (chmod +x)"
    fi
    ((WARNINGS++))
    add_check "permissions_seal_server" "warn" "seal-server not executable" "chmod +x release-8728fe7/bin/seal-server"
fi

if [ -x "release-8728fe7/scripts/cocoon-launch" ]; then
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} cocoon-launch exécutable"
    fi
    add_check "permissions_cocoon_launch" "pass" "cocoon-launch executable" "No action required"
else
    if [ "$JSON" != true ]; then
        echo -e "${YELLOW}⚠${NC} cocoon-launch non exécutable (chmod +x)"
    fi
    ((WARNINGS++))
    add_check "permissions_cocoon_launch" "warn" "cocoon-launch not executable" "chmod +x release-8728fe7/scripts/cocoon-launch"
fi
if [ "$JSON" != true ]; then
    echo ""
fi

if [ "$JSON" != true ]; then
    echo -e "${BLUE}8. Vérification du format des fichiers...${NC}"
fi
if grep -q "^\[node\]" release-8728fe7/worker-0.conf 2>/dev/null; then
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} Format [node] correct dans worker-0.conf"
    fi
    add_check "format_worker0" "pass" "[node] format correct in worker-0.conf" "No action required"
else
    if [ "$JSON" != true ]; then
        echo -e "${RED}✗${NC} Format incorrect dans worker-0.conf (devrait être [node])"
    fi
    ((ERRORS++))
    add_check "format_worker0" "fail" "Incorrect format in worker-0.conf (should be [node])" "Use [node] section header in worker-0.conf"
fi

if grep -q "^\[node\]" release-8728fe7/worker-1.conf 2>/dev/null; then
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} Format [node] correct dans worker-1.conf"
    fi
    add_check "format_worker1" "pass" "[node] format correct in worker-1.conf" "No action required"
else
    if [ "$JSON" != true ]; then
        echo -e "${RED}✗${NC} Format incorrect dans worker-1.conf (devrait être [node])"
    fi
    ((ERRORS++))
    add_check "format_worker1" "fail" "Incorrect format in worker-1.conf (should be [node])" "Use [node] section header in worker-1.conf"
fi
if [ "$JSON" != true ]; then
    echo ""
fi

# ---------------------------------------------------------------------------
# JSON mode
# ---------------------------------------------------------------------------
if [ "$JSON" = true ]; then
    checks_json="["
    passed=0
    warned=0
    failed=0
    for idx in "${!CHECK_NAMES[@]}"; do
        name_esc=$(json_escape "${CHECK_NAMES[$idx]}")
        status_esc=$(json_escape "${CHECK_STATUS[$idx]}")
        detail_esc=$(json_escape "${CHECK_DETAIL[$idx]}")
        hint_esc=$(json_escape "${CHECK_HINT[$idx]}")
        case "${CHECK_STATUS[$idx]}" in
            pass) ((passed++)) ;;
            warn) ((warned++)) ;;
            fail) ((failed++)) ;;
        esac
        if [[ $idx -gt 0 ]]; then
            checks_json+=","
        fi
        checks_json+="{\"name\":\"$name_esc\",\"status\":\"$status_esc\",\"detail\":\"$detail_esc\",\"hint\":\"$hint_esc\"}"
    done
    checks_json+="]"

    total=${#CHECK_NAMES[@]}
    if [ "$failed" -gt 0 ]; then
        overall="failed"
    elif [ "$warned" -gt 0 ]; then
        overall="degraded"
    else
        overall="ok"
    fi

    exit_code=0
    if [ "$ERRORS" -gt 0 ]; then
        exit_code=1
    fi

    printf '{"checks":%s,"summary":{"passed":%d,"warned":%d,"failed":%d,"total":%d},"overall_status":"%s","exit_code":%d}\n' \
        "$checks_json" "$passed" "$warned" "$failed" "$total" "$overall" "$exit_code"
    exit $exit_code
fi

# Résumé
if [ "$JSON" != true ]; then
    echo -e "${BLUE}=== Résumé ===${NC}"
fi
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration complète et correcte!${NC}"
    echo ""
    echo "Prochaines étapes:"
    echo "1. Démarrer seal-server: cd release-8728fe7 && ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
    echo "2. Lancer les workers: ./launch-workers.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Configuration avec $WARNINGS avertissement(s)${NC}"
    exit 0
else
    echo -e "${RED}✗ Configuration avec $ERRORS erreur(s) et $WARNINGS avertissement(s)${NC}"
    exit 1
fi
