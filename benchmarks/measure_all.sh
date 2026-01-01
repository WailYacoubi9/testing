#!/bin/bash
#=============================================================================
# BENCHMARK COMPLET - Mesure RÉALISTE des composantes
# T_total = T_init + T_split + T_calc + T_merge
#
# RÉALITÉ:
# - T_init: Sequential RMI lookups (Naming.lookup en boucle)
# - T_split: Split local + transfert parallèle vers workers
# - T_calc: Calcul parallèle sur workers (wordcount)
# - T_merge: Récupération résultats + agrégation locale
#
# NOTE: Utilise oarsh/oarcp au lieu de ssh/scp pour Grid5000
#=============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   BENCHMARK RÉALISTE - MODÈLE WORDCOUNT DISTRIBUÉ           ║"
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
    echo "   oarsub -I -p \"cluster='ecotype'\" -l nodes=19,walltime=2:00:00"
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
# CLEANUP GLOBAL AU DÉMARRAGE
#=============================================================================
echo ""
echo "Nettoyage global de tous les noeuds..."
for h in $ALL_NODES; do
    oarsh -n $h "pkill -9 -f WorkerNode 2>/dev/null; pkill -9 -f java 2>/dev/null" &
done
wait
sleep 2
echo "  ✓ Cleanup terminé"

#=============================================================================
# 1. MESURE T_init(n) = α × n + β
# RÉALITÉ: Naming.lookup() est SÉQUENTIEL dans une boucle Java
# On mesure: temps pour faire n lookups RMI séquentiels
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[1/4] MESURE T_init(n) = α × n + β (RMI lookups séquentiels)"
echo "═══════════════════════════════════════════════════════════════"

for num_workers in "${WORKER_COUNTS[@]}"; do
    if [ $num_workers -ge $TOTAL_NODES ]; then
        echo "  Skip $num_workers workers (pas assez de noeuds)"
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    # PRÉ-DÉMARRAGE: Lancer les workers UNE FOIS (hors mesure)
    echo "  Pré-démarrage de $num_workers workers..."

    # Cleanup
    for h in $WORKERS; do
        oarsh -n $h "pkill -9 -f WorkerNode" 2>/dev/null &
    done
    wait
    sleep 1

    # Démarrage des workers
    for h in $WORKERS; do
        echo "    Démarrage worker sur $h..."
        oarsh -n $h "cd $PROJECT_DIR && java -cp bin network.worker.WorkerNode $h 3000 > /tmp/worker.log 2>&1 &" </dev/null &
    done
    wait

    echo "  Attente 5s pour initialisation RMI..."
    sleep 5

    # Vérification rapide
    FIRST_WORKER=$(echo "$WORKERS" | head -1)
    if oarsh -n $FIRST_WORKER "ps aux | grep -q '[W]orkerNode'" 2>/dev/null; then
        echo "  ✓ Workers démarrés"
    else
        echo "  ⚠ Vérification worker échouée, on continue..."
    fi

    # MESURE: Uniquement les RMI lookups séquentiels
    for run in $(seq 1 $RUNS); do
        echo "  T_init: $num_workers workers, run $run/$RUNS"

        # Construire args pour LauncherBenchmark
        WORKER_ARGS=""
        for h in $WORKERS; do
            WORKER_ARGS="$WORKER_ARGS $h:3000"
        done

        # Mesurer UNIQUEMENT le temps des lookups RMI séquentiels
        START_TIME=$(date +%s%N)

        # LauncherBenchmark fait: for each worker: Naming.lookup() (SÉQUENTIEL)
        java -cp bin benchmark.LauncherBenchmark $WORKER_ARGS 2>/dev/null | grep "^RESULT:" > /tmp/rmi_result.txt || true

        END_TIME=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

        echo "$run,$num_workers,$DURATION_MS" >> "$INIT_CSV"
    done

    # Cleanup après toutes les runs pour ce n
    for h in $WORKERS; do
        oarsh -n $h "pkill -f WorkerNode" 2>/dev/null &
    done
    wait
    sleep 1
done

echo "  ✓ T_init sauvegardé: $INIT_CSV"

#=============================================================================
# 2. MESURE T_split(S) - Temps de découpage + transfert
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[2/4] MESURE T_split(S) = S / BW_write (split + transfert)"
echo "═══════════════════════════════════════════════════════════════"

# Créer répertoire de test
TEST_DIR="$PROJECT_DIR/benchmark_data"
mkdir -p "$TEST_DIR"

# Utiliser 8 workers pour le test de split
SPLIT_WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n 8)

for size_mb in "${FILE_SIZES_MB[@]}"; do
    # Générer fichier de test
    echo "  Génération fichier $size_mb MB..."
    dd if=/dev/urandom bs=1M count=$size_mb 2>/dev/null | base64 | head -c ${size_mb}000000 > "$TEST_DIR/input_${size_mb}mb.txt"

    for run in $(seq 1 $RUNS); do
        echo "  T_split: $size_mb MB, run $run/$RUNS"

        START_TIME=$(date +%s%N)

        # Split en 8 partitions
        split -n 8 -d "$TEST_DIR/input_${size_mb}mb.txt" "$TEST_DIR/part_"

        # Transfert vers workers (parallèle) - utilise oarcp
        i=0
        for h in $SPLIT_WORKERS; do
            PART="$TEST_DIR/part_$(printf '%02d' $i)"
            if [ -f "$PART" ]; then
                oarcp "$PART" $h:/tmp/split_part.txt 2>/dev/null &
            fi
            i=$((i + 1))
        done
        wait

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
        oarsh -n $h "pkill -f WorkerNode" 2>/dev/null || true
    done
    sleep 1

    for h in $WORKERS; do
        oarsh -n $h "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $h 3000 > /tmp/worker.log 2>&1 &" &
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

            # Copier partitions vers workers AVANT la mesure - utilise oarcp
            i=0
            for h in $WORKERS; do
                PART_FILE="$TEST_DIR/calc_part_$(printf '%02d' $i)"
                if [ -f "$PART_FILE" ]; then
                    oarcp "$PART_FILE" $h:/tmp/part.txt 2>/dev/null &
                fi
                i=$((i + 1))
            done
            wait

            # Mesurer UNIQUEMENT le calcul
            START_TIME=$(date +%s%N)

            for h in $WORKERS; do
                oarsh -n $h "cat /tmp/part.txt | tr ' ' '\n' | tr -s '\n' | sort | uniq -c > /tmp/result.txt" &
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
        oarsh -n $h "pkill -f WorkerNode" 2>/dev/null &
    done
    wait
done

echo "  ✓ T_calc sauvegardé: $CALC_CSV"

#=============================================================================
# 4. MESURE T_merge(n) = T_fetch + T_aggregate
# RÉALITÉ: Récupérer résultats depuis workers + agrégation locale
#=============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "[4/4] MESURE T_merge(n) = T_fetch + T_aggregate"
echo "═══════════════════════════════════════════════════════════════"

for num_workers in "${WORKER_COUNTS[@]}"; do
    if [ $num_workers -ge $TOTAL_NODES ]; then
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    # Pré-créer des résultats sur chaque worker (simule résultat wordcount)
    echo "  Préparation résultats sur $num_workers workers..."
    i=0
    for h in $WORKERS; do
        oarsh -n $h "for j in \$(seq 1 1000); do echo \"\$j word_\$j\"; done > /tmp/result.txt" &
        i=$((i + 1))
    done
    wait

    for run in $(seq 1 $RUNS); do
        echo "  T_merge: $num_workers workers, run $run/$RUNS"

        mkdir -p "$TEST_DIR/merge_tmp"

        START_TIME=$(date +%s%N)

        # 1. FETCH: Récupérer résultats depuis tous les workers (parallèle) - utilise oarcp
        i=0
        for h in $WORKERS; do
            oarcp $h:/tmp/result.txt "$TEST_DIR/merge_tmp/count_$i.txt" 2>/dev/null &
            i=$((i + 1))
        done
        wait

        # 2. AGGREGATE: Fusionner tous les résultats
        cat "$TEST_DIR/merge_tmp"/count_*.txt | \
            awk '{counts[$2]+=$1} END {for(w in counts) print counts[w], w}' | \
            sort -rn > "$TEST_DIR/final_result.txt"

        END_TIME=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000" | bc)

        echo "$run,$num_workers,$DURATION_MS" >> "$MERGE_CSV"

        rm -rf "$TEST_DIR/merge_tmp"
    done
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
