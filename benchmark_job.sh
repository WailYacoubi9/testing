#!/bin/bash
#=============================================================================
# Script exécuté par chaque job OAR soumis par launch_campaign.py
#=============================================================================

PROJECT_DIR="$HOME/wordcount-distributed"
CSV_FILE="$PROJECT_DIR/benchmark_results.csv"
ITERATIONS=3

cd "$PROJECT_DIR"

# En-tête du CSV (si n'existe pas)
if [ ! -f "$CSV_FILE" ]; then
    echo "Nodes,Iteration,Launcher_Time_ms,Bootstrap_Time_ms,Split_Time_ms,Distrib_Exec_ms,Total_Time_ms" > "$CSV_FILE"
fi

NODE_COUNT=$(cat $OAR_NODEFILE | uniq | wc -l)
echo "=== Benchmark pour $NODE_COUNT noeuds ($ITERATIONS iterations) ==="

for ((i=1; i<=ITERATIONS; i++)); do
    echo "Iteration $i/$ITERATIONS..."

    # Appel du script de benchmark
    OUTPUT=$(bash deploy/run_nfs_home.sh huge_input.txt 2>&1)

    if echo "$OUTPUT" | grep -q "Execution completed!"; then
        # Parsing des résultats
        T_LAUNCHER=$(echo "$OUTPUT" | grep "LAUNCHER_TIME_MS" | cut -d'=' -f2 | tr -d '\r')
        T_BOOTSTRAP=$(echo "$OUTPUT" | grep "BOOTSTRAP_TIME_MS" | cut -d'=' -f2 | tr -d '\r')
        T_SPLIT=$(echo "$OUTPUT" | grep "FILE_SPLITTED" | awk '{print $3}' | tr -d 'ms')
        T_TOTAL=$(echo "$OUTPUT" | grep "EXECUTION_COMPLETED" | awk '{print $3}' | tr -d 'ms')
        T_EXEC_START=$(echo "$OUTPUT" | grep "DISTRIBUTED_EXECUTION_START" | awk '{print $3}' | tr -d 'ms')
        T_DISTRIB=$((T_TOTAL - T_EXEC_START))

        # Sécurité valeur vide
        [ -z "$T_LAUNCHER" ] && T_LAUNCHER=0
        [ -z "$T_BOOTSTRAP" ] && T_BOOTSTRAP=0
        [ -z "$T_SPLIT" ] && T_SPLIT=0
        [ -z "$T_DISTRIB" ] && T_DISTRIB=0
        [ -z "$T_TOTAL" ] && T_TOTAL=0

        echo "  OK: Launcher=${T_LAUNCHER}ms, Split=${T_SPLIT}ms, Exec=${T_DISTRIB}ms"
        echo "$NODE_COUNT,$i,$T_LAUNCHER,$T_BOOTSTRAP,$T_SPLIT,$T_DISTRIB,$T_TOTAL" >> "$CSV_FILE"
    else
        echo "  ECHEC iteration $i"
        echo "$OUTPUT" > "$PROJECT_DIR/error_${NODE_COUNT}nodes_iter${i}.log"
    fi

    sleep 2
done

echo "=== Benchmark $NODE_COUNT noeuds terminé ==="
