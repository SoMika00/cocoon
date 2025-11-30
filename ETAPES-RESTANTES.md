# 📋 Étapes Restantes pour Compiler QEMU

## Problème Détecté

La configuration a échoué car `glib-2.0` n'est pas trouvé. Il faut installer les dépendances manquantes.

## Commandes à Exécuter

### 1. Installer les dépendances manquantes

```bash
sudo apt install -y libglib2.0-dev libpixman-1-dev libfdt-dev
```

### 2. Vérifier que les dépendances sont installées

```bash
pkg-config --exists glib-2.0 && echo "✓ glib-2.0 OK" || echo "✗ glib-2.0 manquant"
pkg-config --exists pixman-1 && echo "✓ pixman OK" || echo "✗ pixman manquant"
```

### 3. Configurer QEMU

```bash
cd /tmp/qemu
rm -rf build  # Nettoyer si nécessaire
./configure --target-list=x86_64-softmmu --enable-kvm
```

### 4. Vérifier que la configuration a réussi

À la fin de la configuration, vous devriez voir quelque chose comme:
```
QEMU is configured as follows:
...
```

### 5. Compiler QEMU

```bash
make -j$(nproc)
```

Cela peut prendre 30-60 minutes.

### 6. Installer

```bash
sudo make install
```

### 7. Vérifier l'installation

```bash
/usr/local/bin/qemu-system-x86_64 --version
/usr/local/bin/qemu-system-x86_64 -machine help | grep -i tdx
```

Vous devriez voir:
```
q35-tdx          Q35-based PC with Intel TDX support
```

### 8. Relancer les workers COCOON

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

## Vérification Continue

Utilisez ces scripts pour surveiller:

```bash
# Vérifier l'état
./check-compilation.sh

# Surveiller la compilation
./monitor-compilation.sh

# Suivre les logs en temps réel
tail -f /tmp/qemu-compile.log
```

