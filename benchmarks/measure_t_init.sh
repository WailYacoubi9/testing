#!/bin/bash
#=============================================================================
# MESURE T_init(n) = α × n + β
# Script optimisé pour Grid5000 avec oarsh
#=============================================================================

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   MESURE T_init - Temps d'initialisation du cluster         ║"
echo "╚══════════════════════════════════════════════════════════════╝"

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmark_results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/t_init_$TIMESTAMP.csv"

# Configuration
WORKER_COUNTS=(1 2 4 8 16)
RUNS=5

# Vérification OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Erreur: Lancez dans un job OAR"
    exit 1
fi

ALL_NODES=$(cat "$OAR_NODEFILE" | sort -u)
TOTAL=$(echo "$ALL_NODES" | wc -l)
echo "Noeuds disponibles: $TOTAL"

# Header CSV
echo "run,workers,time_ms" > "$CSV_FILE"

# Compilation
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

for n in "${WORKER_COUNTS[@]}"; do
    if [ $n -ge $TOTAL ]; then
        echo "Skip $n workers (pas assez de noeuds)"
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $n)
    echo ""
    echo "=== $n worker(s) ==="

    for run in $(seq 1 $RUNS); do
        # Cleanup parallèle
        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 \
                $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
        done
        wait
        sleep 1

        # Démarrage workers parallèle + mesure
        START=$(date +%s%N)

        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 \
                $h "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $h 3000 </dev/null > /tmp/worker.log 2>&1 &" \
                </dev/null 2>/dev/null &
        done
        wait

        # Attendre que les ports soient prêts
        sleep 3

        # Test RMI
        ARGS=""
        for h in $WORKERS; do
            ARGS="$ARGS $h:3000"
        done
        java -cp bin benchmark.LauncherBenchmark $ARGS 2>/dev/null | grep "^RESULT:" > /dev/null || true

        END=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END - $START) / 1000000" | bc)

        echo "  Run $run: ${DURATION_MS} ms"
        echo "$run,$n,$DURATION_MS" >> "$CSV_FILE"

        # Cleanup
        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
        done
        wait
        sleep 1
    done
done

echo ""
echo "✅ Résultats: $CSV_FILE"

# Calcul rapide de alpha et beta
echo ""
echo "Régression linéaire:"
awk -F',' 'NR>1 {
    n=$2; t=$3/1000  # ms -> s
    sum_n+=n; sum_t+=t; sum_nt+=n*t; sum_nn+=n*n; count++
}
END {
    alpha = (count*sum_nt - sum_n*sum_t) / (count*sum_nn - sum_n*sum_n)
    beta = (sum_t - alpha*sum_n) / count
    printf "  T_init(n) = %.4f × n + %.4f\n", alpha, beta
    printf "  α = %.4f s/worker\n", alpha
    printf "  β = %.4f s\n", beta
}' "$CSV_FILE"
