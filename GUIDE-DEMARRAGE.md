# 🚀 Guide de Démarrage Rapide - COCOON avec 2 H100

## Vue d'ensemble

Ce guide vous permet de configurer rapidement vos **2 GPU H100** pour participer au pool GPU décentralisé COCOON sur TON.

**Vos GPUs détectés:**
- GPU 0: `0000:01:00.0` (H100 PCIe)
- GPU 1: `0000:02:00.0` (H100 PCIe)

## 📝 Étapes de Configuration

### Étape 1: Vérifier les prérequis

```bash
./check-prerequisites.sh
```

Assurez-vous que:
- ✅ Kernel Linux 6.16+ (pour TDX complet)
- ✅ CPU Intel avec TDX activé
- ✅ QEMU 10.1+ installé
- ✅ TDX activé dans le BIOS/UEFI

### Étape 2: Télécharger COCOON

```bash
wget https://ci.cocoon.org/cocoon-worker-release-latest.tar.xz
tar xzf cocoon-worker-release-latest.tar.xz
cd cocoon-worker
```

### Étape 3: Préparer le matériel

**Activer TDX:**
- Suivez: https://cocoon.org/gpu-owners (section "Enabling Intel TDX")
- Vérifiez dans le BIOS/UEFI que TDX est activé

**Activer CC sur GPU:**
- Suivez: https://cocoon.org/gpu-owners (section "Enabling CC on NVIDIA GPU")
- Vous devrez peut-être mettre à jour le VBIOS

**Optionnel - Préparer VFIO:**
```bash
./scripts/setup-gpu-vfio  # Voir les instructions
```

### Étape 4: Configuration automatique

Depuis le répertoire `cocoon-worker`:

```bash
../setup-h100.sh
```

Cela crée `worker-0.conf` et `worker-1.conf`.

### Étape 5: Générer les clés

```bash
../generate-keys.sh
```

Copiez la clé générée (`node_wallet_key`) - vous en aurez besoin.

### Étape 6: Configurer les fichiers

Éditez `worker-0.conf` et `worker-1.conf` avec vos informations:

**Informations requises:**

1. **owner_address** - Votre adresse wallet TON
   - Format: `EQD...votre_adresse...`
   - C'est là que vous recevrez les paiements TON

2. **node_wallet_key** - Clé générée à l'étape 5
   - Utilisez la même clé pour les deux workers

3. **hf_token** - Token Hugging Face
   - Obtenez-le sur: https://huggingface.co/settings/tokens
   - Créez un token avec permissions "read"

4. **root_contract_address** - Adresse du contrat COCOON
   - Trouvez-la dans `worker.conf.example` de la distribution
   - C'est l'adresse du smart contract root sur TON

**Les GPUs sont déjà configurés automatiquement!**

### Étape 7: Démarrer seal-server

**⚠️ IMPORTANT:** `seal-server` doit tourner AVANT les workers.

Dans un terminal séparé (gardez-le ouvert):

```bash
cd cocoon-worker
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

Laissez-le tourner en arrière-plan. Un seul `seal-server` peut servir les 2 workers.

### Étape 8: Lancer les workers

```bash
../launch-workers.sh
```

Choisissez le mode:
- **1** = Production (recommandé, nécessite seal-server)
- **2** = Test avec TON réel
- **3** = Test avec TON simulé

Les workers démarrent automatiquement sur les 2 H100!

## 📊 Vérifier que tout fonctionne

### Vérifier les stats

```bash
# Worker 0 (GPU 0)
curl http://localhost:12000/stats

# Worker 1 (GPU 1)
curl http://localhost:12010/stats
```

### Vérifier les logs

```bash
tail -f logs/worker-0.log
tail -f logs/worker-1.log
```

### Vérifier les processus

```bash
ps aux | grep cocoon-launch
```

Vous devriez voir 2 processus en cours d'exécution.

## 🛑 Arrêter les workers

```bash
../stop-workers.sh
```

## 📈 Monitoring

### Endpoints HTTP disponibles

Chaque worker expose:
- `http://localhost:12000/stats` - Stats Worker 0 (format lisible)
- `http://localhost:12000/jsonstats` - Stats Worker 0 (JSON)
- `http://localhost:12010/stats` - Stats Worker 1
- `http://localhost:12010/jsonstats` - Stats Worker 1
- `http://localhost:12000/perf` - Métriques de performance Worker 0
- `http://localhost:12010/perf` - Métriques de performance Worker 1

### Health Client (si disponible)

```bash
./health-client --instance worker status
./health-client -i worker all
```

## ⚙️ Configuration Avancée

### Modifier le prix (worker_coefficient)

Dans `worker-0.conf` ou `worker-1.conf`:

```ini
worker_coefficient = 2000  # 2.0x le prix de base
```

### Changer le modèle AI

```ini
model = Qwen/Qwen3-0.6B  # Modèle par défaut
```

Ou via ligne de commande:

```bash
./scripts/cocoon-launch --model Qwen/Qwen3-0.6B worker-0.conf
```

### Lancer manuellement un worker

```bash
# Worker 0
./scripts/cocoon-launch --instance 0 --gpu 0000:01:00.0 worker-0.conf

# Worker 1
./scripts/cocoon-launch --instance 1 --gpu 0000:02:00.0 worker-1.conf
```

## 🔧 Dépannage

### seal-server ne démarre pas

- Vérifiez que `enclave.signed.so` existe dans `./bin/`
- Utilisez le fichier de la distribution officielle
- Vérifiez les permissions d'exécution

### Workers ne démarrent pas

1. Vérifiez que `seal-server` tourne: `pgrep -f seal-server`
2. Vérifiez les logs: `tail -f logs/worker-*.log`
3. Vérifiez la configuration: `cat worker-0.conf`
4. Vérifiez que TDX est activé: `ls /sys/firmware/tdx`

### GPU non détecté

- Vérifiez avec: `lspci | grep -i nvidia`
- Vérifiez que le GPU est bien configuré pour VFIO
- Vérifiez les permissions: `ls -l /dev/vfio/`

### Erreurs d'attestation

- Vérifiez que TDX est activé dans le BIOS
- Vérifiez que le VBIOS GPU est à jour
- Consultez la documentation: https://cocoon.org/gpu-owners

## 📚 Ressources

- **Documentation complète:** https://cocoon.org/gpu-owners
- **Architecture:** https://cocoon.org/architecture
- **GitHub:** https://github.com/cocoon-org
- **Downloads:** https://cocoon.org/downloads

## ✅ Checklist de Configuration

- [ ] Prérequis vérifiés (kernel, TDX, QEMU)
- [ ] Distribution COCOON téléchargée
- [ ] TDX activé dans le BIOS
- [ ] GPU préparé pour CC (VBIOS à jour si nécessaire)
- [ ] Fichiers de configuration créés (`worker-0.conf`, `worker-1.conf`)
- [ ] Clés générées (`node_wallet_key`)
- [ ] Toutes les valeurs configurées (owner_address, hf_token, root_contract_address)
- [ ] seal-server démarré et en cours d'exécution
- [ ] Workers lancés et fonctionnels
- [ ] Stats accessibles via HTTP
- [ ] Logs vérifiés (pas d'erreurs)

## 🎉 C'est tout!

Une fois configuré, vos 2 H100 participeront automatiquement au pool GPU COCOON et vous recevrez des paiements TON pour chaque requête traitée.

**Bonne chance avec votre configuration! 🚀**

