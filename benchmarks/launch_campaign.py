#!/usr/bin/env python3
import subprocess
import time
import os
import sys

TARGET_CLUSTER = "ecotype"
NODE_COUNTS = [2,3,6,8,11,13,15,18]
WALLTIME = "00:30:00"

HOME_DIR = os.environ['HOME']
SCRIPT_PATH = f"{HOME_DIR}/wordcount-distributed/benchmark_job.sh"

def main():
    print(f"Lancement de la campagne de benchmark")
    print(f"Cluster cible : {TARGET_CLUSTER if TARGET_CLUSTER else 'AUTO (Melange possible)'}")
    print(f"Configurations : {NODE_COUNTS} noeuds")
    print(f"Script : {SCRIPT_PATH}")
    print("-" * 60)

    if not os.path.exists(SCRIPT_PATH):
        print(f"Erreur : Le fichier {SCRIPT_PATH} n'existe pas.")
        sys.exit(1)

    for nodes in NODE_COUNTS:
        cmd = ["/usr/bin/oarsub"]

        if TARGET_CLUSTER:
            cmd.extend(["-p", f"cluster='{TARGET_CLUSTER}'"])

        cmd.extend(["-l", f"nodes={nodes},walltime={WALLTIME}"])

        cmd.append(SCRIPT_PATH)

        print(f"Soumission pour {nodes} noeuds ({TARGET_CLUSTER if TARGET_CLUSTER else 'any'})...", end=" ")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                output_lines = result.stdout.splitlines()
                job_id = "Inconnu"
                for line in output_lines:
                    if "OAR_JOB_ID" in line:
                        job_id = line.split("=")[1]

                print(f"OK (Job ID: {job_id})")
            else:
                print("ERREUR OAR")
                print(f"   Commande: {' '.join(cmd)}")
                print(f"   Stderr: {result.stderr.strip()}")

        except Exception as e:
            print(f"Exception Python: {e}")

        time.sleep(1)

    print("-" * 60)
    print("Campagne lancee !")
    print(f"Suivi : oarstat -u {os.environ['USER']}")
    print(f"Resultats : tail -f benchmark_results.csv")

if __name__ == "__main__":
    main()
