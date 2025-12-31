#!/bin/bash
#=============================================================================
# BENCHMARK WORDCOUNT
# Mesure V_wc = vitesse de calcul (lignes/seconde)
#
# Ce script mesure le temps d'execution du binaire wordcount
# pour calibrer le parametre V_wc du modele theorique.
#=============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmarks/results/compute"
TEST_DIR="$PROJECT_DIR/benchmarks/test_data"
mkdir -p "$RESULTS_DIR" "$TEST_DIR"

echo "================================================================"
echo "         BENCHMARK WORDCOUNT - Temps de Calcul                  "
echo "================================================================"

# Compiler wordcount
echo "[1/4] Compilation de wordcount..."
cd "$PROJECT_DIR"
if [ -f test/wordcount.c ]; then
    gcc -O2 -o wordcount test/wordcount.c
    echo "  Compile: test/wordcount.c -> wordcount"
elif [ -f src/wordcount.c ]; then
    gcc -O2 -o wordcount src/wordcount.c
    echo "  Compile: src/wordcount.c -> wordcount"
else
    echo "  ERREUR: wordcount.c non trouve"
    exit 1
fi

# Generer les fichiers de test
echo "[2/4] Generation des fichiers de test..."

SIZES=(1000 5000 10000 50000 100000 500000 1000000 5000000)

for size in "${SIZES[@]}"; do
    FILE="$TEST_DIR/test_${size}.txt"
    if [ ! -f "$FILE" ]; then
        echo "  Generation: $size lignes..."
        seq 1 $size | while read i; do
            echo "word$i word$((i*2)) word$((i*3))"
        done > "$FILE"
    fi
done

# Executer les benchmarks
echo "[3/4] Execution des benchmarks..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$RESULTS_DIR/wordcount_benchmark_$TIMESTAMP.csv"

echo "lines,file_size_bytes,run,time_seconds,lines_per_second,words_per_second" > "$OUTPUT_FILE"

RUNS=30  # 30 repetitions pour significativite statistique

for size in "${SIZES[@]}"; do
    FILE="$TEST_DIR/test_${size}.txt"
    FILE_SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE")

    echo ""
    echo "--- Test: $size lignes ($FILE_SIZE bytes) ---"

    for run in $(seq 1 $RUNS); do
        # Vider le cache (si root)
        sync 2>/dev/null || true
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

        # Mesurer le temps
        START=$(date +%s.%N)
        ./wordcount "$FILE" > /dev/null
        END=$(date +%s.%N)

        TIME=$(echo "$END - $START" | bc)
        LINES_PER_SEC=$(echo "scale=2; $size / $TIME" | bc)
        WORDS_PER_SEC=$(echo "scale=2; ($size * 3) / $TIME" | bc)

        echo "$size,$FILE_SIZE,$run,$TIME,$LINES_PER_SEC,$WORDS_PER_SEC" >> "$OUTPUT_FILE"

        # Afficher progression
        if [ $((run % 10)) -eq 0 ]; then
            echo "  Run $run/$RUNS: ${TIME}s (${LINES_PER_SEC} lines/s)"
        fi
    done
done

# Calculer les statistiques
echo ""
echo "[4/4] Calcul des statistiques..."

STATS_FILE="$RESULTS_DIR/wordcount_stats_$TIMESTAMP.csv"
echo "lines,mean_time_s,std_time_s,mean_lines_per_s,std_lines_per_s" > "$STATS_FILE"

for size in "${SIZES[@]}"; do
    # Extraire les donnees pour cette taille
    DATA=$(grep "^$size," "$OUTPUT_FILE" | cut -d',' -f4)

    # Calculer avec awk
    STATS=$(echo "$DATA" | awk -v size=$size '
    {
        sum += $1
        sumsq += $1 * $1
        count++
    }
    END {
        mean = sum / count
        variance = (sumsq - sum*sum/count) / (count - 1)
        stddev = sqrt(variance)
        lines_per_s = size / mean
        lines_std = size * stddev / (mean * mean)
        printf "%.6f,%.6f,%.2f,%.2f", mean, stddev, lines_per_s, lines_std
    }')

    echo "$size,$STATS" >> "$STATS_FILE"
done

# Afficher les resultats
echo ""
echo "================================================================"
echo "                 RESULTATS V_wc                                 "
echo "================================================================"
echo ""
cat "$STATS_FILE" | column -t -s','

# Calculer V_wc moyen (pour grands fichiers)
V_WC=$(tail -3 "$STATS_FILE" | awk -F',' '{sum += $4; count++} END {printf "%.0f", sum/count}')
echo ""
echo "----------------------------------------------------------------"
echo "VALEUR POUR LE MODELE:"
echo "  V_wc = $V_WC lignes/seconde"
echo "----------------------------------------------------------------"
echo ""
echo "Fichiers generes:"
echo "  Donnees brutes: $OUTPUT_FILE"
echo "  Statistiques: $STATS_FILE"
