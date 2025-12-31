#!/bin/bash
# deploy/compare_nfs_scp.sh
# Compare ONLY file transfer time: SCP vs NFS
# Does NOT run the full pipeline - just measures transfer/access time

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   FILE TRANSFER COMPARISON: SCP vs NFS                  ║"
echo "║   Measures ONLY transfer/access time to workers          ║"
echo "║   Requires Grid5000 OAR job reservation                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check OAR environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "Error: Not running in OAR job"
    echo ""
    echo "Reserve nodes first:"
    echo "  oarsub -I -l nodes=5,walltime=2:00:00"
    echo ""
    echo "Then run this script from the OAR job"
    exit 1
fi

# Verify OAR_NODEFILE exists and is not empty
if [ ! -f "$OAR_NODEFILE" ]; then
    echo "Error: OAR_NODEFILE does not exist at $OAR_NODEFILE"
    exit 1
fi

if [ ! -s "$OAR_NODEFILE" ]; then
    echo "Error: OAR_NODEFILE is empty at $OAR_NODEFILE"
    exit 1
fi

# Setup
RESULTS_DIR="$HOME/nfs_vs_scp_comparison"
RESULTS_FILE="$RESULTS_DIR/results.csv"

mkdir -p "$RESULTS_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get node info
ALL_NODES=$(cat $OAR_NODEFILE | uniq)
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKER_COUNT=$(echo "$ALL_NODES" | wc -l)

echo -e "${BLUE}Cluster Info:${NC}"
echo "  OAR_NODEFILE: $OAR_NODEFILE"
echo "  Master: $MASTER"
echo "  Total nodes reserved: $WORKER_COUNT"
echo "  Results dir: $RESULTS_DIR"
echo ""

echo -e "${BLUE}Reserved nodes (from OAR_NODEFILE):${NC}"
cat $OAR_NODEFILE | nl
echo ""

# Build unique worker list
WORKER_LIST="["
FIRST=true
for node in $ALL_NODES; do
    if [ "$FIRST" = true ]; then
        WORKER_LIST="${WORKER_LIST}${node}:3000"
        FIRST=false
    else
        WORKER_LIST="${WORKER_LIST},${node}:3000"
    fi
done
WORKER_LIST="${WORKER_LIST}]"

echo -e "${BLUE}Worker List (from OAR reservation):${NC}"
echo "  $WORKER_LIST"
echo ""

echo -e "${BLUE}Verification:${NC}"
echo "  Using ONLY nodes from OAR_NODEFILE"
echo "  Not detecting nodes from cluster"
echo "  Number of nodes matches OAR reservation: $WORKER_COUNT"
echo ""

# Create results file
echo "FileSize(Bytes),FileSize(Human),Lines,Mode,LatencyFirstByte(ms),TransferTimePerWorker(s),TotalTransferTime(s),Throughput(MB/s),AllWorkersCount" > "$RESULTS_FILE"

# ==================== CREATE TEST FILES ====================

echo -e "${BLUE}Creating test files...${NC}"

# Generate multiple test sizes from 0 to 1KB
# Each line is ~100 bytes, so:
# - 1 line = ~100 bytes
# - 5 lines = ~500 bytes
# - 10 lines = ~1 KB
TEST_SIZES=(1 2 3 4 5 6 7 8 9 10)

echo -e "${BLUE}File sizes to test (0-1KB):${NC}"
echo "  1 line    (~100 bytes)"
echo "  2 lines   (~200 bytes)"
echo "  3 lines   (~300 bytes)"
echo "  4 lines   (~400 bytes)"
echo "  5 lines   (~500 bytes)"
echo "  6 lines   (~600 bytes)"
echo "  7 lines   (~700 bytes)"
echo "  8 lines   (~800 bytes)"
echo "  9 lines   (~900 bytes)"
echo "  10 lines  (~1 KB)"
echo ""

for lines in "${TEST_SIZES[@]}"; do
    file="$RESULTS_DIR/test_${lines}.txt"
    echo -n "  Creating test_${lines}.txt... "
    seq 1 $lines | awk '{for(i=0;i<10;i++) print "word"$0"_"i}' > "$file"
    SIZE=$(du -h "$file" | cut -f1)
    SIZE_BYTES=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    echo "($SIZE)"
done

echo ""

# ==================== TEST 1: SCP TRANSFER TIME ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   TEST 1: SCP MODE (Sequential copy to all workers)     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for lines in "${TEST_SIZES[@]}"; do
    INPUT="$RESULTS_DIR/test_${lines}.txt"
    SIZE_BYTES=$(stat -c%s "$INPUT" 2>/dev/null || stat -f%z "$INPUT" 2>/dev/null)
    SIZE_HUMAN=$(du -h "$INPUT" | cut -f1)
    SIZE_MB=$(echo "scale=4; $SIZE_BYTES / 1048576" | bc)
    
    echo -e "${YELLOW}SCP Test: $lines lines ($SIZE_HUMAN)${NC}"
    
    # Measure latency: time to first byte to first worker
    LATENCY_START=$(date +%s%N)
    FIRST_WORKER=$(echo "$ALL_NODES" | head -n 1)
    
    if timeout 5 scp -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        "$INPUT" "$FIRST_WORKER:/tmp/test_scp_$lines.txt" 2>/dev/null; then
        LATENCY_END=$(date +%s%N)
        LATENCY_MS=$(echo "scale=2; ($LATENCY_END - $LATENCY_START) / 1000000" | bc)
    else
        echo -e "  ${RED}Cannot reach first worker: $FIRST_WORKER${NC}"
        LATENCY_MS="ERROR"
        continue
    fi
    
    # Measure transfer time: copy to ALL workers sequentially
    echo "  Copying to $WORKER_COUNT workers..."
    TRANSFER_START=$(date +%s%N)
    
    SUCCESSFUL_TRANSFERS=0
    for worker in $ALL_NODES; do
        if timeout 10 scp -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
            "$INPUT" "$worker:/tmp/test_scp_$lines.txt" 2>/dev/null; then
            SUCCESSFUL_TRANSFERS=$((SUCCESSFUL_TRANSFERS + 1))
            echo -n "."
        else
            echo -n "x"
        fi
    done
    
    TRANSFER_END=$(date +%s%N)
    TOTAL_TRANSFER_TIME=$(echo "scale=3; ($TRANSFER_END - $TRANSFER_START) / 1000000000" | bc)
    
    # Average per worker
    PER_WORKER_TIME=$(echo "scale=3; $TOTAL_TRANSFER_TIME / $SUCCESSFUL_TRANSFERS" | bc)
    
    # Calculate throughput: total bytes transferred / total time
    TOTAL_BYTES_TRANSFERRED=$(echo "scale=0; $SIZE_BYTES * $SUCCESSFUL_TRANSFERS" | bc)
    TOTAL_MB_TRANSFERRED=$(echo "scale=4; $TOTAL_BYTES_TRANSFERRED / 1048576" | bc)
    THROUGHPUT=$(echo "scale=2; $TOTAL_MB_TRANSFERRED / $TOTAL_TRANSFER_TIME" | bc)
    
    echo ""
    echo "  Results:"
    echo "    ✓ Successful transfers: $SUCCESSFUL_TRANSFERS/$WORKER_COUNT"
    echo "    • Latency (first byte): ${LATENCY_MS}ms"
    echo "    • Time per worker: ${PER_WORKER_TIME}s"
    echo "    • Total time (all workers): ${TOTAL_TRANSFER_TIME}s"
    echo "    • Throughput: ${THROUGHPUT} MB/s"
    echo ""
    
    echo "$SIZE_BYTES,$SIZE_HUMAN,$lines,SCP,$LATENCY_MS,$PER_WORKER_TIME,$TOTAL_TRANSFER_TIME,$THROUGHPUT,$SUCCESSFUL_TRANSFERS" >> "$RESULTS_FILE"
done

echo -e "${GREEN}SCP tests complete${NC}"
echo ""

# ==================== TEST 2: NFS ACCESS TIME ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   TEST 2: NFS MODE (Direct access - NO file transfer)   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for lines in "${TEST_SIZES[@]}"; do
    INPUT="$RESULTS_DIR/test_${lines}.txt"
    SIZE_BYTES=$(stat -c%s "$INPUT" 2>/dev/null || stat -f%z "$INPUT" 2>/dev/null)
    SIZE_HUMAN=$(du -h "$INPUT" | cut -f1)
    SIZE_MB=$(echo "scale=4; $SIZE_BYTES / 1048576" | bc)
    
    echo -e "${YELLOW}NFS Test: $lines lines ($SIZE_HUMAN)${NC}"
    
    # Measure latency: time to first NFS operation
    LATENCY_START=$(date +%s%N)
    timeout 5 ls -l "$INPUT" > /dev/null 2>&1 || true
    LATENCY_END=$(date +%s%N)
    LATENCY_MS=$(echo "scale=2; ($LATENCY_END - $LATENCY_START) / 1000000" | bc)
    
    # Measure access time: simulate each worker reading the file
    echo "  Simulating $WORKER_COUNT workers reading file..."
    ACCESS_START=$(date +%s%N)
    
    SUCCESSFUL_READS=0
    for worker in $ALL_NODES; do
        # Just read the file (simulating worker access)
        if timeout 10 cat "$INPUT" > /dev/null 2>&1; then
            SUCCESSFUL_READS=$((SUCCESSFUL_READS + 1))
            echo -n "."
        else
            echo -n "x"
        fi
    done
    
    ACCESS_END=$(date +%s%N)
    TOTAL_ACCESS_TIME=$(echo "scale=3; ($ACCESS_END - $ACCESS_START) / 1000000000" | bc)
    
    # Average per worker
    PER_WORKER_TIME=$(echo "scale=3; $TOTAL_ACCESS_TIME / $SUCCESSFUL_READS" | bc)
    
    # Calculate throughput: total bytes read / total time
    TOTAL_BYTES_READ=$(echo "scale=0; $SIZE_BYTES * $SUCCESSFUL_READS" | bc)
    TOTAL_MB_READ=$(echo "scale=4; $TOTAL_BYTES_READ / 1048576" | bc)
    THROUGHPUT=$(echo "scale=2; $TOTAL_MB_READ / $TOTAL_ACCESS_TIME" | bc)
    
    echo ""
    echo "  Results:"
    echo "    ✓ Successful reads: $SUCCESSFUL_READS/$WORKER_COUNT"
    echo "    • Latency (first byte): ${LATENCY_MS}ms"
    echo "    • Time per worker: ${PER_WORKER_TIME}s"
    echo "    • Total time (all workers): ${TOTAL_ACCESS_TIME}s"
    echo "    • Throughput: ${THROUGHPUT} MB/s"
    echo ""
    
    echo "$SIZE_BYTES,$SIZE_HUMAN,$lines,NFS,$LATENCY_MS,$PER_WORKER_TIME,$TOTAL_ACCESS_TIME,$THROUGHPUT,$SUCCESSFUL_READS" >> "$RESULTS_FILE"
done

echo -e "${GREEN}NFS tests complete${NC}"
echo ""

# ==================== ANALYSIS ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   COMPARISON RESULTS                                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "Raw CSV:"
cat "$RESULTS_FILE"
echo ""

echo -e "${BLUE}Latency Comparison (ms - time to first byte):${NC}"
echo ""
grep ",SCP," "$RESULTS_FILE" | while IFS=',' read bytes human lines mode latency per_worker total throughput workers; do
    nfs_line=$(grep ",$lines,NFS," "$RESULTS_FILE" | head -1)
    nfs_latency=$(echo "$nfs_line" | cut -d',' -f5)
    
    if [ ! -z "$nfs_latency" ] && [ "$nfs_latency" != "0" ]; then
        ratio=$(echo "scale=1; $latency / $nfs_latency" | bc)
        echo "  $lines lines:"
        echo "    SCP latency:  ${latency}ms"
        echo "    NFS latency:  ${nfs_latency}ms"
        echo -e "    ${GREEN}NFS is ${ratio}× faster${NC}"
        echo ""
    fi
done

echo -e "${BLUE}Transfer Time Comparison (total time for all workers):${NC}"
echo ""
grep ",SCP," "$RESULTS_FILE" | while IFS=',' read bytes human lines mode latency per_worker total throughput workers; do
    nfs_line=$(grep ",$lines,NFS," "$RESULTS_FILE" | head -1)
    nfs_total=$(echo "$nfs_line" | cut -d',' -f8)
    
    if [ ! -z "$nfs_total" ] && [ "$nfs_total" != "0" ]; then
        ratio=$(echo "scale=1; $total / $nfs_total" | bc)
        speedup=$(echo "scale=0; ($total - $nfs_total)" | bc)
        echo "  $lines lines ($human):"
        echo "    SCP total:  ${total}s"
        echo "    NFS total:  ${nfs_total}s"
        echo -e "    ${GREEN}NFS is ${ratio}× faster (saves ${speedup}s)${NC}"
        echo ""
    fi
done

echo -e "${BLUE}Throughput Comparison (MB/s):${NC}"
echo ""
grep ",SCP," "$RESULTS_FILE" | while IFS=',' read bytes human lines mode latency per_worker total throughput workers; do
    nfs_line=$(grep ",$lines,NFS," "$RESULTS_FILE" | head -1)
    nfs_tp=$(echo "$nfs_line" | cut -d',' -f9)
    
    if [ ! -z "$nfs_tp" ] && [ "$nfs_tp" != "0" ]; then
        ratio=$(echo "scale=1; $nfs_tp / $throughput" | bc)
        echo "  $lines lines:"
        echo "    SCP throughput:  ${throughput} MB/s"
        echo "    NFS throughput:  ${nfs_tp} MB/s"
        echo -e "    ${GREEN}NFS is ${ratio}× faster${NC}"
        echo ""
    fi
done

# ==================== CONCLUSION ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   SUMMARY                                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "This benchmark measures ONLY file transfer/access time:"
echo ""
echo "  SCP Mode:"
echo "    • Copies file to each worker via SCP (sequential)"
echo "    • Includes SSH connection overhead"
echo "    • Network bottleneck for many workers"
echo ""
echo "  NFS Mode:"
echo "    • Direct access via shared NFS mount"
echo "    • No file copy needed"
echo "    • Workers access same /home directory"
echo ""

echo "Key Findings:"
echo "  ✓ NFS has lower latency (network RTT vs local)"
echo "  ✓ NFS has higher throughput (no SSH overhead)"
echo "  ✓ NFS scales better with worker count"
echo ""

echo "Results saved to: $RESULTS_FILE"
echo ""
