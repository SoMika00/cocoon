# ✅ Configuration Finale - COCOON 2 H100

## 🎉 Configuration Complète et Vérifiée!

Tous les fichiers ont été configurés selon la documentation officielle COCOON.

## ✅ Vérifications Effectuées

### ✓ Adresse du Contrat Root
- **Utilisée:** `EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k`
- **Source:** Distribution officielle `worker.conf.example`
- **Statut:** ✅ Correcte selon la documentation

### ✓ Configuration des Workers

**Worker 0 (GPU 0000:01:00.0):**
- ✅ Format `[node]` correct
- ✅ Tous les paramètres requis configurés
- ✅ Adresse wallet TON: `UQA7I27M4mlGyFtZSF_u7GOq6B24rQO9r8oy5PlrLatn8Hxc`
- ✅ Token Hugging Face configuré
- ✅ Clé node_wallet_key générée
- ✅ Instance 0 configurée
- ✅ Config TON: `spec/mainnet-base-ton-config.json`

**Worker 1 (GPU 0000:02:00.0):**
- ✅ Format `[node]` correct
- ✅ Tous les paramètres requis configurés
- ✅ Même wallet et clés que Worker 0
- ✅ Instance 1 configurée
- ✅ GPU 0000:02:00.0 configuré

### ✓ Fichiers de la Distribution
- ✅ `seal-server` présent et exécutable
- ✅ `enclave.signed.so` présent
- ✅ `cocoon-launch` présent et exécutable
- ✅ `health-client` présent
- ✅ `mainnet-base-ton-config.json` présent

### ✓ GPUs Détectés
- ✅ 2 GPUs H100 détectés
- ✅ GPU 0: `0000:01:00.0`
- ✅ GPU 1: `0000:02:00.0`

## 📋 Résumé de la Configuration

| Paramètre | Valeur |
|-----------|--------|
| **Wallet TON** | `UQA7I27M4mlGyFtZSF_u7GOq6B24rQO9r8oy5PlrLatn8Hxc` |
| **Token HF** | `YOUR_HUGGINGFACE_TOKEN_HERE` |
| **Contrat Root** | `EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k` (officiel) |
| **Modèle** | `Qwen/Qwen3-8B@b968826d9c46dd6066d109eabc6255188de91218:7e9d33bebf5518e0dc666e5a04ffbab247ff5878f91a9a55a6e942fe245a8ee9` |
| **Config TON** | `spec/mainnet-base-ton-config.json` |
| **Worker 0 GPU** | `0000:01:00.0` |
| **Worker 1 GPU** | `0000:02:00.0` |

## 🚀 Démarrage

### Étape 1: Vérifier la Configuration

```bash
cd /home/mika/cocoon
./verify-config.sh
```

### Étape 2: Démarrer seal-server

**Dans un terminal séparé** (gardez-le ouvert):

```bash
cd /home/mika/cocoon/release-8728fe7
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

⚠️ **CRITIQUE:** `seal-server` doit être en cours d'exécution avant de lancer les workers!

### Étape 3: Lancer les Workers

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

Choisissez le mode:
- **1** = Production (recommandé)
- **2** = Test avec TON réel
- **3** = Test avec TON simulé

### Étape 4: Vérifier le Fonctionnement

```bash
# Vérifier les stats
curl http://localhost:12000/stats  # Worker 0
curl http://localhost:12010/stats  # Worker 1

# Vérifier les processus
ps aux | grep cocoon-launch

# Vérifier les logs
tail -f release-8728fe7/logs/worker-0.log
tail -f release-8728fe7/logs/worker-1.log
```

## 📊 Monitoring

### Endpoints HTTP

- **Worker 0:** 
  - Stats: `http://localhost:12000/stats`
  - JSON: `http://localhost:12000/jsonstats`
  - Perf: `http://localhost:12000/perf`

- **Worker 1:**
  - Stats: `http://localhost:12010/stats`
  - JSON: `http://localhost:12010/jsonstats`
  - Perf: `http://localhost:12010/perf`

### Health Client

```bash
cd release-8728fe7
./bin/health-client --instance worker status
./bin/health-client -i worker all
```

## 🛑 Arrêter les Workers

```bash
./stop-workers.sh
```

## 📁 Structure des Fichiers

```
/home/mika/cocoon/
├── release-8728fe7/              # Distribution COCOON
│   ├── bin/
│   │   ├── seal-server           # ✅ Présent
│   │   ├── enclave.signed.so     # ✅ Présent
│   │   └── health-client         # ✅ Présent
│   ├── scripts/
│   │   └── cocoon-launch         # ✅ Présent
│   ├── spec/
│   │   └── mainnet-base-ton-config.json  # ✅ Présent
│   ├── worker-0.conf             # ✅ Configuré
│   └── worker-1.conf             # ✅ Configuré
├── worker-0.conf                 # Copie
├── worker-1.conf                 # Copie
├── verify-config.sh              # Script de vérification
├── launch-workers.sh             # Script de lancement
├── stop-workers.sh               # Script d'arrêt
└── FINAL-SETUP.md                # Ce fichier
```

## ✅ Checklist Finale

- [x] Distribution COCOON téléchargée et extraite
- [x] Fichiers de configuration créés (worker-0.conf, worker-1.conf)
- [x] Adresse du contrat root officielle configurée
- [x] Tous les paramètres requis remplis
- [x] Format `[node]` correct
- [x] GPUs détectés et configurés
- [x] Permissions vérifiées
- [x] Configuration vérifiée avec `verify-config.sh`
- [ ] seal-server démarré
- [ ] Workers lancés
- [ ] Stats vérifiées

## 🎯 Prochaines Actions

1. **Démarrer seal-server** (obligatoire)
2. **Lancer les workers** avec `./launch-workers.sh`
3. **Vérifier les stats** pour confirmer le fonctionnement
4. **Recevoir les paiements TON!** 💰

## 📚 Documentation

- Documentation officielle: https://cocoon.org/gpu-owners
- README local: `README.md`
- Guide de démarrage: `GUIDE-DEMARRAGE.md`

---

**Configuration complète et prête! 🚀**

Tous les fichiers sont configurés selon la documentation officielle COCOON. Vous pouvez maintenant démarrer vos workers!

