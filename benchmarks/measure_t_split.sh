#!/bin/bash
#=============================================================================
# MESURE T_split(S) = S / BW_write
# Mesure le temps de découpage du fichier
#=============================================================================

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   MESURE T_split - Temps de découpage fichier               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmark_results"
TEST_DIR="$PROJECT_DIR/test_data"
mkdir -p "$RESULTS_DIR" "$TEST_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/t_split_$TIMESTAMP.csv"

# Configuration
SIZES_MB=(10 50 100 500 1000)
RUNS=3
NUM_PARTITIONS=8

echo "run,size_mb,time_ms" > "$CSV_FILE"

for size in "${SIZES_MB[@]}"; do
    echo ""
    echo "=== Fichier $size MB ==="

    # Générer fichier de test
    echo "  Génération..."
    dd if=/dev/zero bs=1M count=$size 2>/dev/null | tr '\0' 'A' > "$TEST_DIR/input_${size}mb.txt"

    for run in $(seq 1 $RUNS); do
        # Mesurer le split
        START=$(date +%s%N)

        # Utiliser le FileSplitter Java si disponible, sinon split
        if [ -f "$PROJECT_DIR/bin/utils/FileSplitter.class" ]; then
            java -cp "$PROJECT_DIR/bin" utils.FileSplitter "$TEST_DIR/input_${size}mb.txt" $NUM_PARTITIONS "$TEST_DIR" 2>/dev/null
        else
            split -n $NUM_PARTITIONS -d "$TEST_DIR/input_${size}mb.txt" "$TEST_DIR/part_"
        fi

        END=$(date +%s%N)
        DURATION_MS=$(echo "scale=3; ($END - $START) / 1000000" | bc)

        echo "  Run $run: ${DURATION_MS} ms"
        echo "$run,$size,$DURATION_MS" >> "$CSV_FILE"

        # Cleanup partitions
        rm -f "$TEST_DIR/part_"*
    done

    # Garder le fichier pour les prochains tests
done

echo ""
echo "✅ Résultats: $CSV_FILE"

# Calcul de BW_write
echo ""
echo "Bande passante d'écriture:"
awk -F',' 'NR>1 {
    s=$2; t=$3/1000  # ms -> s
    bw = s / t
    sum_bw += bw
    count++
}
END {
    avg_bw = sum_bw / count
    printf "  BW_write = %.2f MB/s\n", avg_bw
    printf "  T_split(S) = S / %.2f\n", avg_bw
}' "$CSV_FILE"

# Cleanup
rm -rf "$TEST_DIR"
