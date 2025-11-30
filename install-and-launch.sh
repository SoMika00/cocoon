#!/bin/bash
# Script complet pour installer QEMU et lancer les workers

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Installation et Lancement COCOON Workers ===${NC}"
echo ""

# Étape 1: Vérifier QEMU
echo -e "${BLUE}1. Vérification de QEMU...${NC}"
if command -v qemu-system-x86_64 &> /dev/null; then
    VERSION=$(qemu-system-x86_64 --version | head -1)
    echo -e "${GREEN}✓${NC} QEMU installé: $VERSION"
else
    echo -e "${YELLOW}⚠${NC} QEMU non trouvé. Installation nécessaire..."
    echo ""
    echo "Exécutez cette commande pour installer QEMU:"
    echo -e "${GREEN}sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils${NC}"
    echo ""
    read -p "QEMU est-il maintenant installé? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation de QEMU requise avant de continuer${NC}"
        exit 1
    fi
    
    # Vérifier à nouveau
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo -e "${RED}✗${NC} QEMU toujours non trouvé. Vérifiez l'installation."
        exit 1
    fi
fi
echo ""

# Étape 2: Vérifier seal-server
echo -e "${BLUE}2. Vérification de seal-server...${NC}"
cd "$(dirname "$0")"
if pgrep -f "seal-server" > /dev/null; then
    echo -e "${GREEN}✓${NC} seal-server déjà en cours d'exécution"
else
    echo -e "${YELLOW}⚠${NC} Démarrage de seal-server..."
    cd release-8728fe7
    mkdir -p ../logs
    nohup ./bin/seal-server --enclave-path ./bin/enclave.signed.so > ../logs/seal-server.log 2>&1 &
    sleep 2
    if pgrep -f "seal-server" > /dev/null; then
        echo -e "${GREEN}✓${NC} seal-server démarré"
    else
        echo -e "${RED}✗${NC} Impossible de démarrer seal-server"
        exit 1
    fi
    cd ..
fi
echo ""

# Étape 3: Nettoyer les anciens processus
echo -e "${BLUE}3. Nettoyage des anciens processus...${NC}"
pkill -f "cocoon-launch" 2>/dev/null || true
sleep 1
echo -e "${GREEN}✓${NC} Nettoyage terminé"
echo ""

# Étape 4: Vérifier la configuration
echo -e "${BLUE}4. Vérification de la configuration...${NC}"
if [ -f "release-8728fe7/worker-0.conf" ] && [ -f "release-8728fe7/worker-1.conf" ]; then
    echo -e "${GREEN}✓${NC} Fichiers de configuration présents"
else
    echo -e "${RED}✗${NC} Fichiers de configuration manquants"
    exit 1
fi
echo ""

# Étape 5: Démarrer les workers
echo -e "${BLUE}5. Démarrage des workers...${NC}"
cd release-8728fe7
mkdir -p ../logs

echo -e "${YELLOW}Démarrage Worker 0 (GPU: 0000:01:00.0)...${NC}"
nohup ./scripts/cocoon-launch --instance 0 --gpu 0000:01:00.0 worker-0.conf > ../logs/worker-0.log 2>&1 &
WORKER0_PID=$!
echo "  PID: $WORKER0_PID"

sleep 3

echo -e "${YELLOW}Démarrage Worker 1 (GPU: 0000:02:00.0)...${NC}"
nohup ./scripts/cocoon-launch --instance 1 --gpu 0000:02:00.0 worker-1.conf > ../logs/worker-1.log 2>&1 &
WORKER1_PID=$!
echo "  PID: $WORKER1_PID"

cd ..
echo ""

# Étape 6: Vérifier le démarrage
echo -e "${BLUE}6. Vérification du démarrage...${NC}"
sleep 5

if pgrep -f "cocoon-launch.*instance.*0" > /dev/null; then
    echo -e "${GREEN}✓${NC} Worker 0 en cours d'exécution"
else
    echo -e "${YELLOW}⚠${NC} Worker 0 non détecté (peut être en cours d'initialisation)"
fi

if pgrep -f "cocoon-launch.*instance.*1" > /dev/null; then
    echo -e "${GREEN}✓${NC} Worker 1 en cours d'exécution"
else
    echo -e "${YELLOW}⚠${NC} Worker 1 non détecté (peut être en cours d'initialisation)"
fi
echo ""

# Étape 7: Afficher les logs
echo -e "${BLUE}7. Dernières lignes des logs:${NC}"
echo -e "${YELLOW}Worker 0:${NC}"
tail -3 logs/worker-0.log 2>/dev/null | head -3 || echo "  (log non disponible)"
echo ""
echo -e "${YELLOW}Worker 1:${NC}"
tail -3 logs/worker-1.log 2>/dev/null | head -3 || echo "  (log non disponible)"
echo ""

# Résumé
echo -e "${BLUE}=== Résumé ===${NC}"
echo ""
echo "Workers démarrés:"
echo "  Worker 0: PID $WORKER0_PID (GPU 0000:01:00.0)"
echo "  Worker 1: PID $WORKER1_PID (GPU 0000:02:00.0)"
echo ""
echo "Commandes utiles:"
echo "  Voir les logs: tail -f logs/worker-0.log"
echo "  Vérifier le statut: ./status-workers.sh"
echo "  Stats Worker 0: curl http://localhost:12000/stats"
echo "  Stats Worker 1: curl http://localhost:12010/stats"
echo "  Arrêter: ./stop-workers.sh"
echo ""
echo -e "${GREEN}Les workers sont en cours de démarrage. Cela peut prendre quelques minutes.${NC}"
echo -e "${YELLOW}Utilisez './status-workers.sh' pour vérifier le statut.${NC}"

