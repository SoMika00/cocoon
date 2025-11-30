#!/bin/bash
# Script pour vérifier l'état de la compilation QEMU

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== État de la Compilation QEMU ===${NC}"
echo ""

# Vérifier si compilation en cours
if pgrep -f "compile-qemu\|configure\|make.*qemu" > /dev/null; then
    echo -e "${YELLOW}⚠ Compilation en cours...${NC}"
    echo ""
    echo "Processus actifs:"
    ps aux | grep -E "compile-qemu|configure|make" | grep -v grep | head -5
    echo ""
    echo "Vérifiez les logs dans /tmp/qemu/"
else
    echo -e "${GREEN}✓ Pas de compilation en cours${NC}"
fi

echo ""

# Vérifier répertoire QEMU
if [ -d "/tmp/qemu" ]; then
    echo -e "${BLUE}Répertoire QEMU:${NC}"
    cd /tmp/qemu
    echo "  Chemin: $(pwd)"
    echo "  Taille: $(du -sh . 2>/dev/null | cut -f1)"
    
    if [ -f "config.log" ]; then
        echo -e "${GREEN}✓ Configuration terminée${NC}"
    fi
    
    if [ -f "build/qemu-system-x86_64" ]; then
        echo -e "${GREEN}✓ Binaire compilé trouvé${NC}"
        ls -lh build/qemu-system-x86_64
    fi
else
    echo -e "${YELLOW}⚠ Répertoire /tmp/qemu non trouvé${NC}"
fi

echo ""

# Vérifier QEMU installé
if [ -f "/usr/local/bin/qemu-system-x86_64" ]; then
    echo -e "${BLUE}QEMU installé:${NC}"
    /usr/local/bin/qemu-system-x86_64 --version | head -1
    
    if /usr/local/bin/qemu-system-x86_64 -machine help 2>&1 | grep -qi tdx; then
        echo -e "${GREEN}✓ Support TDX détecté!${NC}"
    else
        echo -e "${YELLOW}⚠ Support TDX non détecté${NC}"
    fi
else
    echo -e "${YELLOW}⚠ QEMU non installé dans /usr/local/bin/${NC}"
fi

echo ""
echo "Pour suivre la compilation en temps réel:"
echo "  tail -f /tmp/qemu/config.log"
echo "  watch -n 5 'ps aux | grep make'"

