#!/bin/bash
# Script de vérification complète de la configuration COCOON

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Vérification de la Configuration COCOON ===${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Fonction pour vérifier un fichier
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 (manquant)"
        ((ERRORS++))
        return 1
    fi
}

# Fonction pour vérifier une valeur dans un fichier
check_config_value() {
    local file=$1
    local key=$2
    local expected=$3
    
    if [ -f "$file" ]; then
        value=$(grep "^${key}" "$file" | cut -d'=' -f2 | tr -d ' ' | head -1)
        if [ "$value" = "$expected" ] || [ -z "$expected" ]; then
            if [ -n "$value" ] && [ "$value" != "YOUR_"* ] && [ "$value" != "[PRIVATE]" ]; then
                echo -e "${GREEN}✓${NC} $key = $value"
                return 0
            else
                echo -e "${RED}✗${NC} $key n'est pas configuré correctement"
                ((ERRORS++))
                return 1
            fi
        else
            echo -e "${YELLOW}⚠${NC} $key = $value (attendu: $expected)"
            ((WARNINGS++))
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Fichier $file non trouvé"
        ((ERRORS++))
        return 1
    fi
}

echo -e "${BLUE}1. Vérification des fichiers de la distribution...${NC}"
check_file "release-8728fe7/bin/seal-server"
check_file "release-8728fe7/bin/enclave.signed.so"
check_file "release-8728fe7/bin/health-client"
check_file "release-8728fe7/scripts/cocoon-launch"
check_file "release-8728fe7/spec/mainnet-base-ton-config.json"
check_file "release-8728fe7/worker.conf.example"
echo ""

echo -e "${BLUE}2. Vérification des fichiers de configuration...${NC}"
check_file "release-8728fe7/worker-0.conf"
check_file "release-8728fe7/worker-1.conf"
echo ""

echo -e "${BLUE}3. Vérification de la configuration Worker 0...${NC}"
if [ -f "release-8728fe7/worker-0.conf" ]; then
    check_config_value "release-8728fe7/worker-0.conf" "type" "worker"
    check_config_value "release-8728fe7/worker-0.conf" "owner_address" ""
    check_config_value "release-8728fe7/worker-0.conf" "gpu" "0000:01:00.0"
    check_config_value "release-8728fe7/worker-0.conf" "node_wallet_key" ""
    check_config_value "release-8728fe7/worker-0.conf" "hf_token" ""
    check_config_value "release-8728fe7/worker-0.conf" "root_contract_address" "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k"
    check_config_value "release-8728fe7/worker-0.conf" "instance" "0"
    check_config_value "release-8728fe7/worker-0.conf" "ton_config" "spec/mainnet-base-ton-config.json"
fi
echo ""

echo -e "${BLUE}4. Vérification de la configuration Worker 1...${NC}"
if [ -f "release-8728fe7/worker-1.conf" ]; then
    check_config_value "release-8728fe7/worker-1.conf" "type" "worker"
    check_config_value "release-8728fe7/worker-1.conf" "owner_address" ""
    check_config_value "release-8728fe7/worker-1.conf" "gpu" "0000:02:00.0"
    check_config_value "release-8728fe7/worker-1.conf" "node_wallet_key" ""
    check_config_value "release-8728fe7/worker-1.conf" "hf_token" ""
    check_config_value "release-8728fe7/worker-1.conf" "root_contract_address" "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k"
    check_config_value "release-8728fe7/worker-1.conf" "instance" "1"
    check_config_value "release-8728fe7/worker-1.conf" "ton_config" "spec/mainnet-base-ton-config.json"
fi
echo ""

echo -e "${BLUE}5. Vérification de la cohérence des configurations...${NC}"
if [ -f "release-8728fe7/worker-0.conf" ] && [ -f "release-8728fe7/worker-1.conf" ]; then
    OWNER0=$(grep "^owner_address" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    OWNER1=$(grep "^owner_address" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$OWNER0" = "$OWNER1" ]; then
        echo -e "${GREEN}✓${NC} owner_address identique dans les deux workers"
    else
        echo -e "${YELLOW}⚠${NC} owner_address différent entre les workers"
        ((WARNINGS++))
    fi
    
    KEY0=$(grep "^node_wallet_key" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    KEY1=$(grep "^node_wallet_key" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$KEY0" = "$KEY1" ]; then
        echo -e "${GREEN}✓${NC} node_wallet_key identique dans les deux workers"
    else
        echo -e "${YELLOW}⚠${NC} node_wallet_key différent entre les workers"
        ((WARNINGS++))
    fi
    
    ROOT0=$(grep "^root_contract_address" release-8728fe7/worker-0.conf | cut -d'=' -f2 | tr -d ' ')
    ROOT1=$(grep "^root_contract_address" release-8728fe7/worker-1.conf | cut -d'=' -f2 | tr -d ' ')
    if [ "$ROOT0" = "$ROOT1" ] && [ "$ROOT0" = "EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k" ]; then
        echo -e "${GREEN}✓${NC} root_contract_address correct et identique (officiel)"
    else
        echo -e "${RED}✗${NC} root_contract_address incorrect ou différent"
        ((ERRORS++))
    fi
fi
echo ""

echo -e "${BLUE}6. Vérification des GPUs...${NC}"
GPU_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
if [ "$GPU_COUNT" -ge 2 ]; then
    echo -e "${GREEN}✓${NC} $GPU_COUNT GPU(s) H100 détecté(s)"
    lspci | grep -i "H100\|GH100" | awk '{print "  - 0000:" $1}'
else
    echo -e "${RED}✗${NC} Moins de 2 GPUs H100 détectés"
    ((ERRORS++))
fi
echo ""

echo -e "${BLUE}7. Vérification des permissions...${NC}"
if [ -x "release-8728fe7/bin/seal-server" ]; then
    echo -e "${GREEN}✓${NC} seal-server exécutable"
else
    echo -e "${YELLOW}⚠${NC} seal-server non exécutable (chmod +x)"
    ((WARNINGS++))
fi

if [ -x "release-8728fe7/scripts/cocoon-launch" ]; then
    echo -e "${GREEN}✓${NC} cocoon-launch exécutable"
else
    echo -e "${YELLOW}⚠${NC} cocoon-launch non exécutable (chmod +x)"
    ((WARNINGS++))
fi
echo ""

echo -e "${BLUE}8. Vérification du format des fichiers...${NC}"
if grep -q "^\[node\]" release-8728fe7/worker-0.conf 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Format [node] correct dans worker-0.conf"
else
    echo -e "${RED}✗${NC} Format incorrect dans worker-0.conf (devrait être [node])"
    ((ERRORS++))
fi

if grep -q "^\[node\]" release-8728fe7/worker-1.conf 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Format [node] correct dans worker-1.conf"
else
    echo -e "${RED}✗${NC} Format incorrect dans worker-1.conf (devrait être [node])"
    ((ERRORS++))
fi
echo ""

# Résumé
echo -e "${BLUE}=== Résumé ===${NC}"
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

