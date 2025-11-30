#!/bin/bash
# Script pour surveiller la compilation QEMU

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Surveillance de la Compilation QEMU ===${NC}"
echo ""

# Vérifier si compilation en cours
if pgrep -f "make.*qemu" > /dev/null; then
    PID=$(pgrep -f "make.*qemu" | head -1)
    echo -e "${GREEN}✓ Compilation en cours (PID: $PID)${NC}"
    
    # Afficher utilisation CPU
    if command -v top &> /dev/null; then
        echo ""
        echo "Utilisation CPU par le processus:"
        top -b -n 1 -p $PID 2>/dev/null | tail -2 || echo "  (non disponible)"
    fi
else
    echo -e "${YELLOW}⚠ Aucune compilation détectée${NC}"
fi

echo ""

# Afficher dernières lignes du log
if [ -f "/tmp/qemu-compile.log" ]; then
    echo -e "${BLUE}Dernières lignes du log:${NC}"
    tail -10 /tmp/qemu-compile.log
else
    echo -e "${YELLOW}⚠ Log non trouvé${NC}"
fi

echo ""

# Vérifier si binaire compilé
if [ -f "/tmp/qemu/build/qemu-system-x86_64" ]; then
    SIZE=$(ls -lh /tmp/qemu/build/qemu-system-x86_64 | awk '{print $5}')
    echo -e "${GREEN}✓ Binaire compilé trouvé (taille: $SIZE)${NC}"
else
    echo -e "${YELLOW}⚠ Binaire pas encore compilé${NC}"
fi

echo ""
echo "Commandes utiles:"
echo "  tail -f /tmp/qemu-compile.log  # Suivre en temps réel"
echo "  ./check-compilation.sh          # Vérifier l'état"
echo "  ps aux | grep make              # Voir les processus"

