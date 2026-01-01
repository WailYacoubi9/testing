#!/bin/bash
#=============================================================================
# BENCHMARK LATENCE RMI
# Mesure les parametres L_rmi et o_rmi du modele LogP
#
# Reference: Culler et al. (1993) "LogP: A Practical Model of Parallel Computation"
#=============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmarks/results/rmi"
mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo "         BENCHMARK LATENCE RMI - Modele LogP                    "
echo "================================================================"

# Verifier l'environnement Grid5000
if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Ce script doit etre execute dans une reservation OAR"
    echo "   Utilisez: oarsub -I -l nodes=4,walltime=1:00:00"
    exit 1
fi

# Obtenir les noeuds
MASTER_NODE=$(head -n 1 $OAR_NODEFILE)
WORKER_NODES=$(tail -n +2 $OAR_NODEFILE | sort -u)
NUM_WORKERS=$(echo "$WORKER_NODES" | wc -l)

echo ""
echo "Configuration:"
echo "  Master: $MASTER_NODE"
echo "  Workers: $NUM_WORKERS"
echo "  Resultats: $RESULTS_DIR"
echo ""

# Compiler si necessaire
echo "[1/4] Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || {
    echo "Compilation..."
    javac -d bin -sourcepath src $(find src -name "*.java")
}

# Demarrer les workers
echo "[2/4] Demarrage des workers..."
for worker in $WORKER_NODES; do
    echo "  -> Demarrage sur $worker..."
    oarsh -n $worker "pkill -f WorkerNode 2>/dev/null || true"
    oarsh -n $worker "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $worker 3000 > /tmp/worker.log 2>&1 &"
done

# Attendre que les workers soient prets
echo "[3/4] Attente des workers..."
sleep 5
for worker in $WORKER_NODES; do
    timeout=30
    while ! ssh $worker "netstat -ln 2>/dev/null | grep -q :3000"; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "  ERREUR: Timeout $worker non pret"
            exit 1
        fi
    done
    echo "  OK: $worker pret"
done

# Executer les benchmarks
echo "[4/4] Execution des benchmarks..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_FILE="$RESULTS_DIR/rmi_summary_$TIMESTAMP.csv"

echo "worker,L_rmi_mean_ms,L_rmi_std_ms,o_rmi_mean_ms,o_rmi_std_ms,total_mean_ms" > "$SUMMARY_FILE"

for worker in $WORKER_NODES; do
    echo ""
    echo "--- Benchmark: $worker ---"

    OUTPUT_FILE="$RESULTS_DIR/rmi_${worker}_${TIMESTAMP}.csv"

    java -cp bin benchmark.RMILatencyBenchmark "$worker:3000" "$OUTPUT_FILE"

    # Extraire les stats pour le resume
    L_RMI=$(grep "L_rmi_mean_ms" "$OUTPUT_FILE" | cut -d',' -f2)
    L_STD=$(grep "L_rmi_std_ms" "$OUTPUT_FILE" | cut -d',' -f2)
    O_RMI=$(grep "o_rmi_mean_ms" "$OUTPUT_FILE" | cut -d',' -f2)
    O_STD=$(grep "o_rmi_std_ms" "$OUTPUT_FILE" | cut -d',' -f2)
    TOTAL=$(echo "$L_RMI + $O_RMI" | bc)

    echo "$worker,$L_RMI,$L_STD,$O_RMI,$O_STD,$TOTAL" >> "$SUMMARY_FILE"
done

# Nettoyer
echo ""
echo "[Nettoyage] Arret des workers..."
for worker in $WORKER_NODES; do
    oarsh -n $worker "pkill -f WorkerNode 2>/dev/null || true"
done

# Afficher le resume
echo ""
echo "================================================================"
echo "                    RESUME                                       "
echo "================================================================"
echo ""
cat "$SUMMARY_FILE" | column -t -s','
echo ""
echo "Fichiers generes:"
echo "  Resume: $SUMMARY_FILE"
ls -la "$RESULTS_DIR"/rmi_*_${TIMESTAMP}.csv
