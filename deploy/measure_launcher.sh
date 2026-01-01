#!/bin/bash
#=============================================================================
# MESURE DU TEMPS DE LANCEUR (Initialisation Cluster)
# Mesure les parametres alpha et beta du modele: T_init(n) = alpha * n + beta
#
# Methodologie academique:
# - 30 repetitions par configuration (significativite statistique)
# - Calcul moyenne, ecart-type, intervalle de confiance 95%
# - Regression lineaire pour extraction alpha, beta
#
# Reference: Guide academique de mesure de performance
#=============================================================================

set -e

echo "================================================================"
echo "   MESURE DU TEMPS DE LANCEUR - Parametres alpha, beta          "
echo "================================================================"

PROJECT_DIR="${PROJECT_DIR:-$HOME/wordcount-distributed}"
RESULTS_DIR="$PROJECT_DIR/launcher-results"
mkdir -p "$RESULTS_DIR"

# Fichier de resultats
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTS_DIR/launcher_$TIMESTAMP.csv"
STATS_FILE="$RESULTS_DIR/launcher_stats_$TIMESTAMP.csv"
PARAMS_FILE="$RESULTS_DIR/launcher_params_$TIMESTAMP.txt"

echo "run,num_workers,ssh_start_time,port_ready_time,rmi_connected_time,total_time_s,rmi_time_ms" > "$CSV_FILE"

# Configuration academique - ajuste pour ecotype (17 noeuds = 16 workers max)
WORKER_COUNTS=(1 2 4 8 16)     # Ajuste pour les noeuds disponibles
RUNS=10                        # Reduit pour test initial (augmenter a 30 pour mesure finale)

# Ce script mesure le VRAI temps de lancement:
# 1. SSH + demarrage JVM (ssh ... java WorkerNode)
# 2. Port 3000 ouvert (netstat check)
# 3. Connexion RMI reelle (Naming.lookup + executeCommand)

# Verifier l'environnement Grid5000
if [ -z "$OAR_NODEFILE" ]; then
    echo "ERREUR: Ce script doit etre execute dans une reservation OAR"
    echo "   Utilisez: oarsub -I -l nodes=33,walltime=2:00:00"
    exit 1
fi

# Compter les noeuds disponibles
TOTAL_AVAILABLE=$(cat "$OAR_NODEFILE" | sort -u | wc -l)

# Trouver le nombre maximum de workers demande
MAX_WORKERS_REQUESTED=0
for n in "${WORKER_COUNTS[@]}"; do
    if (( n > MAX_WORKERS_REQUESTED )); then
        MAX_WORKERS_REQUESTED=$n
    fi
done

# Calculer le total requis (Master + Max Workers)
REQUIRED_NODES=$((MAX_WORKERS_REQUESTED + 1))

# Verifier et bloquer si insuffisant
if [ "$TOTAL_AVAILABLE" -lt "$REQUIRED_NODES" ]; then
    echo ""
    echo "ERREUR: Nombre de noeuds insuffisant!"
    echo "  Noeuds reserves: $TOTAL_AVAILABLE"
    echo "  Noeuds requis: $REQUIRED_NODES (1 Master + $MAX_WORKERS_REQUESTED Workers)"
    echo ""
    echo "Solution: oarsub -I -l nodes=$REQUIRED_NODES,walltime=2:00:00"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  Noeuds disponibles: $TOTAL_AVAILABLE"
echo "  Workers a tester: ${WORKER_COUNTS[*]}"
echo "  Repetitions: $RUNS"
echo "  Resultats: $RESULTS_DIR"
echo ""

# Compiler si necessaire
echo "[1/3] Compilation..."
cd "$PROJECT_DIR"
mkdir -p bin
javac -d bin -sourcepath src $(find src -name "*.java") 2>/dev/null || true

# Obtenir la liste des noeuds (FQDN depuis OAR_NODEFILE)
ALL_NODES=$(cat $OAR_NODEFILE | sort -u)
MASTER=$(echo "$ALL_NODES" | head -n 1)

echo "[2/3] Execution des mesures..."
echo "  Master: $MASTER"
echo "  Noeuds disponibles:"
echo "$ALL_NODES" | head -5 | sed 's/^/    /'
if [ $(echo "$ALL_NODES" | wc -l) -gt 5 ]; then
    echo "    ... ($(echo "$ALL_NODES" | wc -l) total)"
fi

for num_workers in "${WORKER_COUNTS[@]}"; do
    # Verifier qu'on a assez de workers
    if [ $num_workers -gt $((TOTAL_AVAILABLE - 1)) ]; then
        echo "  Skip $num_workers workers (max disponible: $((TOTAL_AVAILABLE - 1)))"
        continue
    fi

    echo ""
    echo "--- Test avec $num_workers worker(s) ---"

    # Selectionner les workers pour ce test
    WORKERS=$(echo "$ALL_NODES" | tail -n +2 | head -n $num_workers)

    for run in $(seq 1 $RUNS); do
        echo "  Run $run/$RUNS"

        # Nettoyer les workers precedents
        for hostname in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $hostname "pkill -f WorkerNode 2>/dev/null" </dev/null 2>/dev/null || true
        done
        sleep 1

        # Mesure: Demarrage des workers
        START_TIME=$(date +%s.%N)

        for hostname in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $hostname "cd $PROJECT_DIR && nohup java -cp bin network.worker.WorkerNode $hostname 3000 > /tmp/worker.log 2>&1 &" </dev/null 2>/dev/null
        done

        # Attendre que tous les workers soient prets (port 3000 ouvert)
        all_ready=false
        timeout_counter=0
        while [ "$all_ready" = false ] && [ $timeout_counter -lt 60 ]; do
            ready_count=0
            for hostname in $WORKERS; do
                if ssh -o StrictHostKeyChecking=no -o BatchMode=yes $hostname "netstat -ln 2>/dev/null | grep -q :3000" </dev/null 2>/dev/null; then
                    ready_count=$((ready_count + 1))
                fi
            done

            if [ $ready_count -eq $num_workers ]; then
                all_ready=true
            else
                sleep 0.5
                timeout_counter=$((timeout_counter + 1))
            fi
        done

        PORT_READY_TIME=$(date +%s.%N)

        if [ "$all_ready" = false ]; then
            echo "    TIMEOUT"
            continue
        fi

        # ===========================================
        # MESURE RMI REELLE: Naming.lookup + executeCommand
        # ===========================================
        # Construire la liste des workers pour le benchmark Java
        WORKER_ARGS=""
        for hostname in $WORKERS; do
            WORKER_ARGS="$WORKER_ARGS $hostname:3000"
        done

        # Executer le benchmark RMI reel
        RMI_OUTPUT=$(java -cp bin benchmark.LauncherBenchmark $WORKER_ARGS 2>/dev/null | grep "^RESULT:" | cut -d':' -f2)

        RMI_CONNECTED_TIME=$(date +%s.%N)

        # Extraire le temps RMI en ms
        if [ -n "$RMI_OUTPUT" ]; then
            RMI_TIME_MS=$(echo "$RMI_OUTPUT" | cut -d',' -f3)
            echo "    OK (${RMI_TIME_MS}ms)"
        else
            RMI_TIME_MS="0"
            echo "    FAILED"
        fi

        # Calculer le temps total (SSH start -> RMI connected)
        TOTAL_TIME=$(echo "$RMI_CONNECTED_TIME - $START_TIME" | bc)

        # Ecrire dans CSV
        echo "$run,$num_workers,$START_TIME,$PORT_READY_TIME,$RMI_CONNECTED_TIME,$TOTAL_TIME,$RMI_TIME_MS" >> "$CSV_FILE"

        # Nettoyer
        for hostname in $WORKERS; do
            ssh -o StrictHostKeyChecking=no -o BatchMode=yes $hostname "pkill -f WorkerNode 2>/dev/null" </dev/null 2>/dev/null || true
        done

        sleep 1
    done
done

# ============================================================================
# PHASE 3: CALCUL DES STATISTIQUES
# ============================================================================

echo ""
echo "[3/3] Calcul des statistiques..."

# Calculer les statistiques par nombre de workers
echo "num_workers,mean_time_s,std_time_s,ci95_low,ci95_high,count" > "$STATS_FILE"

for num_workers in "${WORKER_COUNTS[@]}"; do
    # Extraire les temps pour ce nombre de workers (colonne 6 = total_time_s)
    DATA=$(grep ",$num_workers," "$CSV_FILE" | cut -d',' -f6)

    if [ -z "$DATA" ]; then
        continue
    fi

    # Calculer avec awk
    STATS=$(echo "$DATA" | awk '
    {
        sum += $1
        sumsq += $1 * $1
        count++
        values[count] = $1
    }
    END {
        if (count == 0) exit
        mean = sum / count
        if (count > 1) {
            variance = (sumsq - sum*sum/count) / (count - 1)
            stddev = sqrt(variance)
        } else {
            stddev = 0
        }
        stderr = stddev / sqrt(count)
        ci95 = 1.96 * stderr
        ci_low = mean - ci95
        ci_high = mean + ci95
        printf "%.4f,%.4f,%.4f,%.4f,%d", mean, stddev, ci_low, ci_high, count
    }')

    echo "$num_workers,$STATS" >> "$STATS_FILE"
done

# Regression lineaire pour extraire alpha et beta
echo ""
echo "Calcul de la regression lineaire: T_init(n) = alpha * n + beta"

REGRESSION=$(cat "$STATS_FILE" | tail -n +2 | awk -F',' '
{
    n = $1
    t = $2
    sum_n += n
    sum_t += t
    sum_nt += n * t
    sum_nn += n * n
    count++
}
END {
    if (count < 2) {
        print "0,0,0"
        exit
    }
    alpha = (count * sum_nt - sum_n * sum_t) / (count * sum_nn - sum_n * sum_n)
    beta = (sum_t - alpha * sum_n) / count

    # R² (coefficient de determination)
    mean_t = sum_t / count
    ss_tot = 0
    ss_res = 0
}
{
    predicted = alpha * $1 + beta
    ss_res += ($2 - predicted)^2
    ss_tot += ($2 - mean_t)^2
}
END {
    if (ss_tot > 0) {
        r_squared = 1 - ss_res / ss_tot
    } else {
        r_squared = 1
    }
    printf "%.4f,%.4f,%.4f", alpha, beta, r_squared
}')

ALPHA=$(echo $REGRESSION | cut -d',' -f1)
BETA=$(echo $REGRESSION | cut -d',' -f2)
R_SQUARED=$(echo $REGRESSION | cut -d',' -f3)

# Sauvegarder les parametres
cat > "$PARAMS_FILE" << EOF
# Parametres d'initialisation pour le modele theorique
# Mesures REELLES sur Grid5000
# Date: $(date)
#
# Mesure COMPLETE du temps de lancement:
# - SSH vers chaque worker
# - Demarrage JVM + WorkerNode
# - Enregistrement RMI registry (port 3000)
# - Connexion RMI reelle depuis le master (Naming.lookup)
# - Verification connexion (executeCommand)
#
# Regression: T_init(n) = alpha * n + beta

alpha = $ALPHA
beta = $BETA
r_squared = $R_SQUARED

# Interpretation:
# - alpha: temps additionnel par worker (SSH + JVM + RMI)
# - beta: overhead fixe (compilation, setup master)
EOF

# ============================================================================
# AFFICHAGE DES RESULTATS
# ============================================================================

echo ""
echo "================================================================"
echo "       RESULTATS (Mesure RMI REELLE)                             "
echo "================================================================"
echo ""
echo "Statistiques par nombre de workers:"
echo ""
cat "$STATS_FILE" | column -t -s','
echo ""
echo "----------------------------------------------------------------"
echo "PARAMETRES DU MODELE (regression lineaire):"
echo ""
echo "  T_init(n) = $ALPHA * n + $BETA"
echo ""
echo "  alpha = $ALPHA secondes/worker"
echo "  beta  = $BETA secondes (overhead fixe)"
echo "  R²    = $R_SQUARED"
echo "----------------------------------------------------------------"
echo ""
echo "Fichiers generes:"
echo "  Donnees brutes: $CSV_FILE"
echo "  Statistiques:   $STATS_FILE"
echo "  Parametres:     $PARAMS_FILE"
echo ""
