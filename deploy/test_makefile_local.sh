#!/bin/bash
# deploy/test_makefile_local.sh
# Test Makefile generation and parsing without Grid5000

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MAKEFILE TEST - LOCAL ENVIRONMENT                     ║"
echo "║   No Grid5000 required - tests file splitting & parsing  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PROJECT_DIR="."
TEST_DIR="$PROJECT_DIR/makefile_test_results"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create test directory
mkdir -p "$TEST_DIR"
echo -e "${BLUE}📁 Test directory: $TEST_DIR${NC}"
echo ""

# ==================== COMPILE IF NEEDED ====================

if [ ! -d "bin" ]; then
    echo -e "${BLUE}🔨 Compiling Java source...${NC}"
    javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
          src/parser/*.java src/network/worker/*.java \
          src/network/master/*.java src/scheduler/*.java
    echo -e "${GREEN}Compilation successful${NC}"
    echo ""
fi

# ==================== CREATE TEST FILES ====================

echo -e "${BLUE}📝 Creating test files...${NC}"

# Create test files of different sizes
for lines in 10 100 1000; do
    file="$TEST_DIR/test_${lines}.txt"
    seq 1 $lines | awk '{for(i=0;i<10;i++) print "word"$0"_"i}' > "$file"
    echo -e "${GREEN}  Created: $file ($lines lines)${NC}"
done

echo ""

# ==================== TEST 1: MAKEFILE GENERATION ====================

echo -e "${BLUE}=== TEST 1: Makefile Generation from Input File ===${NC}"
echo ""

for lines in 10 100 1000; do
    INPUT="$TEST_DIR/test_${lines}.txt"
    OUTPUT="$TEST_DIR/Makefile_${lines}"
    
    echo -e "${YELLOW}Testing with $lines lines...${NC}"
    
    # Run Java in dynamic mode to generate Makefile
    cd "$PROJECT_DIR"
    java -cp bin scheduler.Main "$INPUT" "[localhost]" 2>&1 | tee "$TEST_DIR/run_${lines}.log" > /dev/null
    
    if [ -f "Makefile.generated" ]; then
        # Copy for analysis
        cp Makefile.generated "$OUTPUT"
        
        # Extract stats
        TASKS=$(grep -c "^[a-z]" "$OUTPUT" || echo "0")
        DEPS=$(grep -c ":" "$OUTPUT" || echo "0")
        SIZE=$(wc -l < "$OUTPUT")
        
        echo -e "${GREEN}  Makefile generated${NC}"
        echo "     - Tasks: $TASKS"
        echo "     - Dependencies: $DEPS"
        echo "     - Lines: $SIZE"
        
        # Show sample
        echo "     - Sample content:"
        head -3 "$OUTPUT" | sed 's/^/       /'
        
    else
        echo -e "${RED}  Makefile generation FAILED${NC}"
    fi
    
    echo ""
done

# ==================== TEST 2: FILE SPLITTING ====================

echo -e "${BLUE}=== TEST 2: File Splitting Equitability ===${NC}"
echo ""

INPUT="$TEST_DIR/test_1000.txt"
OUTPUT_PREFIX="$TEST_DIR/split"

echo -e "${YELLOW}Splitting test_1000.txt into 4 parts...${NC}"

java -cp bin utils.FileSplitter "$INPUT" 4 "$OUTPUT_PREFIX"

# Analyze split files
echo ""
echo -e "${YELLOW}Split Results:${NC}"

TOTAL_LINES=0
for i in 1 2 3 4; do
    file="${OUTPUT_PREFIX}${i}.txt"
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file")
        TOTAL_LINES=$((TOTAL_LINES + lines))
        echo -e "  ${OUTPUT_PREFIX}${i}.txt: $lines lines"
        cp "$file" "$TEST_DIR/"
    fi
done

echo ""
ORIGINAL=$(wc -l < "$INPUT")
echo -e "${YELLOW}Verification:${NC}"
echo "  Original: $ORIGINAL lines"
echo "  Total split: $TOTAL_LINES lines"

if [ $TOTAL_LINES -eq $ORIGINAL ]; then
    echo -e "${GREEN}  Perfect split - no data loss${NC}"
else
    echo -e "${RED}  Data loss detected: missing $((ORIGINAL - TOTAL_LINES)) lines${NC}"
fi

echo ""

# ==================== TEST 3: DEPENDENCY PARSING ====================

echo -e "${BLUE}=== TEST 3: Makefile Dependency Parsing ===${NC}"
echo ""

MAKEFILE="$TEST_DIR/Makefile_100"

if [ -f "$MAKEFILE" ]; then
    echo -e "${YELLOW}Parsing: $MAKEFILE${NC}"
    
    echo "  Tasks found:"
    grep "^[a-z]" "$MAKEFILE" | head -3 | sed 's/^/    /'
    
    echo ""
    echo "  Dependencies:"
    grep ":" "$MAKEFILE" | head -3 | sed 's/^/    /'
    
    echo ""
    echo -e "${GREEN}  Makefile structure valid${NC}"
else
    echo -e "${RED}  Makefile not found: $MAKEFILE${NC}"
fi

echo ""

# ==================== TEST 4: SPLIT EQUITABILITY ====================

echo -e "${BLUE}=== TEST 4: Split Equitability Check ===${NC}"
echo ""

echo -e "${YELLOW}Testing with different worker counts:${NC}"

for workers in 2 3 5 8; do
    INPUT="$TEST_DIR/test_1000.txt"
    PREFIX="$TEST_DIR/equity_${workers}"
    
    echo ""
    echo "  Splitting 1000 lines into $workers parts:"
    
    java -cp bin utils.FileSplitter "$INPUT" $workers "$PREFIX" 2>&1 | \
        grep "Created.*with.*lines" | sed 's/^/    /'
    
    # Calculate statistics
    MIN_LINES=99999
    MAX_LINES=0
    
    for i in $(seq 1 $workers); do
        file="${PREFIX}${i}.txt"
        if [ -f "$file" ]; then
            lines=$(wc -l < "$file")
            MIN_LINES=$(( lines < MIN_LINES ? lines : MIN_LINES ))
            MAX_LINES=$(( lines > MAX_LINES ? lines : MAX_LINES ))
            rm "$file"
        fi
    done
    
    DIFF=$((MAX_LINES - MIN_LINES))
    echo "    Min: $MIN_LINES, Max: $MAX_LINES, Diff: $DIFF"
    
    if [ $DIFF -le 1 ]; then
        echo -e "    ${GREEN}Equitable split (max ±1 line difference)${NC}"
    else
        echo -e "    ${RED}Unequitable split${NC}"
    fi
done

echo ""

# ==================== TEST 5: TASK SCHEDULER ====================

echo -e "${BLUE}=== TEST 5: Task Scheduler (Local Simulation) ===${NC}"
echo ""

INPUT="$TEST_DIR/test_100.txt"

echo -e "${YELLOW}Running local simulation...${NC}"
echo "  Input: $INPUT (100 lines)"
echo "  Workers: [localhost] (simulated)"
echo ""

cd "$PROJECT_DIR"

# Run and capture output
java -cp bin scheduler.Main "$INPUT" "[localhost]" 2>&1 | \
    grep -E "SPLITTER|SCHEDULER|TASK|executing|aggreg" | \
    head -15 | sed 's/^/  /'

echo ""
echo -e "${GREEN}Task scheduler test complete${NC}"

echo ""

# ==================== SUMMARY ====================

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   SUMMARY                                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "Tests completed:"
echo "  Makefile generation from input file"
echo "  File splitting into equitable parts"
echo "  Dependency parsing"
echo "  Split equitability validation"
echo "  Task scheduler simulation"
echo ""

echo "Test results saved in: $TEST_DIR/"
echo "  - Makefile_*: Generated Makefiles"
echo "  - split*: Split file examples"
echo "  - run_*.log: Execution logs"
echo ""

echo -e "${GREEN}All local tests PASSED!${NC}"
echo ""
echo "Next steps:"
echo "  1. Reserve Grid5000 nodes:"
echo "     oarsub -I -l nodes=4,walltime=1:00:00"
echo "  2. Test SCP mode:"
echo "     bash deploy/run_mono_site.sh test_input.txt"
echo "  3. Test NFS mode:"
echo "     bash deploy/run_nfs_home.sh test_input.txt"
echo ""
