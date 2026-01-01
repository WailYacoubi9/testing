#!/bin/bash
#=============================================================================
# MESURE T_calc(n, S) - Temps de calcul parallèle WordCount
#=============================================================================

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   MESURE T_calc - Temps de calcul parallèle                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmark_results"
TEST_DIR="$PROJECT_DIR/test_data"
mkdir -p "$RESULTS_DIR" "$TEST_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/t_calc_$TIMESTAMP.csv"

# Configuration - WORKER COUNTS EXACTS
WORKER_COUNTS=(2 3 6 8 11 13 15 18)
SIZES_MB=(10 50 100 500 1000)
RUNS=3

# Vérification OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Erreur: Lancez dans un job OAR"
    exit 1
fi

ALL_NODES=$(cat "$OAR_NODEFILE" | sort -u)
TOTAL=$(echo "$ALL_NODES" | wc -l)

echo "run,workers,size_mb,time_ms" > "$CSV_FILE"

# Compilation
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

# Générer fichiers de test
echo "Génération des fichiers de test..."
for size in "${SIZES_MB[@]}"; do
    if [ ! -f "$TEST_DIR/input_${size}mb.txt" ]; then
        # Générer du texte avec des mots (pas juste des zéros)
        yes "hello world this is a test file for wordcount benchmark " | head -c ${size}000000 > "$TEST_DIR/input_${size}mb.txt"
    fi
done

for n in "${WORKER_COUNTS[@]}"; do
    if [ $n -ge $TOTAL ]; then
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $n)
    echo ""
    echo "=== $n worker(s) ==="

    # Démarrer workers
    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
    done
    wait
    sleep 1

    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
            $h "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $h 3000 </dev/null > /tmp/worker.log 2>&1 &" \
            </dev/null 2>/dev/null &
    done
    wait
    sleep 3

    for size in "${SIZES_MB[@]}"; do
        INPUT="$TEST_DIR/input_${size}mb.txt"

        # Créer partitions
        split -n $n -d "$INPUT" "$TEST_DIR/calc_part_"

        for run in $(seq 1 $RUNS); do
            echo "  $n workers, $size MB, run $run"

            # Copier partitions vers workers
            i=0
            for h in $WORKERS; do
                PART="$TEST_DIR/calc_part_$(printf '%02d' $i)"
                if [ -f "$PART" ]; then
                    scp -o StrictHostKeyChecking=no "$PART" "$h:/tmp/input_part.txt" 2>/dev/null &
                fi
                i=$((i + 1))
            done
            wait

            # Mesurer le calcul parallèle
            START=$(date +%s%N)

            for h in $WORKERS; do
                ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
                    $h "cat /tmp/input_part.txt | tr ' ' '\n' | sort | uniq -c > /tmp/wordcount_result.txt" \
                    </dev/null 2>/dev/null &
            done
            wait

            END=$(date +%s%N)
            DURATION_MS=$(echo "scale=3; ($END - $START) / 1000000" | bc)

            echo "    ${DURATION_MS} ms"
            echo "$run,$n,$size,$DURATION_MS" >> "$CSV_FILE"
        done

        rm -f "$TEST_DIR/calc_part_"*
    done

    # Arrêter workers
    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
    done
    wait
done

echo ""
echo "✅ Résultats: $CSV_FILE"

# Calcul de V_cpu et détection saturation
echo ""
echo "Analyse:"
awk -F',' 'NR>1 {
    n=$2; s=$3; t=$4/1000  # ms -> s
    throughput = s / t
    tp_per_worker = throughput / n
    printf "  n=%d, S=%dMB: %.2f MB/s total, %.2f MB/s/worker\n", n, s, throughput, tp_per_worker
}' "$CSV_FILE"

# Cleanup
rm -rf "$TEST_DIR"
