# Guide de Test - Cluster Nantes (Grid5000)

## Prérequis

- Compte Grid5000 actif
- Clé SSH configurée
- Accès au site de Nantes

---

## Étape 1 : Connexion à Grid5000

```bash
# Depuis votre machine locale
ssh <votre-login>@access.grid5000.fr

# Puis connexion au site Nantes
ssh nantes
```

---

## Étape 2 : Cloner et Préparer le Projet

```bash
# Aller dans votre home
cd ~

# Cloner le repository (ou copier vos fichiers)
git clone <URL_REPO> wordcount-distributed
cd wordcount-distributed

# Vérifier la structure
ls -la
# Vous devez voir: src/ benchmarks/ model/ CAHIER_DE_LABORATOIRE.org etc.

# Compiler le projet Java
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java")

# Compiler wordcount (si vous avez le fichier C)
gcc -O2 -o wordcount test/wordcount.c
```

---

## Étape 3 : Réserver des Nœuds sur Nantes

### Option A : Réservation Interactive (Recommandé pour les tests)

```bash
# Réserver 5 nœuds pour 1 heure (1 master + 4 workers)
oarsub -I -l nodes=5,walltime=1:00:00

# Pour plus de nœuds (ex: 10 nœuds pour 2 heures)
oarsub -I -l nodes=10,walltime=2:00:00

# Pour 65 nœuds (test complet 64 workers)
oarsub -I -l nodes=65,walltime=4:00:00
```

### Option B : Réservation avec Script

```bash
# Créer un script de job
cat > job_test.sh << 'EOF'
#!/bin/bash
#OAR -l nodes=5,walltime=1:00:00
#OAR -O job_output.log
#OAR -E job_error.log

cd ~/wordcount-distributed
export PROJECT_DIR=$HOME/wordcount-distributed
bash benchmarks/run_rmi_benchmark.sh
EOF

# Soumettre le job
oarsub -S ./job_test.sh
```

---

## Étape 4 : Vérifier les Nœuds Alloués

Une fois la réservation obtenue (vous êtes dans le job) :

```bash
# Voir tous les nœuds alloués
cat $OAR_NODEFILE

# Voir les nœuds uniques
cat $OAR_NODEFILE | sort -u

# Compter le nombre de nœuds
cat $OAR_NODEFILE | sort -u | wc -l

# Identifier le master (premier nœud)
head -n 1 $OAR_NODEFILE

# Identifier les workers (tous sauf le premier)
tail -n +2 $OAR_NODEFILE | sort -u
```

**Exemple de sortie sur Nantes :**
```
ecotype-1.nantes.grid5000.fr
ecotype-2.nantes.grid5000.fr
ecotype-3.nantes.grid5000.fr
ecotype-4.nantes.grid5000.fr
ecotype-5.nantes.grid5000.fr
```

---

## Étape 5 : Test Manuel (Comprendre le Fonctionnement)

### 5.1 Lancer les Workers manuellement

```bash
# Définir les variables
PROJECT_DIR=$HOME/wordcount-distributed
cd $PROJECT_DIR

# Obtenir la liste des workers
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | sort -u)

echo "Master: $MASTER"
echo "Workers: $WORKERS"

# Lancer un worker sur chaque nœud (sauf le master)
for worker in $WORKERS; do
    echo "Démarrage du worker sur $worker..."
    ssh $worker "cd $PROJECT_DIR && java -cp bin network.worker.WorkerNode $worker 3000" &
    sleep 2
done

# Attendre que les workers soient prêts
sleep 5
```

### 5.2 Vérifier que les Workers sont Prêts

```bash
# Vérifier le port 3000 sur chaque worker
for worker in $WORKERS; do
    echo -n "Vérification de $worker... "
    if ssh $worker "netstat -ln | grep -q :3000"; then
        echo "✅ OK"
    else
        echo "❌ NON PRÊT"
    fi
done
```

### 5.3 Tester avec un Fichier Simple

```bash
# Créer un fichier de test
echo "hello world test grid5000 nantes" > test_input.txt
for i in $(seq 1 1000); do
    echo "word$i another$i test$i" >> test_input.txt
done

# Préparer la liste des workers (format: [host1:port,host2:port,...])
WORKER_LIST=$(echo $WORKERS | tr ' ' '\n' | sed 's/$/:3000/' | tr '\n' ',' | sed 's/,$//')
echo "Worker list: [$WORKER_LIST]"

# Lancer le master
java -cp bin scheduler.Main test_input.txt "[$WORKER_LIST]"
```

### 5.4 Arrêter les Workers

```bash
# Arrêter tous les workers
for worker in $WORKERS; do
    ssh $worker "pkill -f WorkerNode" 2>/dev/null
done
```

---

## Étape 6 : Exécuter les Benchmarks Automatisés

### 6.1 Benchmark Latence RMI

```bash
cd ~/wordcount-distributed
export PROJECT_DIR=$HOME/wordcount-distributed

# Exécuter le benchmark RMI
bash benchmarks/run_rmi_benchmark.sh

# Les résultats seront dans:
ls -la benchmarks/results/rmi/
```

### 6.2 Benchmark Temps de Calcul (Wordcount)

```bash
# Ce benchmark peut s'exécuter sur un seul nœud
bash benchmarks/run_wordcount_benchmark.sh

# Résultats dans:
ls -la benchmarks/results/compute/
```

### 6.3 Benchmark Transfert (SCP/NFS)

```bash
bash benchmarks/run_transfer_benchmark.sh

# Résultats dans:
ls -la benchmarks/results/transfer/
```

### 6.4 Benchmark Initialisation

```bash
bash benchmarks/run_init_benchmark.sh

# Résultats dans:
ls -la benchmarks/results/init/
```

---

## Étape 7 : Calibrer le Modèle

```bash
# Une fois tous les benchmarks exécutés
python3 benchmarks/calibrate_model.py \
    --results-dir benchmarks/results \
    --output model/model_config.ini

# Vérifier le fichier de configuration généré
cat model/model_config.ini
```

---

## Étape 8 : Validation du Modèle

```bash
# Nécessite une réservation avec suffisamment de nœuds
# Pour tester jusqu'à 64 workers: oarsub -I -l nodes=65,walltime=4:00:00

bash benchmarks/validate_model.sh

# Générer les graphiques (si matplotlib installé)
python3 benchmarks/plot_validation.py \
    benchmarks/results/validation/validation_*.csv \
    --output benchmarks/results/plots/
```

---

## Étape 9 : Récupérer les Résultats

### Depuis le frontend Nantes vers votre machine locale :

```bash
# Sur votre machine locale
scp -r <login>@access.grid5000.fr:nantes/wordcount-distributed/benchmarks/results ./results_nantes/
```

### Ou créer une archive :

```bash
# Sur Nantes
cd ~/wordcount-distributed
tar -czvf results_$(date +%Y%m%d).tar.gz benchmarks/results/

# Puis récupérer l'archive
```

---

## Commandes Utiles Grid5000

```bash
# Voir vos jobs en cours
oarstat -u

# Annuler un job
oardel <JOB_ID>

# Voir les ressources disponibles sur Nantes
oarstat -f | grep nantes

# Voir l'état du cluster
oarnodes -s

# Informations sur les clusters disponibles à Nantes
# (Nantes a le cluster "ecotype")
```

---

## Dépannage

### Problème : "Permission denied" lors de SSH entre nœuds

```bash
# Vérifier que votre clé SSH est propagée
ssh-add -l

# Si vide, ajouter votre clé
ssh-add ~/.ssh/id_rsa
```

### Problème : Worker ne démarre pas

```bash
# Vérifier si Java est disponible
ssh <worker> "java -version"

# Vérifier si le projet est accessible
ssh <worker> "ls ~/wordcount-distributed/bin"

# Vérifier les logs
ssh <worker> "cat /tmp/worker.log"
```

### Problème : Port 3000 déjà utilisé

```bash
# Voir qui utilise le port
ssh <worker> "netstat -tlnp | grep 3000"

# Tuer le processus
ssh <worker> "pkill -f WorkerNode"
```

### Problème : Timeout RMI

```bash
# Augmenter les timeouts dans le code ou vérifier le réseau
ping <worker>
```

---

## Exemple Complet : Session de Test

```bash
# 1. Connexion
ssh monlogin@access.grid5000.fr
ssh nantes

# 2. Préparation
cd ~/wordcount-distributed
git pull  # si nécessaire
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java")

# 3. Réservation
oarsub -I -l nodes=5,walltime=1:00:00

# 4. (Dans le job) Exécuter le test
export PROJECT_DIR=$HOME/wordcount-distributed
cd $PROJECT_DIR

# 5. Test rapide
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | sort -u)

for w in $WORKERS; do
    ssh $w "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $w 3000 > /tmp/worker.log 2>&1 &"
done
sleep 5

# Créer fichier test
seq 1 10000 | xargs -I {} echo "word{} test{}" > test.txt

# Lancer
WORKER_LIST=$(echo $WORKERS | tr ' ' '\n' | sed 's/$/:3000/' | tr '\n' ',' | sed 's/,$//')
java -cp bin scheduler.Main test.txt "[$WORKER_LIST]"

# 6. Vérifier le résultat
cat total.txt

# 7. Nettoyer
for w in $WORKERS; do ssh $w "pkill -f WorkerNode"; done

# 8. Quitter le job
exit
```

---

## Structure des Résultats

```
benchmarks/results/
├── rmi/
│   ├── rmi_summary_20241231_120000.csv      # Résumé par worker
│   └── rmi_ecotype-1_20241231_120000.csv    # Détail par worker
├── compute/
│   ├── wordcount_benchmark_20241231_120000.csv
│   └── wordcount_stats_20241231_120000.csv
├── transfer/
│   ├── scp_benchmark_20241231_120000.csv
│   ├── nfs_benchmark_20241231_120000.csv
│   └── transfer_params_20241231_120000.txt
├── init/
│   ├── init_benchmark_20241231_120000.csv
│   └── init_params_20241231_120000.txt
├── validation/
│   └── validation_20241231_120000.csv
└── plots/
    ├── validation_NFS_100MB.png
    ├── validation_SCP_100MB.png
    └── validation_summary.png
```
