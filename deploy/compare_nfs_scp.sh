#!/bin/bash
# deploy/compare_nfs_scp.sh
# Compare NFS vs SCP modes on Grid5000

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   NFS vs SCP MODE COMPARISON                            ║"
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

# Setup
PROJECT_DIR="$HOME/wordcount-distributed"
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
echo "  Master: $MASTER"
echo "  Total nodes: $WORKER_COUNT"
echo "  Results dir: $RESULTS_DIR"
echo ""

# Build worker list
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

echo -e "${BLUE}Worker List: $WORKER_LIST${NC}"
echo ""

# Compile
echo -e "${BLUE}Compiling Java...${NC}"
cd "$PROJECT_DIR"
javac -d bin src/**/*.java 2>/dev/null
echo -e "${GREEN}Compiled${NC}"
echo ""

# Create results file
echo "Mode,FileSize,Lines,Duration,Workers,Status" > "$RESULTS_FILE"

# ==================== TEST DATA ====================

echo -e "${BLUE}Creating test files...${NC}"

TEST_SIZES=(100 1000 10000)

for lines in "${TEST_SIZES[@]}"; do
    file="$RESULTS_DIR/test_${lines}.txt"
    seq 1 $lines | awk '{for(i=0;i<10;i++) print "word"$0"_"i}' > "$file"
    SIZE=$(du -h "$file" | cut -f1)
    echo -e "  ${GREEN}${NC} test_${lines}.txt ($SIZE)"
done

echo ""

# ==================== TEST SCP MODE ====================

echo -e "${BLUE}=== TESTING SCP MODE ===${NC}"
echo "Script: run_mono_site.sh"
echo "Coordinator: MasterCoordinator.java (with file transfers)"
echo ""

for lines in "${TEST_SIZES[@]}"; do
    INPUT="$RESULTS_DIR/test_${lines}.txt"
    
    echo -e "${YELLOW}SCP Test: $lines lines${NC}"
    
    # Run SCP mode with timing
    SCP_OUTPUT="$RESULTS_DIR/scp_${lines}.log"
    
    START=$(date +%s%N)
    bash deploy/run_mono_site.sh "$INPUT" > "$SCP_OUTPUT" 2>&1 || true
    END=$(date +%s%N)
    
    # Calculate duration in seconds
    DURATION=$(echo "scale=2; ($END - $START) / 1000000000" | bc)
    
    SIZE=$(ls -lh "$INPUT" | awk '{print $5}')
    STATUS=$(grep -q "SUCCESS" "$SCP_OUTPUT" && echo "OK" || echo "FAIL")
    
    echo "SCP,$SIZE,$lines,$DURATION,$WORKER_COUNT,$STATUS" >> "$RESULTS_FILE"
    
    echo "  Duration: ${DURATION}s"
    echo "  Status: $STATUS"
    echo ""
done

echo -e "${GREEN}SCP mode tests complete${NC}"
echo ""

# ==================== TEST NFS MODE ====================

echo -e "${BLUE}=== TESTING NFS MODE ===${NC}"
echo "Script: run_nfs_home.sh"
echo "Coordinator: MasterCoordinatorNFS.java (direct NFS access)"
echo ""

for lines in "${TEST_SIZES[@]}"; do
    INPUT="$RESULTS_DIR/test_${lines}.txt"
    
    echo -e "${YELLOW}NFS Test: $lines lines${NC}"
    
    # Run NFS mode with timing
    NFS_OUTPUT="$RESULTS_DIR/nfs_${lines}.log"
    
    START=$(date +%s%N)
    bash deploy/run_nfs_home.sh "$INPUT" > "$NFS_OUTPUT" 2>&1 || true
    END=$(date +%s%N)
    
    # Calculate duration in seconds
    DURATION=$(echo "scale=2; ($END - $START) / 1000000000" | bc)
    
    SIZE=$(ls -lh "$INPUT" | awk '{print $5}')
    STATUS=$(grep -q "SUCCESS" "$NFS_OUTPUT" && echo "OK" || echo "FAIL")
    
    echo "NFS,$SIZE,$lines,$DURATION,$WORKER_COUNT,$STATUS" >> "$RESULTS_FILE"
    
    echo "  Duration: ${DURATION}s"
    echo "  Status: $STATUS"
    echo ""
done

echo -e "${GREEN}NFS mode tests complete${NC}"
echo ""

# ==================== ANALYSIS ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   COMPARISON RESULTS                                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "Raw results (CSV):"
cat "$RESULTS_FILE"
echo ""

echo "Summary:"
echo ""

echo -e "${BLUE}SCP Mode:${NC}"
grep "^SCP" "$RESULTS_FILE" | while IFS=',' read mode size lines duration workers status; do
    echo "  $lines lines: ${duration}s ($status)"
done

echo ""
echo -e "${BLUE}NFS Mode:${NC}"
grep "^NFS" "$RESULTS_FILE" | while IFS=',' read mode size lines duration workers status; do
    echo "  $lines lines: ${duration}s ($status)"
done

echo ""
echo -e "${BLUE}Performance Difference:${NC}"

# Calculate average times
SCP_AVG=$(grep "^SCP" "$RESULTS_FILE" | awk -F',' '{sum+=$4; count++} END {print sum/count}')
NFS_AVG=$(grep "^NFS" "$RESULTS_FILE" | awk -F',' '{sum+=$4; count++} END {print sum/count}')

if [ ! -z "$SCP_AVG" ] && [ ! -z "$NFS_AVG" ]; then
    DIFF=$(echo "scale=2; $SCP_AVG - $NFS_AVG" | bc)
    PERCENT=$(echo "scale=1; ($DIFF / $SCP_AVG) * 100" | bc)
    
    if (( $(echo "$NFS_AVG < $SCP_AVG" | bc -l) )); then
        echo -e "  ${GREEN}NFS is ${PERCENT}% faster than SCP${NC}"
        echo "  SCP avg: ${SCP_AVG}s"
        echo "  NFS avg: ${NFS_AVG}s"
    else
        echo -e "  ${YELLOW}SCP is faster (unexpected)${NC}"
    fi
fi

echo ""

# ==================== COORDINATOR ANALYSIS ====================

echo -e "${BLUE}Coordinator Detection:${NC}"
echo ""

echo "SCP Mode Indicators:"
if grep -q "scp\|SCP\|MasterCoordinator" "$RESULTS_DIR/scp_"*.log 2>/dev/null; then
    echo -e "  ${GREEN}Found SCP/MasterCoordinator references${NC}"
else
    echo -e "  ${YELLOW}⚠️  No explicit references found${NC}"
fi

echo ""
echo "NFS Mode Indicators:"
if grep -q "NFS\|MasterCoordinatorNFS" "$RESULTS_DIR/nfs_"*.log 2>/dev/null; then
    echo -e "  ${GREEN}Found NFS/MasterCoordinatorNFS references${NC}"
else
    echo -e "  ${YELLOW}⚠️  No explicit references found${NC}"
fi

echo ""

# ==================== CONCLUSION ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   CONCLUSION                                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "Key Findings:"
echo ""

# Check correctness
SCP_FAIL=$(grep "FAIL" "$RESULTS_FILE" | grep "^SCP" | wc -l)
NFS_FAIL=$(grep "FAIL" "$RESULTS_FILE" | grep "^NFS" | wc -l)

if [ $SCP_FAIL -eq 0 ]; then
    echo -e "  ${GREEN}SCP mode: All tests PASSED${NC}"
else
    echo -e "  ${RED}SCP mode: $SCP_FAIL tests FAILED${NC}"
fi

if [ $NFS_FAIL -eq 0 ]; then
    echo -e "  ${GREEN}NFS mode: All tests PASSED${NC}"
else
    echo -e "  ${RED}NFS mode: $NFS_FAIL tests FAILED${NC}"
fi

echo ""
echo "Recommendations:"
echo "  - NFS mode is preferred for Grid5000 (no file transfers)"
echo "  - SCP mode works but with network overhead"
echo "  - Choose based on available infrastructure"
echo ""

echo "Full results saved to: $RESULTS_FILE"
echo ""
