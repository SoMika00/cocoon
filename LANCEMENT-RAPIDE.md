# 🚀 Lancement Rapide des Workers COCOON

## ⚠️ Prérequis: QEMU doit être installé

Avant de lancer les workers, vous devez installer QEMU:

```bash
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils
```

Vérifiez l'installation:
```bash
qemu-system-x86_64 --version
```

## 🎯 Méthode 1: Script Automatique (Recommandé)

```bash
cd /home/mika/cocoon
./install-and-launch.sh
```

Ce script va:
1. ✅ Vérifier que QEMU est installé
2. ✅ Démarrer seal-server si nécessaire
3. ✅ Nettoyer les anciens processus
4. ✅ Lancer les 2 workers
5. ✅ Afficher le statut

## 🎯 Méthode 2: Lancement Manuel

### Étape 1: Démarrer seal-server

```bash
cd /home/mika/cocoon/release-8728fe7
./bin/seal-server --enclave-path ./bin/enclave.signed.so
```

**Gardez ce terminal ouvert!** Laissez seal-server tourner en arrière-plan.

### Étape 2: Dans un autre terminal, lancer les workers

```bash
cd /home/mika/cocoon
./launch-workers.sh
```

Ou manuellement:

```bash
cd /home/mika/cocoon/release-8728fe7

# Worker 0
nohup ./scripts/cocoon-launch --instance 0 --gpu 0000:01:00.0 worker-0.conf > ../logs/worker-0.log 2>&1 &

# Attendre quelques secondes
sleep 3

# Worker 1
nohup ./scripts/cocoon-launch --instance 1 --gpu 0000:02:00.0 worker-1.conf > ../logs/worker-1.log 2>&1 &
```

## 📊 Vérification

### Vérifier les processus

```bash
ps aux | grep -E "cocoon-launch|seal-server" | grep -v grep
```

### Vérifier les logs

```bash
# Worker 0
tail -f logs/worker-0.log

# Worker 1
tail -f logs/worker-1.log
```

### Vérifier les stats HTTP

```bash
# Worker 0
curl http://localhost:12000/stats

# Worker 1
curl http://localhost:12010/stats
```

### Script de statut

```bash
./status-workers.sh
```

## 🛑 Arrêter les Workers

```bash
./stop-workers.sh
```

## ⚠️ Dépannage

### Erreur "FileNotFoundError: qemu-system-x86_64"

**Solution:** QEMU n'est pas installé. Installez-le:
```bash
sudo apt install -y qemu-system-x86 qemu-utils
```

### Workers ne démarrent pas

1. Vérifiez que seal-server tourne:
   ```bash
   pgrep -f seal-server
   ```

2. Vérifiez les logs:
   ```bash
   tail -50 logs/worker-0.log
   ```

3. Vérifiez que QEMU est installé:
   ```bash
   which qemu-system-x86_64
   ```

### Ports déjà utilisés

Si les ports 12000 ou 12010 sont déjà utilisés:
```bash
# Trouver le processus
sudo lsof -i :12000
sudo lsof -i :12010

# Arrêter les anciens workers
./stop-workers.sh
```

## 📝 Notes

- Les workers peuvent prendre plusieurs minutes pour démarrer (téléchargement du modèle, initialisation TDX, etc.)
- Le premier démarrage peut être plus long (téléchargement du modèle depuis Hugging Face)
- Vérifiez régulièrement les logs pour suivre la progression

## ✅ Checklist

- [ ] QEMU installé (`qemu-system-x86_64 --version`)
- [ ] seal-server en cours d'exécution
- [ ] Workers lancés
- [ ] Logs sans erreurs critiques
- [ ] Stats HTTP accessibles

