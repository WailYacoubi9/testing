#!/bin/bash
#=============================================================================
# BENCHMARK INITIALISATION CLUSTER
# Mesure alpha (cout par worker) et beta (overhead fixe)
#
# Modele: T_init(n) = alpha * n + beta
#=============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmarks/results/init"
mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo "      BENCHMARK INITIALISATION - Parametres alpha, beta         "
echo "================================================================"

if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Ce script doit etre execute dans une reservation OAR"
    echo "   Utilisez: oarsub -I -l nodes=10,walltime=2:00:00"
    exit 1
fi

# Configuration
ALL_NODES=$(cat $OAR_NODEFILE | sort -u)
MAX_WORKERS=$(($(echo "$ALL_NODES" | wc -l) - 1))
RUNS=10

echo ""
echo "Configuration:"
echo "  Noeuds disponibles: $((MAX_WORKERS + 1))"
echo "  Max workers testes: $MAX_WORKERS"
echo "  Repetitions: $RUNS"

# Compiler
echo ""
echo "[1/3] Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/init_benchmark_$TIMESTAMP.csv"

echo "num_workers,run,ssh_time_s,jvm_time_s,rmi_ready_time_s,total_time_s" > "$OUTPUT_FILE"

echo "[2/3] Execution des tests..."

# Test pour differents nombres de workers
for num_workers in $(seq 1 $MAX_WORKERS); do
    echo ""
    echo "--- Test avec $num_workers worker(s) ---"

    # Selectionner les workers
    MASTER=$(echo "$ALL_NODES" | head -n 1)
    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    for run in $(seq 1 $RUNS); do
        echo "  Run $run/$RUNS..."

        # Nettoyer les workers precedents
        for worker in $WORKERS; do
            ssh $worker "pkill -f WorkerNode 2>/dev/null" || true
        done
        sleep 1

        # Mesure 1: Temps SSH pour lancer les commandes
        START_SSH=$(date +%s.%N)
        for worker in $WORKERS; do
            ssh $worker "echo ready" > /dev/null &
        done
        wait
        END_SSH=$(date +%s.%N)
        SSH_TIME=$(echo "$END_SSH - $START_SSH" | bc)

        # Mesure 2: Temps de demarrage JVM + Worker
        START_JVM=$(date +%s.%N)
        for worker in $WORKERS; do
            ssh $worker "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $worker 3000 > /tmp/worker.log 2>&1 &"
        done
        END_JVM=$(date +%s.%N)
        JVM_TIME=$(echo "$END_JVM - $START_JVM" | bc)

        # Mesure 3: Temps jusqu'a ce que RMI soit pret
        START_RMI=$(date +%s.%N)
        all_ready=false
        while [ "$all_ready" = false ]; do
            ready_count=0
            for worker in $WORKERS; do
                if ssh $worker "netstat -ln 2>/dev/null | grep -q :3000"; then
                    ready_count=$((ready_count + 1))
                fi
            done
            if [ $ready_count -eq $num_workers ]; then
                all_ready=true
            else
                sleep 0.1
            fi
        done
        END_RMI=$(date +%s.%N)
        RMI_TIME=$(echo "$END_RMI - $START_RMI" | bc)

        TOTAL_TIME=$(echo "$SSH_TIME + $JVM_TIME + $RMI_TIME" | bc)

        echo "$num_workers,$run,$SSH_TIME,$JVM_TIME,$RMI_TIME,$TOTAL_TIME" >> "$OUTPUT_FILE"

        # Nettoyer
        for worker in $WORKERS; do
            ssh $worker "pkill -f WorkerNode 2>/dev/null" || true
        done
    done
done

# Calculer alpha et beta par regression lineaire
echo ""
echo "[3/3] Calcul de la regression lineaire..."

STATS_FILE="$RESULTS_DIR/init_stats_$TIMESTAMP.csv"

# Calculer moyennes par nombre de workers
echo "num_workers,mean_total_s,std_total_s" > "$STATS_FILE"

for n in $(seq 1 $MAX_WORKERS); do
    STATS=$(grep "^$n," "$OUTPUT_FILE" | awk -F',' '
    {
        sum += $6
        sumsq += $6 * $6
        count++
    }
    END {
        mean = sum / count
        std = sqrt((sumsq - sum*sum/count) / (count - 1))
        printf "%.4f,%.4f", mean, std
    }')
    echo "$n,$STATS" >> "$STATS_FILE"
done

# Regression lineaire avec awk
REGRESSION=$(cat "$STATS_FILE" | tail -n +2 | awk -F',' '
{
    n = $1
    t = $2
    sum_n += n
    sum_t += t
    sum_nt += n * t
    sum_nn += n * n
    count++
}
END {
    alpha = (count * sum_nt - sum_n * sum_t) / (count * sum_nn - sum_n * sum_n)
    beta = (sum_t - alpha * sum_n) / count
    printf "%.4f,%.4f", alpha, beta
}')

ALPHA=$(echo $REGRESSION | cut -d',' -f1)
BETA=$(echo $REGRESSION | cut -d',' -f2)

echo ""
echo "================================================================"
echo "           PARAMETRES POUR LE MODELE                            "
echo "================================================================"
echo ""
echo "Regression: T_init(n) = alpha * n + beta"
echo ""
echo "  alpha = $ALPHA secondes/worker"
echo "  beta = $BETA secondes (overhead fixe)"
echo ""

# Sauvegarder les parametres
PARAMS_FILE="$RESULTS_DIR/init_params_$TIMESTAMP.txt"
cat > "$PARAMS_FILE" << EOF
# Parametres d'initialisation pour le modele theorique
# Date: $(date)
# Regression: T_init(n) = alpha * n + beta

alpha = $ALPHA
beta = $BETA
EOF

echo "Fichiers generes:"
echo "  Donnees: $OUTPUT_FILE"
echo "  Stats: $STATS_FILE"
echo "  Parametres: $PARAMS_FILE"
