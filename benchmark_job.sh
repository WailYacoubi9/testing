#!/bin/bash

PROJECT_DIR="$HOME/wordcount-distributed"
INPUT_FILE="huge_input.txt" # Assure-toi que ce fichier existe !
CSV_FILE="$PROJECT_DIR/benchmark_results.csv"
ITERATIONS=3

cd "$PROJECT_DIR"

# En-tête du CSV
if [ ! -f "$CSV_FILE" ]; then
    echo "Nodes,Iteration,Launcher_Time_ms,Bootstrap_Time_ms,Split_Time_ms,Distrib_Exec_ms,Total_Time_ms" > "$CSV_FILE"
fi

NODE_COUNT=$(cat $OAR_NODEFILE | uniq | wc -l)
echo "Demarrage du benchmark pour $NODE_COUNT noeuds ($ITERATIONS iterations)"

for ((i=1; i<=ITERATIONS; i++)); do
    echo "------------------------------------------------"
    echo "Iteration $i/$ITERATIONS sur $NODE_COUNT noeuds..."

    # Appel du script qui fait le vrai travail (deploy/run_nfs_home.sh)
    OUTPUT=$(bash deploy/run_nfs_home.sh "$INPUT_FILE" 2>&1)

    if echo "$OUTPUT" | grep -q "Execution completed!"; then

        # Parsing des résultats
        T_LAUNCHER=$(echo "$OUTPUT" | grep "LAUNCHER_TIME_MS" | cut -d'=' -f2 | tr -d '\r')
        T_BOOTSTRAP=$(echo "$OUTPUT" | grep "BOOTSTRAP_TIME_MS" | cut -d'=' -f2 | tr -d '\r')

        # On utilise TIMING REPORT pour récupérer les durées exactes
        # On extrait la colonne qui contient "ms" et on enlève "ms"
        T_SPLIT=$(echo "$OUTPUT" | grep "FILE_SPLITTED" | awk '{print $3}' | tr -d 'ms')

        # Pour Total_Time, on prend EXECUTION_COMPLETED
        T_TOTAL=$(echo "$OUTPUT" | grep "EXECUTION_COMPLETED" | awk '{print $3}' | tr -d 'ms')

        # Pour le calcul distribué (Exec - Start Exec)
        T_EXEC_START=$(echo "$OUTPUT" | grep "DISTRIBUTED_EXECUTION_START" | awk '{print $3}' | tr -d 'ms')
        T_DISTRIB=$((T_TOTAL - T_EXEC_START))

        # Sécurité valeur vide
        [ -z "$T_LAUNCHER" ] && T_LAUNCHER=0
        [ -z "$T_BOOTSTRAP" ] && T_BOOTSTRAP=0
        [ -z "$T_SPLIT" ] && T_SPLIT=0
        [ -z "$T_DISTRIB" ] && T_DISTRIB=0
        [ -z "$T_TOTAL" ] && T_TOTAL=0

        echo "Succes : Launcher=${T_LAUNCHER}ms, Bootstrap=${T_BOOTSTRAP}ms, Split=${T_SPLIT}ms, Exec=${T_DISTRIB}ms"
        echo "$NODE_COUNT,$i,$T_LAUNCHER,$T_BOOTSTRAP,$T_SPLIT,$T_DISTRIB,$T_TOTAL" >> "$CSV_FILE"
    else
        echo "Echec iteration $i"
        echo "$OUTPUT" > "error_log_${NODE_COUNT}_nodes_iter_${i}.txt"
    fi

    # Pause et nettoyage
    sleep 5
done

echo "Benchmark termine."
