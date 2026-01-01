#!/bin/bash
#=============================================================================
# MESURE DU TEMPS DE LANCEUR - Version simplifiee
# T_init(n) = alpha * n + beta
#=============================================================================

# Force immediate output
exec > >(tee -a /tmp/measure_launcher.log) 2>&1

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/launcher-results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/launcher_$TIMESTAMP.csv"

echo "========================================"
echo "MESURE T_init - $(date)"
echo "========================================"

# Check OAR
if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Pas de reservation OAR"
    exit 1
fi

# Get nodes
ALL_NODES=$(cat $OAR_NODEFILE | sort -u)
MASTER=$(echo "$ALL_NODES" | head -n 1)
TOTAL=$(echo "$ALL_NODES" | wc -l)

echo "Master: $MASTER"
echo "Total nodes: $TOTAL"

# Compile
echo ""
echo "Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

# CSV header
echo "run,workers,time_s,rmi_ms" > "$CSV_FILE"

# Configuration
WORKER_COUNTS=(1 2 4 8)
RUNS=3

echo ""
echo "Config: workers=${WORKER_COUNTS[*]}, runs=$RUNS"
echo ""

# SSH function - truly non-blocking
ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 "$@" </dev/null 2>/dev/null
}

for n in "${WORKER_COUNTS[@]}"; do
    # Check if we have enough workers
    if [ $n -ge $TOTAL ]; then
        echo "Skip $n workers (only $((TOTAL-1)) available)"
        continue
    fi

    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $n)

    echo "=== $n worker(s) ==="

    for run in $(seq 1 $RUNS); do
        # Cleanup
        for h in $WORKERS; do
            ssh_cmd $h "pkill -f WorkerNode" &
        done
        wait
        sleep 1

        # Start workers and measure
        START=$(date +%s.%N)

        for h in $WORKERS; do
            ssh_cmd $h "cd $PROJECT_DIR && java -cp bin network.worker.WorkerNode $h 3000 > /tmp/worker.log 2>&1 &"
        done

        # Wait for ports (simple polling)
        for i in {1..30}; do
            ready=0
            for h in $WORKERS; do
                if ssh_cmd $h "netstat -ln | grep -q :3000"; then
                    ready=$((ready + 1))
                fi
            done
            if [ $ready -eq $n ]; then
                break
            fi
            sleep 0.3
        done

        # RMI test
        WORKER_ARGS=""
        for h in $WORKERS; do
            WORKER_ARGS="$WORKER_ARGS $h:3000"
        done

        RMI_OUT=$(java -cp bin benchmark.LauncherBenchmark $WORKER_ARGS 2>/dev/null | grep "^RESULT:" | cut -d':' -f2)

        END=$(date +%s.%N)
        TOTAL_TIME=$(echo "$END - $START" | bc)
        RMI_MS=$(echo "$RMI_OUT" | cut -d',' -f3)
        [ -z "$RMI_MS" ] && RMI_MS="0"

        echo "  Run $run: ${TOTAL_TIME}s (RMI: ${RMI_MS}ms)"
        echo "$run,$n,$TOTAL_TIME,$RMI_MS" >> "$CSV_FILE"

        # Cleanup
        for h in $WORKERS; do
            ssh_cmd $h "pkill -f WorkerNode" &
        done
        wait
        sleep 0.5
    done
done

echo ""
echo "========================================"
echo "RESULTATS"
echo "========================================"

# Calculate stats per worker count
echo ""
echo "Moyennes par nombre de workers:"
for n in "${WORKER_COUNTS[@]}"; do
    DATA=$(grep ",$n," "$CSV_FILE" | cut -d',' -f3)
    if [ -n "$DATA" ]; then
        AVG=$(echo "$DATA" | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count}')
        echo "  $n workers: ${AVG}s"
    fi
done

# Simple linear regression
echo ""
echo "Regression lineaire:"
awk -F',' 'NR>1 {
    n=$2; t=$3
    sum_n+=n; sum_t+=t; sum_nt+=n*t; sum_nn+=n*n; count++
}
END {
    if(count>=2) {
        alpha = (count*sum_nt - sum_n*sum_t) / (count*sum_nn - sum_n*sum_n)
        beta = (sum_t - alpha*sum_n) / count
        printf "  T_init(n) = %.4f * n + %.4f\n", alpha, beta
        printf "  alpha = %.4f s/worker\n", alpha
        printf "  beta = %.4f s\n", beta
    }
}' "$CSV_FILE"

echo ""
echo "CSV: $CSV_FILE"
echo "Log: /tmp/measure_launcher.log"
echo "Done!"
