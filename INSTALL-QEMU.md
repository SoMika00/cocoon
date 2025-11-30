# Installation de QEMU avec Support TDX

## Problème Détecté

QEMU n'est pas installé sur votre système. COCOON nécessite **QEMU 10.1+** avec support TDX.

## Installation

### Option 1: Installation via apt (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils
```

**Note:** La version dans les dépôts standards peut ne pas avoir le support TDX complet. Vérifiez la version après installation:

```bash
qemu-system-x86_64 --version
```

### Option 2: Compilation depuis les sources (Recommandé pour TDX)

Pour avoir le support TDX complet, vous devrez peut-être compiler QEMU depuis les sources:

```bash
# Installer les dépendances
sudo apt install build-essential git libglib2.0-dev libfdt-dev \
  libpixman-1-dev zlib1g-dev ninja-build python3-pip

# Cloner QEMU (version récente avec support TDX)
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu
git checkout v10.1.0  # ou version plus récente

# Configurer avec support TDX
./configure --target-list=x86_64-softmmu --enable-kvm

# Compiler (cela peut prendre du temps)
make -j$(nproc)

# Installer
sudo make install
```

### Option 3: Utiliser une distribution avec QEMU pré-configuré

Certaines distributions comme Ubuntu 24.04+ ou des images spécialisées pour TDX peuvent avoir QEMU avec support TDX pré-installé.

## Vérification

Après installation, vérifiez:

```bash
# Version
qemu-system-x86_64 --version

# Support TDX (devrait afficher "tdx-guest" dans les options)
qemu-system-x86_64 -machine help | grep -i tdx
```

## Après Installation

Une fois QEMU installé, relancez les workers:

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

## Note Importante

Selon la documentation COCOON, vous avez besoin de:
- **QEMU 10.1+** avec support TDX
- **Kernel Linux 6.16+** pour support TDX complet
- **CPU Intel avec TDX** activé dans le BIOS

Vérifiez aussi que TDX est activé dans votre système avant de continuer.

