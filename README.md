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

### 2. Configuration automatique (télécharge la distribution si manquante)

```bash
chmod +x setup-h100.sh
./setup-h100.sh
```

Le script télécharge automatiquement `cocoon-worker-release-latest.tar.xz` via wget si `cocoon-worker/` ou `release-*/` est absent, l'extrait et change de répertoire. Utilisez `--dry-run` pour simuler.

### 3. Préparer le matériel

Avant de commencer, vous devez:

1. **Activer Intel TDX** - Suivez le guide: [Enabling Intel TDX](https://cocoon.org/gpu-owners)
2. **Activer CC sur GPU NVIDIA** - Vous devrez peut-être mettre à jour le VBIOS pour que l'attestation GPU fonctionne complètement
3. **Préparer le GPU pour VFIO** - Utilisez le script `./scripts/setup-gpu-vfio` si disponible

### 4. Éditer les fichiers de configuration

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

### 5. Démarrer seal-server

**IMPORTANT:** `seal-server` doit être lancé avant les workers. Il fournit la dérivation sécurisée des clés pour l'environnement TDX.

```bash
# Dans un terminal séparé, gardez-le en cours d'exécution
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

> **Note:** Vous devez utiliser le fichier `enclave.signed.so` inclus dans la distribution. Un seul `seal-server` peut servir plusieurs workers.

### 6. Lancer les workers

```bash
chmod +x launch-workers.sh
./launch-workers.sh
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
./launch-workers.sh --watchdog
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
chmod +x stop-workers.sh
./stop-workers.sh
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

... (rest of original README unchanged) ...

## 🛠️ System Health Check

A new helper script `system-health.sh` has been added to quickly verify that the entire COCOON deployment environment is ready.

```bash
chmod +x system-health.sh
./system-health.sh          # Human‑readable table output
./system-health.sh --json  # JSON output (useful for CI pipelines)
```

The script performs the following checks:

1. **Configuration validation** – runs `validate-config.sh` on all `worker-*.conf` files.
2. **seal‑server** – ensures a `seal-server` process is running.
3. **QEMU binary** – verifies `/usr/local/bin/qemu-system-x86_64` exists and reports its version.
4. **TDX support** – confirms the QEMU binary reports TDX support via `-machine help`.
5. **Worker processes** – checks that both workers are alive using their PID files (`logs/worker-0.pid` and `logs/worker-1.pid`).

The script prints a concise PASS/FAIL table and exits with status 0 when all checks succeed, otherwise with a non‑zero code.

---

*For any further assistance, refer to the existing documentation sections above.*