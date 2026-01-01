#!/bin/bash
#=============================================================================
# BENCHMARK COMPLET - Mesure toutes les composantes du modèle théorique
# T_total = T_init + T_split + T_calc + T_merge
#=============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   BENCHMARK COMPLET - MODÈLE THÉORIQUE WORDCOUNT            ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Configuration
PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmark_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$RESULTS_DIR"

# Paramètres de test - CONFIGURATION EXACTE
WORKER_COUNTS=(2 3 6 8 11 13 15 18)
FILE_SIZES_MB=(10 50 100 500 1000)
RUNS=3

# Vérification OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Erreur: Ce script doit être lancé dans un job OAR"
    echo "   oarsub -I -l nodes=17,walltime=2:00:00"
    exit 1
fi

ALL_NODES=$(cat "$OAR_NODEFILE" | sort -u)
TOTAL_NODES=$(echo "$ALL_NODES" | wc -l)
MASTER=$(echo "$ALL_NODES" | head -1)

echo ""
echo "Configuration:"
echo "  Master: $MASTER"
echo "  Noeuds disponibles: $TOTAL_NODES"
echo "  Workers à tester: ${WORKER_COUNTS[*]}"
echo "  Tailles fichiers: ${FILE_SIZES_MB[*]} MB"
echo "  Répétitions: $RUNS"
echo ""

# Fichiers de résultats
INIT_CSV="$RESULTS_DIR/t_init_$TIMESTAMP.csv"
SPLIT_CSV="$RESULTS_DIR/t_split_$TIMESTAMP.csv"
CALC_CSV="$RESULTS_DIR/t_calc_$TIMESTAMP.csv"
MERGE_CSV="$RESULTS_DIR/t_merge_$TIMESTAMP.csv"
TOTAL_CSV="$RESULTS_DIR/t_total_$TIMESTAMP.csv"

# Headers CSV
echo "run,workers,time_ms" > "$INIT_CSV"
echo "run,size_mb,time_ms" > "$SPLIT_CSV"
echo "run,workers,size_mb,time_ms" > "$CALC_CSV"
echo "run,workers,time_ms" > "$MERGE_CSV"
echo "run,workers,size_mb,t_init,t_split,t_calc,t_merge,t_total" > "$TOTAL_CSV"

# Compilation
echo "[0/4] Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

#=============================================================================
# 1. MESURE T_init(n) - Temps d'initialisation
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[1/4] MESURE T_init(n) = α × n + β"
echo "═══════════════════════════════════════════════════════════════"

for num_workers in "${WORKER_COUNTS[@]}"; do
    if [ $num_workers -ge $TOTAL_NODES ]; then
        echo "  Skip $num_workers workers (pas assez de noeuds)"
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    for run in $(seq 1 $RUNS); do
        echo "  T_init: $num_workers workers, run $run/$RUNS"

        # Cleanup
        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
        done
        wait
        sleep 1

        # Start workers
        START_TIME=$(date +%s%N)

        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h \
                "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $h 3000 > /tmp/worker.log 2>&1 &" \
                </dev/null 2>/dev/null &
        done
        wait

        # Wait for ports
        sleep 3

        # RMI lookup
        WORKER_ARGS=""
        for h in $WORKERS; do
            WORKER_ARGS="$WORKER_ARGS $h:3000"
        done

        java -cp bin benchmark.LauncherBenchmark $WORKER_ARGS 2>/dev/null | grep "^RESULT:" > /tmp/rmi_result.txt || true

        END_TIME=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

        echo "$run,$num_workers,$DURATION_MS" >> "$INIT_CSV"

        # Cleanup
        for h in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
        done
        wait
        sleep 1
    done
done

echo "  ✓ T_init sauvegardé: $INIT_CSV"

#=============================================================================
# 2. MESURE T_split(S) - Temps de découpage
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[2/4] MESURE T_split(S) = S / BW_write"
echo "═══════════════════════════════════════════════════════════════"

# Créer répertoire de test
TEST_DIR="$PROJECT_DIR/benchmark_data"
mkdir -p "$TEST_DIR"

for size_mb in "${FILE_SIZES_MB[@]}"; do
    # Générer fichier de test
    echo "  Génération fichier $size_mb MB..."
    dd if=/dev/urandom bs=1M count=$size_mb 2>/dev/null | base64 | head -c ${size_mb}000000 > "$TEST_DIR/input_${size_mb}mb.txt"

    for run in $(seq 1 $RUNS); do
        echo "  T_split: $size_mb MB, run $run/$RUNS"

        START_TIME=$(date +%s%N)

        # Simuler split en 8 partitions
        split -n 8 -d "$TEST_DIR/input_${size_mb}mb.txt" "$TEST_DIR/part_"

        END_TIME=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

        echo "$run,$size_mb,$DURATION_MS" >> "$SPLIT_CSV"

        # Cleanup partitions
        rm -f "$TEST_DIR/part_"*
    done

    # Garder le fichier pour T_calc
done

echo "  ✓ T_split sauvegardé: $SPLIT_CSV"

#=============================================================================
# 3. MESURE T_calc(n, S) - Temps de calcul parallèle
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[3/4] MESURE T_calc(n, S)"
echo "═══════════════════════════════════════════════════════════════"

for num_workers in "${WORKER_COUNTS[@]}"; do
    if [ $num_workers -ge $TOTAL_NODES ]; then
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    # Démarrer workers une fois
    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null || true
    done
    sleep 1

    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h \
            "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $h 3000 > /tmp/worker.log 2>&1 &" \
            </dev/null 2>/dev/null &
    done
    wait
    sleep 3

    for size_mb in "${FILE_SIZES_MB[@]}"; do
        INPUT_FILE="$TEST_DIR/input_${size_mb}mb.txt"

        if [ ! -f "$INPUT_FILE" ]; then
            echo "  Skip $size_mb MB (fichier non trouvé)"
            continue
        fi

        for run in $(seq 1 $RUNS); do
            echo "  T_calc: $num_workers workers, $size_mb MB, run $run/$RUNS"

            # Split file
            split -n $num_workers -d "$INPUT_FILE" "$TEST_DIR/calc_part_"

            START_TIME=$(date +%s%N)

            # Lancer wordcount sur chaque worker
            i=0
            for h in $WORKERS; do
                PART_FILE="$TEST_DIR/calc_part_$(printf '%02d' $i)"
                if [ -f "$PART_FILE" ]; then
                    # Copier partition vers worker et exécuter wordcount
                    scp -o StrictHostKeyChecking=no "$PART_FILE" "$h:/tmp/part.txt" 2>/dev/null
                    ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h \
                        "wc -w /tmp/part.txt > /tmp/result.txt" </dev/null 2>/dev/null &
                fi
                i=$((i + 1))
            done
            wait

            END_TIME=$(date +%s%N)
            DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

            echo "$run,$num_workers,$size_mb,$DURATION_MS" >> "$CALC_CSV"

            # Cleanup
            rm -f "$TEST_DIR/calc_part_"*
        done
    done

    # Arrêter workers
    for h in $WORKERS; do
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes $h "pkill -f WorkerNode" </dev/null 2>/dev/null &
    done
    wait
done

echo "  ✓ T_calc sauvegardé: $CALC_CSV"

#=============================================================================
# 4. MESURE T_merge(n) - Temps de fusion
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[4/4] MESURE T_merge(n)"
echo "═══════════════════════════════════════════════════════════════"

for num_workers in "${WORKER_COUNTS[@]}"; do
    # Créer fichiers de résultats simulés
    for i in $(seq 1 $num_workers); do
        echo "100 word$i" > "$TEST_DIR/count_$i.txt"
        for j in $(seq 1 1000); do
            echo "$j word_$j" >> "$TEST_DIR/count_$i.txt"
        done
    done

    for run in $(seq 1 $RUNS); do
        echo "  T_merge: $num_workers workers, run $run/$RUNS"

        START_TIME=$(date +%s%N)

        # Merge comme dans le vrai wordcount
        cat "$TEST_DIR"/count_*.txt | \
            awk '{counts[$2]+=$1} END {for(w in counts) print counts[w], w}' | \
            sort -rn > "$TEST_DIR/final_result.txt"

        END_TIME=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

        echo "$run,$num_workers,$DURATION_MS" >> "$MERGE_CSV"
    done

    # Cleanup
    rm -f "$TEST_DIR"/count_*.txt "$TEST_DIR/final_result.txt"
done

echo "  ✓ T_merge sauvegardé: $MERGE_CSV"

#=============================================================================
# CLEANUP
#=============================================================================
rm -rf "$TEST_DIR"

#=============================================================================
# RÉSUMÉ
#=============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   BENCHMARK TERMINÉ                                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Fichiers générés:"
echo "  - T_init:  $INIT_CSV"
echo "  - T_split: $SPLIT_CSV"
echo "  - T_calc:  $CALC_CSV"
echo "  - T_merge: $MERGE_CSV"
echo ""
echo "Pour analyser et tracer les graphiques:"
echo "  python3 benchmarks/analyze_model.py $RESULTS_DIR"
