#!/bin/bash
#=============================================================================
# VALIDATION DU MODELE THEORIQUE
# Compare les predictions du modele avec les mesures reelles
#
# Teste les configurations: 1, 2, 4, 8, 16, 32, 64 workers
# Avec differentes tailles de fichiers et modes (SCP/NFS)
#=============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmarks/results/validation"
TEST_DIR="$PROJECT_DIR/benchmarks/test_data"
mkdir -p "$RESULTS_DIR" "$TEST_DIR"

echo "================================================================"
echo "      VALIDATION DU MODELE - Comparaison Theorie/Reel           "
echo "================================================================"

if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Ce script doit etre execute dans une reservation OAR"
    echo "   Pour 64 coeurs: oarsub -I -l nodes=65,walltime=4:00:00"
    exit 1
fi

# Configuration
ALL_NODES=$(cat $OAR_NODEFILE | sort -u)
NUM_NODES=$(echo "$ALL_NODES" | wc -l)
MAX_WORKERS=$((NUM_NODES - 1))
RUNS=5
FILE_SIZES_MB=(10 50 100 500)

echo ""
echo "Configuration:"
echo "  Noeuds disponibles: $NUM_NODES"
echo "  Max workers: $MAX_WORKERS"
echo "  Repetitions par config: $RUNS"
echo "  Tailles testees: ${FILE_SIZES_MB[*]} MB"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/validation_$TIMESTAMP.csv"

echo "num_workers,file_size_mb,mode,run,measured_time_s" > "$OUTPUT_FILE"

# Compiler
echo ""
echo "[1/4] Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true
gcc -O2 -o wordcount test/wordcount.c 2>/dev/null || true

# Generer les fichiers de test
echo "[2/4] Generation des fichiers de test..."
for size_mb in "${FILE_SIZES_MB[@]}"; do
    FILE="$TEST_DIR/validation_${size_mb}MB.txt"
    if [ ! -f "$FILE" ]; then
        echo "  Generation: ${size_mb} MB..."
        LINES=$((size_mb * 10000))
        seq 1 $LINES | while read i; do
            echo "word$i word$((i*2)) word$((i*3)) word$((i*4)) word$((i*5))"
        done > "$FILE"
    fi
done

# Demarrer tous les workers
echo "[3/4] Demarrage des workers..."
MASTER=$(echo "$ALL_NODES" | head -n 1)
ALL_WORKERS=$(echo "$ALL_NODES" | tail -n +2)

for worker in $ALL_WORKERS; do
    ssh $worker "pkill -f WorkerNode 2>/dev/null || true"
    ssh $worker "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $worker 3000 > /tmp/worker.log 2>&1 &"
done
sleep 5

# Verifier que les workers sont prets
echo "  Verification..."
for worker in $ALL_WORKERS; do
    timeout=30
    while ! ssh $worker "netstat -ln 2>/dev/null | grep -q :3000"; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "  ERREUR: $worker non pret"
            exit 1
        fi
    done
done
echo "  Tous les workers sont prets."

# Executer les tests
echo "[4/4] Execution des tests de validation..."

# Configurations de workers a tester
WORKER_COUNTS=(1 2 4 8 16 32)
if [ $MAX_WORKERS -ge 64 ]; then
    WORKER_COUNTS+=(64)
fi

for num_workers in "${WORKER_COUNTS[@]}"; do
    if [ $num_workers -gt $MAX_WORKERS ]; then
        echo "  Skip $num_workers workers (max disponible: $MAX_WORKERS)"
        continue
    fi

    # Selectionner les workers
    WORKERS=$(echo "$ALL_WORKERS" | head -n $num_workers)
    WORKER_LIST=$(echo $WORKERS | tr ' ' '\n' | sed 's/$/:3000/' | tr '\n' ',' | sed 's/,$//')

    for size_mb in "${FILE_SIZES_MB[@]}"; do
        FILE="$TEST_DIR/validation_${size_mb}MB.txt"

        for mode in NFS SCP; do
            echo ""
            echo "--- Test: $num_workers workers, ${size_mb}MB, $mode ---"

            for run in $(seq 1 $RUNS); do
                echo "  Run $run/$RUNS..."

                # Nettoyer
                rm -f part*.txt count*.txt total.txt Makefile.generated 2>/dev/null || true

                # Executer
                START=$(date +%s.%N)

                if [ "$mode" = "NFS" ]; then
                    java -cp bin scheduler.MainNFS "$FILE" "[$WORKER_LIST]" > /dev/null 2>&1 || true
                else
                    java -cp bin scheduler.Main "$FILE" "[$WORKER_LIST]" > /dev/null 2>&1 || true
                fi

                END=$(date +%s.%N)
                TIME=$(echo "$END - $START" | bc)

                echo "$num_workers,$size_mb,$mode,$run,$TIME" >> "$OUTPUT_FILE"
                echo "    Temps: ${TIME}s"

                # Nettoyer
                rm -f part*.txt count*.txt total.txt Makefile.generated 2>/dev/null || true
            done
        done
    done
done

# Nettoyer les workers
echo ""
echo "[Nettoyage] Arret des workers..."
for worker in $ALL_WORKERS; do
    ssh $worker "pkill -f WorkerNode 2>/dev/null" || true
done

echo ""
echo "================================================================"
echo "                   VALIDATION TERMINEE                           "
echo "================================================================"
echo ""
echo "Resultats: $OUTPUT_FILE"
echo ""
echo "Pour generer les graphiques:"
echo "  python3 benchmarks/plot_validation.py $OUTPUT_FILE"
