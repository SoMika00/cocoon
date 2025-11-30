# ⚠️ Problème: TDX non supporté par KVM

## Erreur Détectée

```
qemu-system-x86_64: -accel kvm: vm-type TDX not supported by KVM
```

Cela signifie que votre **kernel KVM ne supporte pas TDX**, même si QEMU le supporte.

## Causes Possibles

1. **TDX non activé dans le BIOS/UEFI**
2. **Kernel sans support TDX compilé**
3. **Modules TDX non chargés**
4. **CPU sans support TDX ou TDX désactivé**

## Vérifications

### 1. Vérifier le CPU

```bash
cat /proc/cpuinfo | grep -i "tdx\|vmx"
```

### 2. Vérifier le kernel

```bash
uname -r
# Besoin: 6.16+ pour support TDX complet
```

### 3. Vérifier les modules TDX

```bash
lsmod | grep -i tdx
```

### 4. Vérifier /sys/firmware/tdx

```bash
ls -la /sys/firmware/tdx
```

Si ce répertoire n'existe pas, TDX n'est pas activé.

### 5. Vérifier dmesg

```bash
dmesg | grep -i tdx
```

## Solutions

### Option 1: Activer TDX dans le BIOS

1. Redémarrer et entrer dans le BIOS/UEFI
2. Chercher les options "Intel TDX" ou "Trust Domain Extensions"
3. Activer TDX
4. Sauvegarder et redémarrer

### Option 2: Vérifier le Kernel

Votre kernel actuel est `6.8.0-88-generic`. Vérifiez si le support TDX est compilé:

```bash
zcat /proc/config.gz | grep -i TDX
# ou
cat /boot/config-$(uname -r) | grep -i TDX
```

Vous devriez voir:
```
CONFIG_INTEL_TDX_HOST=y
CONFIG_INTEL_TDX_GUEST=y
```

### Option 3: Charger les modules TDX

```bash
sudo modprobe intel_tdx
sudo modprobe kvm_intel
```

### Option 4: Utiliser un Kernel avec Support TDX

Si votre kernel n'a pas le support TDX, vous devrez:
- Installer un kernel avec support TDX (6.16+)
- Ou compiler un kernel avec options TDX activées

## Documentation

- Intel TDX: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-trust-domain-extensions.html
- COCOON TDX: https://cocoon.org/tdx-and-images

## Note Importante

**TDX nécessite:**
- CPU Intel avec support TDX (Sapphire Rapids ou plus récent)
- TDX activé dans le BIOS
- Kernel Linux 6.16+ avec support TDX compilé
- Modules kernel TDX chargés

Si votre matériel ne supporte pas TDX, COCOON ne pourra pas fonctionner en mode production avec confidentialité complète.

