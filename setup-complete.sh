#!/bin/bash
# Script de configuration complète pour 2 H100 - Tout est déjà configuré!

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Configuration COCOON - 2 H100 ===${NC}"
echo ""

# Vérifier que nous sommes dans le bon répertoire
if [ ! -d "release-8728fe7" ]; then
    echo "Erreur: Le répertoire release-8728fe7 n'existe pas"
    echo "Assurez-vous d'avoir extrait l'archive COCOON"
    exit 1
fi

cd release-8728fe7

echo -e "${GREEN}✓ Configuration détectée:${NC}"
echo "  - Worker 0: GPU 0000:01:00.0 (H100)"
echo "  - Worker 1: GPU 0000:02:00.0 (H100)"
echo "  - Wallet TON: UQA7I27M4mlGyFtZSF_u7GOq6B24rQO9r8oy5PlrLatn8Hxc"
echo "  - Contrat root: EQC8m6wwiI3ZpNX6KZl1u8Fzj6OwvFgOHnQ8mzYg7MnyoYOO"
echo ""

# Vérifier que les fichiers de config existent
if [ ! -f "worker-0.conf" ] || [ ! -f "worker-1.conf" ]; then
    echo -e "${YELLOW}⚠ Les fichiers de configuration ne sont pas dans release-8728fe7/${NC}"
    echo "Copie depuis le répertoire parent..."
    cp ../worker-0.conf . 2>/dev/null || echo "worker-0.conf non trouvé"
    cp ../worker-1.conf . 2>/dev/null || echo "worker-1.conf non trouvé"
fi

echo -e "${GREEN}✓ Fichiers de configuration prêts${NC}"
echo ""

# Vérifier les prérequis
echo -e "${BLUE}Vérification des prérequis...${NC}"

# Vérifier seal-server
if [ -f "./bin/seal-server" ]; then
    echo -e "${GREEN}✓ seal-server trouvé${NC}"
else
    echo -e "${YELLOW}⚠ seal-server non trouvé${NC}"
fi

# Vérifier enclave
if [ -f "./bin/enclave.signed.so" ]; then
    echo -e "${GREEN}✓ enclave.signed.so trouvé${NC}"
else
    echo -e "${YELLOW}⚠ enclave.signed.so non trouvé${NC}"
fi

# Vérifier cocoon-launch
if [ -f "./scripts/cocoon-launch" ]; then
    echo -e "${GREEN}✓ cocoon-launch trouvé${NC}"
else
    echo -e "${YELLOW}⚠ cocoon-launch non trouvé${NC}"
fi

echo ""
echo -e "${BLUE}=== Prochaines étapes ===${NC}"
echo ""
echo "1. Démarrer seal-server (dans un terminal séparé):"
echo -e "   ${GREEN}./bin/seal-server --enclave-path ./bin/enclave.signed.so${NC}"
echo ""
echo "2. Lancer les workers:"
echo -e "   ${GREEN}../launch-workers.sh${NC}"
echo ""
echo "3. Vérifier les stats:"
echo "   curl http://localhost:12000/stats  # Worker 0"
echo "   curl http://localhost:12010/stats  # Worker 1"
echo ""
echo -e "${GREEN}Configuration complète! 🚀${NC}"

