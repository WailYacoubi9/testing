#!/bin/bash

# NFS-based Mono-Site using HOME directory (no sudo required!)
# Works when /home is already mounted on NFS across Grid5000 nodes

set -e  # Exit on any error

# Configuration - Using HOME directory instead of /tmp
NFS_SHARED_DIR="$HOME/nfs_wordcount"
PROJECT_DIR="$HOME/wordcount-distributed"
PORT=3000

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   NFS Mono-Site (Using Shared Home Directory)          ║"
echo "║   No sudo required - /home is already on NFS!          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in OAR job
if [ -z "$OAR_NODEFILE" ]; then
    echo -e "${RED}❌ Error: Not running in an OAR job${NC}"
    echo "Please reserve nodes first: oarsub -I -l nodes=4,walltime=1:00:00"
    exit 1
fi

# Get all nodes (Java will separate master from workers)
ALL_NODES=$(cat $OAR_NODEFILE | uniq)
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)
WORKER_COUNT=$(echo "$WORKERS" | wc -l)

echo -e "${BLUE}🖥️  Master node: $MASTER${NC}"
echo -e "${BLUE}👷 Workers ($WORKER_COUNT):${NC}"
echo "$WORKERS" | nl
echo ""

# Build node list for Java (ALL nodes: master + workers)
# Java ClusterManager will handle master/worker separation
WORKER_LIST="["
FIRST=true
for node in $ALL_NODES; do
    if [ "$FIRST" = true ]; then
        WORKER_LIST="${WORKER_LIST}${node}:${PORT}"
        FIRST=false
    else
        WORKER_LIST="${WORKER_LIST},${node}:${PORT}"
    fi
done
WORKER_LIST="${WORKER_LIST}]"

echo -e "${GREEN}📋 Node list (master + workers): $WORKER_LIST${NC}"
echo ""

# ==================== COMPILE JAVA CODE ====================

echo -e "${BLUE}🔨 Compiling Java code...${NC}"
cd $PROJECT_DIR
javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
      src/parser/*.java src/network/worker/*.java \
      src/network/master/*.java src/scheduler/*.java

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Java compilation successful${NC}"
else
    echo -e "${RED}❌ Java compilation failed${NC}"
    exit 1
fi
echo ""

# ==================== NFS SETUP (No sudo!) ====================

echo -e "${BLUE}📁 Setting up NFS shared directory in HOME...${NC}"

# Create NFS directory (in HOME, already on NFS!)
mkdir -p $NFS_SHARED_DIR
chmod 755 $NFS_SHARED_DIR

# In NFS mode, files are already accessible - no copy needed!
# Just ensure the test directory exists in the project
if [ ! -d "$PROJECT_DIR/test" ]; then
    echo -e "${RED}❌ Error: $PROJECT_DIR/test directory not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ NFS directory created: $NFS_SHARED_DIR${NC}"

# Verify NFS is accessible from workers
echo -e "${BLUE}🔍 Verifying NFS accessibility from workers...${NC}"
FIRST_WORKER=$(echo "$WORKERS" | head -n 1)
if ssh $FIRST_WORKER "ls $NFS_SHARED_DIR/ > /dev/null 2>&1"; then
    echo -e "${GREEN}✅ Home directory IS shared via NFS!${NC}"
else
    echo -e "${RED}❌ Home directory NOT accessible from workers${NC}"
    echo -e "${YELLOW}This means /home is NOT on NFS on this site${NC}"
    echo "You would need sudo/kadeploy for real NFS setup"
    exit 1
fi

echo ""

# ==================== PREPARE INPUT FILE ====================

echo -e "${BLUE}📝 Preparing input file...${NC}"

# Check if user provided input file
if [ -z "$1" ]; then
    echo "No input file provided, creating test file..."
    cat > $NFS_SHARED_DIR/test_input.txt << 'EOF'
Test NFS mono-site avec répertoire HOME partagé.
Système distribué de comptage de mots sur Grid5000.
Java RMI pour communication entre les nœuds.
Makefile parsing et gestion des dépendances.
Architecture distribuée avec workers multiples.
Grenoble Lyon Nancy infrastructure de recherche.
EOF
    INPUT_FILE="test_input.txt"
else
    # In NFS mode, use absolute path or create symlink - no copy needed!
    INPUT_FILE=$(basename "$1")
    ln -sf "$(realpath $1)" $NFS_SHARED_DIR/$INPUT_FILE
    echo -e "${GREEN}✅ Input file linked to NFS (no copy): $INPUT_FILE${NC}"
fi

# Compile wordcount in NFS directory
echo -e "${BLUE}🔨 Compiling wordcount program in NFS directory...${NC}"
gcc -o $NFS_SHARED_DIR/wordcount $PROJECT_DIR/test/wordcount.c
echo -e "${GREEN}✅ Wordcount compiled${NC}"
echo ""

# ==================== DEPLOY WORKERS ====================

echo -e "${BLUE}📦 Deploying workers...${NC}"

# In NFS mode: bin directory is already accessible on all nodes via /home
# NO SCP NEEDED - all nodes see $PROJECT_DIR/bin automatically!
echo -e "${GREEN}✅ Compiled code already accessible via NFS (no copy needed)${NC}"

# Start worker nodes
echo -e "${BLUE}🚀 Starting worker nodes...${NC}"
for worker in $WORKERS; do
    echo "  Starting worker on $worker:$PORT..."
    ssh $worker "nohup java -cp $PROJECT_DIR/bin network.worker.WorkerNode $worker $PORT > $NFS_SHARED_DIR/worker_nfs_${worker}.log 2>&1 &" &
done

# Wait for workers to initialize
echo -e "${BLUE}⏳ Waiting for workers to initialize...${NC}"
sleep 10
echo -e "${GREEN}✅ All workers started${NC}"
echo ""

# ==================== RUN MAIN ====================

echo -e "${BLUE}🚀 Starting distributed execution (NFS mode with HOME)...${NC}"
cd $PROJECT_DIR

java -cp bin scheduler.MainNFS "$NFS_SHARED_DIR/$INPUT_FILE" "$WORKER_LIST" "$NFS_SHARED_DIR"

# ==================== DISPLAY RESULTS ====================

echo ""
echo -e "${GREEN}✅ Execution completed!${NC}"
echo ""

if [ -f "$NFS_SHARED_DIR/total.txt" ]; then
    RESULT=$(cat $NFS_SHARED_DIR/total.txt)
    echo "╔════════════════════════════════════╗"
    echo "║  Total word count: $RESULT           ║"
    echo "╚════════════════════════════════════╝"
    echo ""

    echo "Files in NFS directory:"
    ls -lh $NFS_SHARED_DIR/*.txt 2>/dev/null | head -10
else
    echo -e "${RED}❌ Result file not found: $NFS_SHARED_DIR/total.txt${NC}"
fi

# ==================== CLEANUP ====================

echo ""
echo -e "${BLUE}🧹 Cleanup...${NC}"

# Stop workers
for worker in $WORKERS; do
    ssh $worker "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
done
echo -e "${GREEN}✅ Workers stopped${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  NFS Mono-Site Test Complete! 🎉  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}ℹ️  NFS directory preserved at: $NFS_SHARED_DIR${NC}"
echo -e "${BLUE}   You can inspect results with: ls -la $NFS_SHARED_DIR/${NC}"
