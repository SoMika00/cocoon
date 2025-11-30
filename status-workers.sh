#!/bin/bash
# Script pour vérifier le statut des workers COCOON

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Vérifier les ports HTTP
echo -e "${BLUE}3. Endpoints HTTP:${NC}"
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
echo -e "${BLUE}4. Dernières lignes des logs:${NC}"
echo -e "${YELLOW}Worker 0:${NC}"
tail -3 logs/worker-0.log 2>/dev/null || echo "  (log non disponible)"
echo ""
echo -e "${YELLOW}Worker 1:${NC}"
tail -3 logs/worker-1.log 2>/dev/null || echo "  (log non disponible)"
echo ""

# Commandes utiles
echo -e "${BLUE}Commandes utiles:${NC}"
echo "  Voir les logs: tail -f logs/worker-0.log"
echo "  Stats Worker 0: curl http://localhost:12000/stats"
echo "  Stats Worker 1: curl http://localhost:12010/stats"
echo "  Arrêter: ./stop-workers.sh"

