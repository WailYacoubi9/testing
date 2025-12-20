#!/bin/bash

###############################################################################
# Grid5000 SCP vs NFS Performance Test
# À exécuter sur Grid5000 après déploiement manuel
# Usage: oarsub -l nodes=4,walltime=1:00 "cd ~/wordcount-distributed && bash deploy/test_scp_nfs_grid5000.sh"
###############################################################################

set -e

# Get project directory
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(pwd)"
fi

# Get nodes from OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "✗ Erreur: OAR_NODEFILE non défini"
    echo "  Ce script doit être exécuté via oarsub"
    echo "  Usage: oarsub -l nodes=4,walltime=1:00 \"cd ~/wordcount-distributed && bash deploy/test_scp_nfs_grid5000.sh\""
    exit 1
fi

NODES=($(cat "$OAR_NODEFILE"))
MASTER=${NODES[0]}
WORKERS=("${NODES[@]:1}")
NUM_NODES=${#NODES[@]}

RESULTS_DIR="grid5000_results"
mkdir -p "$RESULTS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║      GRID5000 SCP vs NFS PERFORMANCE TEST                 ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo ""
echo "Configuration:"
echo "  Master: $MASTER"
echo "  Workers: ${WORKERS[@]}"
echo "  Total nodes: $NUM_NODES"
echo ""

# Create test data
echo "[1/5] Génération des données de test..."

mkdir -p test_data

for SIZE in 10 50 100; do
    FILE="test_data/test_${SIZE}mb.txt"
    dd if=/dev/urandom of="$FILE" bs=1M count=$SIZE 2>/dev/null
    echo "  ✓ test_${SIZE}mb.txt créé"
done

# Create results file
RESULTS_FILE="$RESULTS_DIR/scp_nfs_results.csv"
echo "Method,File_Size_MB,Num_Nodes,Time_ms,Throughput_MBps" > "$RESULTS_FILE"

# Test SCP
echo ""
echo "[2/5] Test SCP - Distribution des fichiers..."

for SIZE in 10 50 100; do
    FILE="test_data/test_${SIZE}mb.txt"
    
    # Time SCP distribution
    START_TIME=$(date +%s%N)
    
    for WORKER in "${WORKERS[@]}"; do
        scp "$FILE" "$WORKER:/tmp/test_file.txt" > /dev/null 2>&1 &
    done
    wait
    
    END_TIME=$(date +%s%N)
    ELAPSED_MS=$((($END_TIME - $START_TIME) / 1000000))
    THROUGHPUT=$(echo "scale=2; ($SIZE * ${#WORKERS[@]}) * 1000 / $ELAPSED_MS" | bc)
    
    echo "  ✓ SCP ${SIZE}MB to ${#WORKERS[@]} workers: ${ELAPSED_MS}ms (${THROUGHPUT}MB/s)"
    echo "SCP,$SIZE,${#WORKERS[@]},$ELAPSED_MS,$THROUGHPUT" >> "$RESULTS_FILE"
    
    # Cleanup
    for WORKER in "${WORKERS[@]}"; do
        ssh "$WORKER" "rm -f /tmp/test_file.txt" 2>/dev/null &
    done
    wait
done

# Test NFS
echo ""
echo "[3/5] Test NFS - Accès aux fichiers..."

# Create NFS mount point
NFS_MOUNT="/tmp/nfs_test"
mkdir -p "$NFS_MOUNT"

# For local testing, use /home (which is NFS-mounted on Grid5000)
NFS_PATH="/home/$USER/nfs_test_data"
mkdir -p "$NFS_PATH"

# Copy test files to NFS
cp test_data/test_*.txt "$NFS_PATH/" 2>/dev/null || true

for SIZE in 10 50 100; do
    FILE="$NFS_PATH/test_${SIZE}mb.txt"
    
    if [ ! -f "$FILE" ]; then
        continue
    fi
    
    # Time NFS access
    START_TIME=$(date +%s%N)
    
    for WORKER in "${WORKERS[@]}"; do
        ssh "$WORKER" "cat $FILE > /dev/null" > /dev/null 2>&1 &
    done
    wait
    
    END_TIME=$(date +%s%N)
    ELAPSED_MS=$((($END_TIME - $START_TIME) / 1000000))
    THROUGHPUT=$(echo "scale=2; ($SIZE * ${#WORKERS[@]}) * 1000 / $ELAPSED_MS" | bc)
    
    echo "  ✓ NFS ${SIZE}MB from ${#WORKERS[@]} workers: ${ELAPSED_MS}ms (${THROUGHPUT}MB/s)"
    echo "NFS,$SIZE,${#WORKERS[@]},$ELAPSED_MS,$THROUGHPUT" >> "$RESULTS_FILE"
done

# Cleanup
echo ""
echo "[4/5] Nettoyage..."

rm -rf test_data
for WORKER in "${WORKERS[@]}"; do
    ssh "$WORKER" "rm -f /tmp/test_file.txt" 2>/dev/null &
done
wait

echo "  ✓ Nettoyage complété"

# Display results
echo ""
echo "[5/5] Résultats:"
echo ""

cat "$RESULTS_FILE"

echo ""
echo "Résumé:"
echo ""

# Calculate speedups
for SIZE in 10 50 100; do
    SCP_TIME=$(grep "^SCP,$SIZE" "$RESULTS_FILE" | cut -d',' -f4)
    NFS_TIME=$(grep "^NFS,$SIZE" "$RESULTS_FILE" | cut -d',' -f4)
    
    if [ -n "$SCP_TIME" ] && [ -n "$NFS_TIME" ] && [ "$NFS_TIME" -gt 0 ]; then
        SPEEDUP=$(echo "scale=2; $SCP_TIME / $NFS_TIME" | bc)
        echo "  ${SIZE}MB: SCP (${SCP_TIME}ms) vs NFS (${NFS_TIME}ms) → Speedup: ${SPEEDUP}x"
    fi
done

echo ""
echo "Fichier de résultats: $RESULTS_FILE"
echo ""
echo "✓ Test complété avec succès"
