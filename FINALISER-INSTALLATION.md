# 🔧 Finalisation de l'Installation

## ✅ État Actuel

- ✅ QEMU 10.1.0 compilé avec succès
- ✅ Binaire trouvé: `/tmp/qemu/build/qemu-system-x86_64` (79M)
- ⚠️ QEMU pas encore installé dans `/usr/local/bin/`
- ⚠️ Problème de permissions KVM

## 📋 Commandes à Exécuter

### 1. Installer QEMU (sudo requis)

```bash
cd /tmp/qemu
sudo make install
```

### 2. Vérifier l'installation

```bash
/usr/local/bin/qemu-system-x86_64 --version
```

Vous devriez voir: `QEMU emulator version 10.1.0`

### 3. Corriger les permissions KVM

```bash
# Vérifier si vous êtes dans le groupe kvm
groups | grep kvm

# Si pas dans le groupe, ajoutez-vous:
sudo usermod -aG kvm $USER

# Vérifier que /dev/kvm existe
ls -l /dev/kvm

# Si nécessaire, corriger les permissions
sudo chmod 666 /dev/kvm
```

**Important:** Après avoir ajouté votre utilisateur au groupe kvm, vous devez vous déconnecter et vous reconnecter (ou redémarrer) pour que les changements prennent effet.

### 4. Vérifier le support TDX

```bash
/usr/local/bin/qemu-system-x86_64 -machine help | grep -i tdx
```

### 5. Relancer les workers

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

## 🔍 Dépannage

### Si "Permission denied" persiste après ajout au groupe kvm

```bash
# Vérifier les permissions
ls -l /dev/kvm

# Si nécessaire, permissions temporaires (moins sécurisé)
sudo chmod 666 /dev/kvm
```

### Si QEMU n'est pas trouvé

Vérifiez que `/usr/local/bin` est dans votre PATH:
```bash
echo $PATH | grep /usr/local/bin
```

Si non, ajoutez-le:
```bash
export PATH=/usr/local/bin:$PATH
```

## ✅ Checklist Finale

- [ ] QEMU installé (`sudo make install`)
- [ ] Utilisateur dans le groupe kvm
- [ ] `/dev/kvm` accessible
- [ ] QEMU 10.1.0 dans PATH
- [ ] Workers relancés

