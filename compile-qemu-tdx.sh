#!/bin/bash
# Script pour compiler QEMU avec support TDX

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Compilation de QEMU avec Support TDX ===${NC}"
echo ""
echo "Ce script va compiler QEMU 10.1+ avec support TDX."
echo "Cela peut prendre 30-60 minutes selon votre CPU."
echo ""
# Auto-confirm si variable d'environnement est définie
if [ "${AUTO_CONFIRM}" != "1" ]; then
    read -p "Continuer? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Vérifier les dépendances
echo -e "${BLUE}1. Installation des dépendances...${NC}"
sudo apt update
sudo apt install -y build-essential git libglib2.0-dev libfdt-dev \
  libpixman-1-dev zlib1g-dev ninja-build python3-pip pkg-config \
  libcap-ng-dev libattr1-dev libslirp-dev meson

echo -e "${GREEN}✓${NC} Dépendances installées"
echo ""

# Cloner QEMU
echo -e "${BLUE}2. Clonage de QEMU...${NC}"
cd /tmp
if [ -d "qemu" ]; then
    echo "Répertoire qemu existe déjà, mise à jour..."
    cd qemu
    git pull
else
    git clone https://gitlab.com/qemu-project/qemu.git
    cd qemu
fi

# Utiliser version 10.1.0 ou plus récente
echo -e "${BLUE}3. Sélection de la version 10.1.0...${NC}"
git checkout v10.1.0 2>/dev/null || git checkout v10.2.0 || git checkout v11.0.0
echo -e "${GREEN}✓${NC} Version sélectionnée"
echo ""

# Configurer
echo -e "${BLUE}4. Configuration de QEMU...${NC}"
./configure --target-list=x86_64-softmmu --enable-kvm
echo -e "${GREEN}✓${NC} Configuration terminée"
echo ""

# Compiler
echo -e "${BLUE}5. Compilation de QEMU (cela peut prendre du temps)...${NC}"
echo "Utilisation de $(nproc) cœurs CPU"
make -j$(nproc)
echo -e "${GREEN}✓${NC} Compilation terminée"
echo ""

# Installer
echo -e "${BLUE}6. Installation de QEMU...${NC}"
sudo make install
echo -e "${GREEN}✓${NC} Installation terminée"
echo ""

# Vérifier
echo -e "${BLUE}7. Vérification...${NC}"
if /usr/local/bin/qemu-system-x86_64 --version > /dev/null 2>&1; then
    VERSION=$(/usr/local/bin/qemu-system-x86_64 --version | head -1)
    echo -e "${GREEN}✓${NC} QEMU installé: $VERSION"
    
    # Vérifier support TDX
    if /usr/local/bin/qemu-system-x86_64 -machine help 2>&1 | grep -qi tdx; then
        echo -e "${GREEN}✓${NC} Support TDX détecté!"
    else
        echo -e "${YELLOW}⚠${NC} Support TDX non clairement détecté (peut nécessiter options supplémentaires)"
    fi
else
    echo -e "${RED}✗${NC} Problème avec l'installation"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Compilation Terminée! ===${NC}"
echo ""
echo "QEMU est installé dans /usr/local/bin/qemu-system-x86_64"
echo "Vous pouvez maintenant relancer les workers COCOON:"
echo "  cd /home/mika/cocoon"
echo "  ./launch-workers.sh"

