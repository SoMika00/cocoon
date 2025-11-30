# ⚠️ Problème: QEMU sans Support TDX

## Problème Détecté

Votre QEMU version **8.2.2** ne supporte pas TDX. L'erreur:
```
Parameter 'qom-type' does not accept value 'tdx-guest'
```

COCOON nécessite **QEMU 10.1+** avec support TDX compilé.

## Solutions

### Option 1: Compiler QEMU depuis les sources (Recommandé)

```bash
# Installer les dépendances
sudo apt install -y build-essential git libglib2.0-dev libfdt-dev \
  libpixman-1-dev zlib1g-dev ninja-build python3-pip pkg-config \
  libcap-ng-dev libattr1-dev libslirp-dev

# Cloner QEMU
cd /tmp
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu

# Utiliser une version récente avec support TDX (10.1+)
git checkout v10.1.0  # ou v10.2.0, v11.0.0, etc.

# Configurer avec support TDX
./configure --target-list=x86_64-softmmu --enable-kvm

# Compiler (cela peut prendre 30-60 minutes)
make -j$(nproc)

# Installer
sudo make install
```

Vérifier après installation:
```bash
/usr/local/bin/qemu-system-x86_64 --version
/usr/local/bin/qemu-system-x86_64 -machine help | grep -i tdx
```

### Option 2: Utiliser un PPA avec QEMU récent

Certains PPAs peuvent avoir des versions plus récentes, mais le support TDX n'est pas garanti.

### Option 3: Utiliser une Distribution Spécialisée

- **Ubuntu 24.04+** avec kernel 6.16+ peut avoir de meilleurs packages
- **Images spécialisées TDX** (Canonical, Intel)

### Option 4: Mode Test sans TDX (Limité)

Vous pouvez essayer le mode test sans TDX, mais cela ne fonctionnera pas pour la production:

```bash
cd /home/mika/cocoon/release-8728fe7
./scripts/cocoon-launch --test --fake-ton --no-tdx worker-0.conf
```

⚠️ **Note:** Le mode sans TDX ne fournit pas les garanties de confidentialité requises pour COCOON.

## Vérification du Support TDX

Après avoir installé QEMU avec support TDX:

```bash
qemu-system-x86_64 -machine help | grep -i tdx
```

Vous devriez voir quelque chose comme:
```
q35-tdx          Q35-based PC with Intel TDX support
```

## Prochaines Étapes

1. Compilez QEMU 10.1+ avec support TDX
2. Vérifiez que TDX est activé dans votre système
3. Relancez les workers

## Références

- Documentation COCOON: https://cocoon.org/gpu-owners
- QEMU TDX: https://www.qemu.org/docs/master/system/i386/tdx.html
- Intel TDX: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-trust-domain-extensions.html

