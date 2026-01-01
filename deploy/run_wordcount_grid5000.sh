#!/bin/bash

###############################################################################
# Grid5000 Wordcount Execution Script
# Exécute le wordcount distribué sur Grid5000 avec OAR
# Usage: oarsub -l nodes=4,walltime=1:00 'cd ~/wordcount-distributed && bash deploy/run_wordcount_grid5000.sh'
###############################################################################

set -e

# Get project directory
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(pwd)"
fi

# Get nodes from OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "Error: OAR_NODEFILE not defined"
    echo "This script must be executed via oarsub"
    echo "Usage: oarsub -l nodes=4,walltime=1:00 'cd ~/wordcount-distributed && bash deploy/run_wordcount_grid5000.sh'"
    exit 1
fi

# Read nodes from OAR
ALL_NODES=($(cat "$OAR_NODEFILE"))

# Use only the first MAX_NODES (1 master + rest as workers)
# Change MAX_NODES to use different number of nodes
MAX_NODES=4
if [ ${#ALL_NODES[@]} -lt $MAX_NODES ]; then
    MAX_NODES=${#ALL_NODES[@]}
fi

NODES=("${ALL_NODES[@]:0:$MAX_NODES}")
MASTER=${NODES[0]}
WORKERS=("${NODES[@]:1}")
NUM_WORKERS=${#WORKERS[@]}

# RMI configuration
RMI_PORT=1099
WORKER_TIMEOUT=30

# Create results directory
RESULTS_DIR="grid5000_wordcount_results"
mkdir -p "$RESULTS_DIR"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          GRID5000 WORDCOUNT DISTRIBUTED EXECUTION          ║"
echo "╚════════════════════════════════════════════════════════════╝"

echo ""
echo "Configuration:"
echo "  Master: $MASTER"
echo "  Workers: ${WORKERS[@]}"
echo "  Num Workers: $NUM_WORKERS"
echo "  RMI Port: $RMI_PORT"
echo "  Timeout: ${WORKER_TIMEOUT}s"
echo ""

# Create test data on master
echo "[1/5] Creating test data..."

TEST_FILE="$PROJECT_DIR/wordcount_input.txt"

# Generate diverse test data (75000 words)
{
    for i in $(seq 1 10000); do echo -n "distributed "; done
    for i in $(seq 1 15000); do echo -n "wordcount "; done
    for i in $(seq 1 20000); do echo -n "system "; done
    for i in $(seq 1 12000); do echo -n "grid5000 "; done
    for i in $(seq 1 18000); do echo -n "performance "; done
} > "$TEST_FILE"

echo "  Created: $TEST_FILE (75000 words)"

# Start workers on each worker node
echo ""
echo "[2/5] Starting workers on ${NUM_WORKERS} nodes..."

WORKER_PIDS=()

for i in "${!WORKERS[@]}"; do
    WORKER_NODE=${WORKERS[$i]}
    WORKER_PORT=$((RMI_PORT + i))
    
    echo "  Starting worker $((i+1))/$NUM_WORKERS on $WORKER_NODE:$WORKER_PORT..."
    
    # SSH to worker and start java process
    oarsh -n "$WORKER_NODE" "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $WORKER_NODE $WORKER_PORT > /tmp/worker_$i.log 2>&1 &" &
    
    WORKER_PIDS+=($!)
done

# Wait for SSH commands to complete
wait

echo "  Waiting ${WORKER_TIMEOUT}s for workers to be ready..."
sleep "$WORKER_TIMEOUT"

# Verify workers are running
echo "  Verifying workers..."
WORKERS_READY=0

for i in "${!WORKERS[@]}"; do
    WORKER_NODE=${WORKERS[$i]}
    WORKER_PORT=$((RMI_PORT + i))
    
    # Check if worker is listening
    if ssh -n "$WORKER_NODE" "netstat -tuln 2>/dev/null | grep -q :$WORKER_PORT || lsof -i :$WORKER_PORT 2>/dev/null | grep -q java"; then
        echo "    OK: $WORKER_NODE:$WORKER_PORT is ready"
        ((WORKERS_READY++))
    else
        echo "    WARNING: $WORKER_NODE:$WORKER_PORT might not be ready yet"
    fi
done

echo "  Workers ready: $WORKERS_READY/$NUM_WORKERS"
echo ""

# Build worker list for master
WORKER_LIST="["
for i in "${!WORKERS[@]}"; do
    WORKER_NODE=${WORKERS[$i]}
    WORKER_PORT=$((RMI_PORT + i))
    
    if [ $i -gt 0 ]; then
        WORKER_LIST="$WORKER_LIST,"
    fi
    WORKER_LIST="$WORKER_LIST$WORKER_NODE:$WORKER_PORT"
done
WORKER_LIST="$WORKER_LIST]"

echo "[3/5] Executing wordcount on master..."
echo "  Master: $MASTER"
echo "  Input file: $TEST_FILE"
echo "  Workers: $WORKER_LIST"
echo ""

# Run wordcount on master
START_TIME=$(date +%s%N)

cd "$PROJECT_DIR"

# Execute wordcount with dynamic file mode
java -cp bin scheduler.Main "$TEST_FILE" "$WORKER_LIST" 2>&1 | tee "$RESULTS_DIR/execution.log"

END_TIME=$(date +%s%N)
EXECUTION_TIME_MS=$((($END_TIME - $START_TIME) / 1000000))

echo ""
echo "[4/5] Collecting results..."

# Copy results from master
if [ -d "results" ]; then
    cp -r results/* "$RESULTS_DIR/" 2>/dev/null || true
    echo "  Results copied to $RESULTS_DIR"
fi

# Get final result
if [ -f "$RESULTS_DIR/final_result.txt" ]; then
    echo ""
    echo "Final Wordcount Result:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$RESULTS_DIR/final_result.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Create summary
echo ""
echo "[5/5] Execution Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

{
    echo "Grid5000 Wordcount Execution Summary"
    echo "===================================="
    echo ""
    echo "Execution Date: $(date)"
    echo "Master Node: $MASTER"
    echo "Number of Workers: $NUM_WORKERS"
    echo "Worker Nodes: ${WORKERS[@]}"
    echo "RMI Port: $RMI_PORT"
    echo ""
    echo "Input File: $TEST_FILE"
    echo "Execution Time: ${EXECUTION_TIME_MS}ms"
    echo ""
    echo "Results Location: $RESULTS_DIR"
    echo ""
    
    if [ -f "$RESULTS_DIR/final_result.txt" ]; then
        echo "Wordcount Results:"
        cat "$RESULTS_DIR/final_result.txt"
    fi
} | tee "$RESULTS_DIR/summary.txt"

echo ""
echo "Results saved to: $RESULTS_DIR"
echo "  - execution.log: Detailed execution logs"
echo "  - final_result.txt: Final wordcount results"
echo "  - summary.txt: This summary"
echo ""

# Cleanup workers
echo ""
echo "Stopping workers..."

for i in "${!WORKERS[@]}"; do
    WORKER_NODE=${WORKERS[$i]}
    WORKER_PORT=$((RMI_PORT + i))
    
    oarsh -n "$WORKER_NODE" "pkill -f 'java.*network.worker.WorkerNode.*$WORKER_PORT' 2>/dev/null || true" &
done

wait

echo "Workers stopped."
echo ""
echo "Execution complete!"
