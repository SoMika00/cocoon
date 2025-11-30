# 🔧 Compilation Manuelle de QEMU avec Support TDX

## Commandes à Exécuter

Exécutez ces commandes **dans votre terminal** (elles nécessitent sudo):

### Étape 1: Installer les dépendances

```bash
sudo apt update
sudo apt install -y build-essential git libglib2.0-dev libfdt-dev \
  libpixman-1-dev zlib1g-dev ninja-build python3-pip pkg-config \
  libcap-ng-dev libattr1-dev libslirp-dev meson
```

### Étape 2: Cloner QEMU

```bash
cd /tmp
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu
```

### Étape 3: Sélectionner la version 10.1.0

```bash
git checkout v10.1.0
```

Si v10.1.0 n'existe pas, essayez:
```bash
git checkout v10.2.0
# ou
git checkout v11.0.0
```

### Étape 4: Configurer avec support TDX

```bash
./configure --target-list=x86_64-softmmu --enable-kvm
```

### Étape 5: Compiler (30-60 minutes)

```bash
make -j$(nproc)
```

### Étape 6: Installer

```bash
sudo make install
```

### Étape 7: Vérifier

```bash
/usr/local/bin/qemu-system-x86_64 --version
/usr/local/bin/qemu-system-x86_64 -machine help | grep -i tdx
```

Vous devriez voir quelque chose comme:
```
q35-tdx          Q35-based PC with Intel TDX support
```

## Après Compilation

Une fois QEMU compilé et installé, relancez les workers:

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

## Vérifier l'État

Utilisez le script de vérification:

```bash
cd /home/mika/cocoon
./check-compilation.sh
```

## Notes

- La compilation peut prendre 30-60 minutes selon votre CPU
- Utilisez `htop` ou `top` pour surveiller l'utilisation CPU
- Vous pouvez suivre la progression avec: `tail -f /tmp/qemu/config.log`

