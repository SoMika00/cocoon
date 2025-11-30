# ✅ Configuration Complète - 2 H100 COCOON

## 🎉 Tout est configuré et prêt!

Vos 2 GPU H100 sont maintenant configurés pour participer au pool GPU COCOON.

## 📋 Résumé de la Configuration

### GPUs Configurés
- **Worker 0:** GPU `0000:01:00.0` (H100 PCIe)
- **Worker 1:** GPU `0000:02:00.0` (H100 PCIe)

### Informations de Configuration
- **Wallet TON:** `UQA7I27M4mlGyFtZSF_u7GOq6B24rQO9r8oy5PlrLatn8Hxc`
- **Token Hugging Face:** `YOUR_HUGGINGFACE_TOKEN_HERE`
- **Contrat Root:** `EQC8m6wwiI3ZpNX6KZl1u8Fzj6OwvFgOHnQ8mzYg7MnyoYOO`
- **Clé Node Wallet:** Générée et configurée (gardez-la secrète!)

### Fichiers Créés
- ✅ `worker-0.conf` - Configuration pour GPU 0
- ✅ `worker-1.conf` - Configuration pour GPU 1
- ✅ Fichiers copiés dans `release-8728fe7/`

## 🚀 Démarrage Rapide

### 1. Vérifier la configuration

```bash
cd /home/mika/cocoon
./setup-complete.sh
```

### 2. Démarrer seal-server (OBLIGATOIRE)

**Dans un terminal séparé** (gardez-le ouvert):

```bash
cd /home/mika/cocoon/release-8728fe7
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

⚠️ **IMPORTANT:** `seal-server` doit être en cours d'exécution avant de lancer les workers!

### 3. Lancer les workers

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

Choisissez le mode:
- **1** = Production (recommandé)
- **2** = Test avec TON réel
- **3** = Test avec TON simulé

## 📊 Vérification

### Vérifier que les workers tournent

```bash
# Vérifier les processus
ps aux | grep cocoon-launch

# Vérifier les stats
curl http://localhost:12000/stats  # Worker 0
curl http://localhost:12010/stats  # Worker 1

# Vérifier les logs
tail -f release-8728fe7/logs/worker-0.log
tail -f release-8728fe7/logs/worker-1.log
```

## 🛑 Arrêter les workers

```bash
./stop-workers.sh
```

## ⚠️ Note sur l'Adresse du Contrat

Vous avez fourni l'adresse: `EQC8m6wwiI3ZpNX6KZl1u8Fzj6OwvFgOHnQ8mzYg7MnyoYOO`

L'exemple dans la distribution montre: `EQCns7bYSp0igFvS1wpb5wsZjCKCV19MD5AVzI4EyxsnU73k`

Si vous rencontrez des problèmes, vérifiez quelle est la bonne adresse pour votre réseau. Vous pouvez la modifier dans:
- `worker-0.conf`
- `worker-1.conf`

## 📁 Structure des Fichiers

```
/home/mika/cocoon/
├── release-8728fe7/          # Distribution COCOON extraite
│   ├── bin/                   # Binaires (seal-server, etc.)
│   ├── scripts/               # Scripts de lancement
│   ├── spec/                  # Configurations TON
│   ├── worker-0.conf          # Config Worker 0
│   └── worker-1.conf          # Config Worker 1
├── worker-0.conf              # Config Worker 0 (copie)
├── worker-1.conf              # Config Worker 1 (copie)
├── launch-workers.sh          # Script de lancement
├── stop-workers.sh            # Script d'arrêt
└── setup-complete.sh          # Vérification de config
```

## 🔧 Dépannage

### seal-server ne démarre pas
- Vérifiez que `./bin/enclave.signed.so` existe
- Vérifiez les permissions: `chmod +x ./bin/seal-server`

### Workers ne démarrent pas
1. Vérifiez que `seal-server` tourne: `pgrep -f seal-server`
2. Vérifiez les logs: `tail -f release-8728fe7/logs/worker-*.log`
3. Vérifiez la configuration: `cat release-8728fe7/worker-0.conf`

### Erreurs de connexion TON
- Vérifiez que `ton_config` pointe vers le bon fichier
- Vérifiez que `root_contract_address` est correcte

## 📚 Documentation

- Documentation complète: https://cocoon.org/gpu-owners
- README local: `README.md`
- Guide de démarrage: `GUIDE-DEMARRAGE.md`

## 🎯 Prochaines Étapes

1. ✅ Configuration complète
2. ⏳ Démarrer seal-server
3. ⏳ Lancer les workers
4. ⏳ Vérifier les stats
5. ⏳ Recevoir les paiements TON! 💰

**Bonne chance avec votre pool GPU COCOON! 🚀**

