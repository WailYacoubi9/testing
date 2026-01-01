#!/bin/bash

set -e

# ================= CONFIGURATION =================
NFS_SHARED_DIR="$HOME/nfs_wordcount"
PROJECT_DIR="$HOME/wordcount-distributed"
PORT=3000

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
# =================================================

echo "NFS Mono-Site (Using Shared Home Directory)"
echo "No sudo required - /home is already on NFS!"
echo ""

if [ -z "$OAR_NODEFILE" ]; then
    echo -e "${RED}Error: Not running in an OAR job${NC}"
    echo "Please reserve nodes first: oarsub -I -l nodes=4,walltime=1:00:00"
    exit 1
fi

ALL_NODES=$(cat $OAR_NODEFILE | uniq)
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)
WORKER_COUNT=$(echo "$WORKERS" | wc -l)

echo -e "${BLUE}Master node: $MASTER${NC}"
echo -e "${BLUE}Workers ($WORKER_COUNT):${NC}"
echo "$WORKERS" | nl
echo ""

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

echo -e "${GREEN}Node list (master + workers): $WORKER_LIST${NC}"
echo ""

echo -e "${BLUE}Compiling Java code...${NC}"
cd $PROJECT_DIR
javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
      src/parser/*.java src/network/worker/*.java \
      src/network/master/*.java src/scheduler/*.java

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Java compilation successful${NC}"
else
    echo -e "${RED}Java compilation failed${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}Setting up NFS shared directory in HOME...${NC}"
mkdir -p $NFS_SHARED_DIR
chmod 755 $NFS_SHARED_DIR

if [ ! -d "$PROJECT_DIR/test" ]; then
    echo -e "${RED}Error: $PROJECT_DIR/test directory not found${NC}"
    exit 1
fi
echo -e "${GREEN}NFS directory created: $NFS_SHARED_DIR${NC}"

echo -e "${BLUE}Preparing input file...${NC}"
if [ -z "$1" ]; then
    echo "No input file provided, creating test file..."
    cat > $NFS_SHARED_DIR/test_input.txt << 'EOF'
Test NFS mono-site.
EOF
    INPUT_FILE="test_input.txt"
else
    INPUT_FILE=$(basename "$1")
    # Lien symbolique au lieu de copie pour aller plus vite
    ln -sf "$(realpath $1)" $NFS_SHARED_DIR/$INPUT_FILE
    echo -e "${GREEN}Input file linked to NFS (no copy): $INPUT_FILE${NC}"
fi

echo -e "${BLUE}Compiling wordcount program in NFS directory...${NC}"
gcc -o $NFS_SHARED_DIR/wordcount $PROJECT_DIR/test/wordcount.c
echo -e "${GREEN}Wordcount compiled${NC}"
echo ""

echo -e "${BLUE}Deploying workers...${NC}"

# === CHRONO LANCEUR (Debut) ===
T_LAUNCH_START=$(date +%s%3N)

echo -e "${BLUE}Starting worker nodes...${NC}"
for worker in $WORKERS; do
    echo "  Starting worker on $worker:$PORT..."
    oarsh -n $worker "cd ~ && nohup java -cp $PROJECT_DIR/bin network.worker.WorkerNode $worker $PORT > /tmp/worker_nfs_${worker}.log 2>&1 &" &
done

echo -e "${BLUE}Waiting for workers to initialize...${NC}"
sleep 5

# === CHRONO LANCEUR (Fin) ===
T_LAUNCH_END=$(date +%s%3N)
LAUNCHER_TIME=$((T_LAUNCH_END - T_LAUNCH_START))
echo "[METRICS] LAUNCHER_TIME_MS=$LAUNCHER_TIME"

echo -e "${GREEN}All workers started${NC}"
echo ""

echo -e "${BLUE}Starting distributed execution (NFS mode with HOME)...${NC}"
cd $PROJECT_DIR

# Execution du Master
java -cp bin scheduler.MainNFS "$NFS_SHARED_DIR/$INPUT_FILE" "$WORKER_LIST" "$NFS_SHARED_DIR"

echo ""
echo -e "${GREEN}Execution completed!${NC}"
echo ""

echo -e "${BLUE}Cleanup...${NC}"
for worker in $WORKERS; do
    oarsh -n $worker "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
done
echo -e "${GREEN}Workers stopped${NC}"

echo -e "${GREEN}NFS Mono-Site Test Complete!${NC}"
