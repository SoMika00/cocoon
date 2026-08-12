# Configuration COCOON pour 2 H100

Ce guide vous aide à configurer vos 2 GPU H100 pour participer au pool GPU COCOON.

## 📋 Prérequis

Selon la [documentation COCOON](https://cocoon.org/gpu-owners), vous avez besoin de:

- **Linux** avec kernel **6.16+** (pour support TDX complet)
- **CPU Intel avec support TDX**
- **GPU NVIDIA H100+** avec support CC (Confidential Computing)
- **QEMU 10.1+** avec support TDX

Vos 2 H100 détectés:
- GPU 0: `0000:01:00.0`
- GPU 1: `0000:02:00.0`

## 🚀 Installation Rapide

### 1. Vérifier les prérequis

```bash
chmod +x check-prerequisites.sh
./check-prerequisites.sh
```

### 2. Télécharger la distribution COCOON

```bash
wget https://ci.cocoon.org/cocoon-worker-release-latest.tar.xz
tar xzf cocoon-worker-release-latest.tar.xz
cd cocoon-worker
```

### 3. Préparer le matériel

Avant de commencer, vous devez:

1. **Activer Intel TDX** - Suivez le guide: [Enabling Intel TDX](https://cocoon.org/gpu-owners)
2. **Activer CC sur GPU NVIDIA** - Vous devrez peut-être mettre à jour le VBIOS pour que l'attestation GPU fonctionne complètement
3. **Préparer le GPU pour VFIO** - Utilisez le script `./scripts/setup-gpu-vfio` si disponible

### 4. Configuration automatique

```bash
# Depuis le répertoire cocoon-worker
chmod +x ../setup-h100.sh
../setup-h100.sh
```

Cela créera:
- `worker-0.conf` - Configuration pour le premier H100
- `worker-1.conf` - Configuration pour le deuxième H100

### 5. Éditer les fichiers de configuration

Éditez `worker-0.conf` et `worker-1.conf` avec vos informations:

**Paramètres requis:**

```ini
# Votre adresse wallet TON (reçoit les paiements)
owner_address = EQD...votre_adresse_ton...

# Clé privée pour le wallet de revenus (générer avec: openssl rand -base64 32)
node_wallet_key = votre_clé_base64_ici

# Token Hugging Face (obtenir sur https://huggingface.co/settings/tokens)
hf_token = hf_votre_token_ici

# Adresse du contrat root COCOON (dans worker.conf.example de la distribution)
root_contract_address = EQD...adresse_du_contrat...
```

**Les GPUs sont déjà configurés:**
- Worker 0: `0000:01:00.0`
- Worker 1: `0000:02:00.0`

### 6. Démarrer seal-server

**IMPORTANT:** `seal-server` doit être lancé avant les workers. Il fournit la dérivation sécurisée des clés pour l'environnement TDX.

```bash
# Dans un terminal séparé, gardez-le en cours d'exécution
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

> **Note:** Vous devez utiliser le fichier `enclave.signed.so` inclus dans la distribution. Un seul `seal-server` peut servir plusieurs workers.

### 7. Lancer les workers

```bash
chmod +x ../launch-workers.sh
../launch-workers.sh
```

Le script vous demandera le mode:
- **Production** - Mode production (nécessite seal-server)
- **Test (real TON)** - Mode test avec shell debug, TON réel
- **Test (fake TON)** - Mode test avec shell debug, TON simulé

## 📊 Monitoring

### Watchdog (auto-restart)

`watchdog.sh` surveille les workers et redémarre automatiquement en cas d'échec.

```bash
chmod +x watchdog.sh
./watchdog.sh --max-retries 5 --backoff 10
```

Lancer via launch-workers.sh:

```bash
../launch-workers.sh --watchdog
```

Logs des redémarrages: `logs/watchdog.log`
Mode dry-run: `./watchdog.sh --dry-run`

### Statistiques HTTP

```bash
# Worker 0
curl http://localhost:12000/stats
curl http://localhost:12000/jsonstats

# Worker 1
curl http://localhost:12010/stats
curl http://localhost:12010/jsonstats
```

### Health Client

Si disponible dans la distribution:

```bash
# Statut des workers
./health-client --instance worker status

# Métriques système
./health-client -i worker sys

# Métriques GPU
./health-client -i worker gpu

# Logs
./health-client -i worker logs cocoon-vllm 100
```

### Logs

```bash
# Suivre les logs en temps réel
tail -f logs/worker-0.log
tail -f logs/worker-1.log
```

## 🚫 Arrêter les workers

```bash
chmod +x ../stop-workers.sh
../stop-workers.sh
```

Ou manuellement:

```bash
# Si vous avez les PIDs sauvegardés
kill $(cat logs/worker-0.pid)
kill $(cat logs/worker-1.pid)
```

## 🔧 Configuration Avancée

### Options de configuration

Chaque worker peut être configuré avec:

- `worker_coefficient` - Coefficient de prix (1000 = 1.0x, valeurs plus élevées = prix plus élevées)
- `model` - Modèle AI à servir (par défaut: `Qwen/Qwen3-0.6B`)
- `persistent` - Chemin de l'image disque persistante

### Lancer avec options en ligne de commande

```bash
# Override des options
./scripts/cocoon-launch --instance 0 --worker-coefficient 2000 --model Qwen/Qwen3-0.6B worker-0.conf
```

### Ports et CIDs

Chaque instance obtient automatiquement:
- **Ports uniques:** 12000, 12010, 12020, ...
- **CIDs uniques:** 6, 16, 26, ...
- **Stockage persistant séparé**

## 📚 Documentation

- [Architecture COCOON](https://cocoon.org/architecture)
- [TDX et Images](https://cocoon.org/tdx-and-images)
- [RA-TLS](https://cocoon.org/ra-tls)
- [Smart Contracts](https://cocoon.org/smart-contracts)
- [Seal Keys](https://cocoon.org/seal-keys)
- [Deployment](https://cocoon.org/deployment)

## ⚠️ Notes Importantes

1. **seal-server est obligatoire** pour la production. Sans lui, les workers échoueront à l'initialisation.

2. **enclave.signed.so** doit être celui de la distribution officielle.

3. **TDX doit être activé** dans le BIOS/UEFI et le kernel Linux.

4. **VBIOS GPU** peut nécessiter une mise à jour pour l'attestation complète.

5. **Gardez vos clés privées secrètes** - `node_wallet_key` doit rester confidentiel.

## 💡 Dépannage

### Vérifier que seal-server tourne

```bash
pgrep -f seal-server
```

### Vérifier les processus workers

```bash
ps aux | grep cocoon-launch
```

### Vérifier les ports

```bash
netstat -tlnp | grep -E "12000|12010"
```

### Logs d'erreur

Consultez les logs dans `logs/worker-*.log` pour diagnostiquer les problèmes.

## 📞 Support

Pour plus d'aide:
- Documentation: https://cocoon.org/gpu-owners
- GitHub: https://github.com/cocoon-org
- Telegram: (voir site web)
