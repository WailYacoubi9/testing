#!/bin/bash
#=============================================================================
# BENCHMARK TRANSFERT FICHIERS
# Mesure L_scp, BW_scp, L_nfs, BW_nfs
#
# Ces parametres sont utilises dans le modele LogP pour la communication.
#=============================================================================

set -e

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/benchmarks/results/transfer"
TEST_DIR="$PROJECT_DIR/benchmarks/test_data"
mkdir -p "$RESULTS_DIR" "$TEST_DIR"

echo "================================================================"
echo "       BENCHMARK TRANSFERT - Parametres Communication           "
echo "================================================================"

# Verifier l'environnement
if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Ce script doit etre execute dans une reservation OAR"
    exit 1
fi

# Configuration
MASTER_NODE=$(head -n 1 $OAR_NODEFILE)
TARGET_NODE=$(tail -n +2 $OAR_NODEFILE | head -n 1)
RUNS=30

echo ""
echo "Configuration:"
echo "  Source: $MASTER_NODE"
echo "  Destination: $TARGET_NODE"
echo "  Repetitions: $RUNS"

# Tailles de fichiers a tester (en KB)
SIZES_KB=(1 10 100 1024 10240 102400 512000)

# Generer les fichiers de test
echo ""
echo "[1/4] Generation des fichiers de test..."

for size_kb in "${SIZES_KB[@]}"; do
    FILE="$TEST_DIR/transfer_test_${size_kb}KB.bin"
    if [ ! -f "$FILE" ]; then
        echo "  Generation: ${size_kb} KB..."
        dd if=/dev/urandom of="$FILE" bs=1024 count=$size_kb 2>/dev/null
    fi
done

# Creer le repertoire distant
oarsh -n $TARGET_NODE "mkdir -p /tmp/transfer_benchmark"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Benchmark SCP
echo ""
echo "[2/4] Benchmark SCP..."

SCP_FILE="$RESULTS_DIR/scp_benchmark_$TIMESTAMP.csv"
echo "size_kb,size_bytes,run,time_seconds,bandwidth_mbps" > "$SCP_FILE"

for size_kb in "${SIZES_KB[@]}"; do
    FILE="$TEST_DIR/transfer_test_${size_kb}KB.bin"
    SIZE_BYTES=$((size_kb * 1024))

    echo "  Test SCP: ${size_kb} KB..."

    for run in $(seq 1 $RUNS); do
        # Nettoyer la destination
        oarsh -n $TARGET_NODE "rm -f /tmp/transfer_benchmark/test.bin" 2>/dev/null

        # Mesurer le transfert
        START=$(date +%s.%N)
        oarcp -q "$FILE" "$TARGET_NODE:/tmp/transfer_benchmark/test.bin"
        END=$(date +%s.%N)

        TIME=$(echo "$END - $START" | bc)
        BW_MBPS=$(echo "scale=2; $SIZE_BYTES / $TIME / 1048576" | bc)

        echo "$size_kb,$SIZE_BYTES,$run,$TIME,$BW_MBPS" >> "$SCP_FILE"
    done
done

# Benchmark NFS
echo ""
echo "[3/4] Benchmark NFS..."

NFS_DIR="$HOME/nfs_benchmark_test"
mkdir -p "$NFS_DIR"

NFS_FILE="$RESULTS_DIR/nfs_benchmark_$TIMESTAMP.csv"
echo "size_kb,size_bytes,run,time_seconds,bandwidth_mbps" > "$NFS_FILE"

for size_kb in "${SIZES_KB[@]}"; do
    FILE="$TEST_DIR/transfer_test_${size_kb}KB.bin"
    SIZE_BYTES=$((size_kb * 1024))

    echo "  Test NFS: ${size_kb} KB..."

    for run in $(seq 1 $RUNS); do
        # Copier vers NFS
        cp "$FILE" "$NFS_DIR/test.bin"
        sync

        # Mesurer l'acces depuis le worker
        START=$(date +%s.%N)
        oarsh -n $TARGET_NODE "cat $NFS_DIR/test.bin > /dev/null"
        END=$(date +%s.%N)

        TIME=$(echo "$END - $START" | bc)
        BW_MBPS=$(echo "scale=2; $SIZE_BYTES / $TIME / 1048576" | bc)

        echo "$size_kb,$SIZE_BYTES,$run,$TIME,$BW_MBPS" >> "$NFS_FILE"

        rm -f "$NFS_DIR/test.bin"
    done
done

# Calculer les statistiques
echo ""
echo "[4/4] Calcul des statistiques..."

calculate_stats() {
    local input_file=$1
    local output_file=$2

    echo "size_kb,mean_time_s,std_time_s,mean_bw_mbps,std_bw_mbps,latency_ms" > "$output_file"

    for size_kb in "${SIZES_KB[@]}"; do
        STATS=$(grep "^$size_kb," "$input_file" | awk -F',' '
        {
            sum_time += $4
            sumsq_time += $4 * $4
            sum_bw += $5
            sumsq_bw += $5 * $5
            count++
        }
        END {
            mean_time = sum_time / count
            std_time = sqrt((sumsq_time - sum_time*sum_time/count) / (count - 1))
            mean_bw = sum_bw / count
            std_bw = sqrt((sumsq_bw - sum_bw*sum_bw/count) / (count - 1))
            latency = mean_time * 1000
            printf "%.6f,%.6f,%.2f,%.2f,%.3f", mean_time, std_time, mean_bw, std_bw, latency
        }')

        echo "$size_kb,$STATS" >> "$output_file"
    done
}

SCP_STATS="$RESULTS_DIR/scp_stats_$TIMESTAMP.csv"
NFS_STATS="$RESULTS_DIR/nfs_stats_$TIMESTAMP.csv"

calculate_stats "$SCP_FILE" "$SCP_STATS"
calculate_stats "$NFS_FILE" "$NFS_STATS"

# Extraire les parametres du modele
L_SCP=$(grep "^1," "$SCP_STATS" | cut -d',' -f6)
BW_SCP=$(tail -3 "$SCP_STATS" | awk -F',' '{sum += $4; count++} END {printf "%.2f", sum/count}')
L_NFS=$(grep "^1," "$NFS_STATS" | cut -d',' -f6)
BW_NFS=$(tail -3 "$NFS_STATS" | awk -F',' '{sum += $4; count++} END {printf "%.2f", sum/count}')

echo ""
echo "================================================================"
echo "           PARAMETRES POUR LE MODELE                            "
echo "================================================================"
echo ""
echo "SCP:"
echo "  L_scp = $L_SCP ms"
echo "  BW_scp = $BW_SCP MB/s"
echo ""
echo "NFS:"
echo "  L_nfs = $L_NFS ms"
echo "  BW_nfs = $BW_NFS MB/s"
echo ""

# Creer fichier de parametres
PARAMS_FILE="$RESULTS_DIR/transfer_params_$TIMESTAMP.txt"
cat > "$PARAMS_FILE" << EOF
# Parametres de transfert pour le modele theorique
# Date: $(date)
# Source: $MASTER_NODE
# Destination: $TARGET_NODE

L_scp_ms = $L_SCP
BW_scp_mbps = $BW_SCP

L_nfs_ms = $L_NFS
BW_nfs_mbps = $BW_NFS
EOF

echo "Fichiers generes:"
echo "  SCP donnees: $SCP_FILE"
echo "  SCP stats: $SCP_STATS"
echo "  NFS donnees: $NFS_FILE"
echo "  NFS stats: $NFS_STATS"
echo "  Parametres: $PARAMS_FILE"

# Nettoyage
oarsh -n $TARGET_NODE "rm -rf /tmp/transfer_benchmark" 2>/dev/null
rm -rf "$NFS_DIR"
