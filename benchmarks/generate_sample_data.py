#!/usr/bin/env python3
"""
Génère des données de test pour valider les scripts d'analyse
"""

import os
import numpy as np
import pandas as pd

# Paramètres du modèle (valeurs réalistes)
ALPHA = 0.5      # s/worker
BETA = 1.0       # s
BW_WRITE = 150   # MB/s
V_CPU = 40       # MB/s
N_SAT = 8        # point de saturation
T_OPEN = 5       # ms
C_MERGE = 20     # ms

# Configuration des tests
WORKERS = [1, 2, 4, 8, 16]
SIZES_MB = [10, 50, 100, 500, 1000]
RUNS = 3
NOISE = 0.1  # 10% de bruit

def add_noise(value, noise_level=NOISE):
    """Ajoute du bruit gaussien"""
    return value * (1 + np.random.normal(0, noise_level))

def generate_t_init(output_dir):
    """Génère T_init = α × n + β"""
    rows = []
    for n in WORKERS:
        for run in range(1, RUNS + 1):
            t_ms = add_noise((ALPHA * n + BETA) * 1000)
            rows.append({'run': run, 'workers': n, 'time_ms': t_ms})

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(output_dir, 't_init_sample.csv'), index=False)
    print(f"✓ t_init_sample.csv ({len(df)} lignes)")

def generate_t_split(output_dir):
    """Génère T_split = S / BW_write"""
    rows = []
    for S in SIZES_MB:
        for run in range(1, RUNS + 1):
            t_ms = add_noise((S / BW_WRITE) * 1000)
            rows.append({'run': run, 'size_mb': S, 'time_ms': t_ms})

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(output_dir, 't_split_sample.csv'), index=False)
    print(f"✓ t_split_sample.csv ({len(df)} lignes)")

def generate_t_calc(output_dir):
    """Génère T_calc = S / (min(n, n_sat) × V_cpu)"""
    rows = []
    for n in WORKERS:
        for S in SIZES_MB:
            for run in range(1, RUNS + 1):
                effective_n = min(n, N_SAT)
                t_ms = add_noise((S / (effective_n * V_CPU)) * 1000)
                rows.append({
                    'run': run,
                    'workers': n,
                    'size_mb': S,
                    'time_ms': t_ms
                })

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(output_dir, 't_calc_sample.csv'), index=False)
    print(f"✓ t_calc_sample.csv ({len(df)} lignes)")

def generate_t_merge(output_dir):
    """Génère T_merge = T_open × n + C"""
    rows = []
    for n in WORKERS:
        for run in range(1, RUNS + 1):
            t_ms = add_noise(T_OPEN * n + C_MERGE)
            rows.append({'run': run, 'workers': n, 'time_ms': t_ms})

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(output_dir, 't_merge_sample.csv'), index=False)
    print(f"✓ t_merge_sample.csv ({len(df)} lignes)")

def main():
    output_dir = 'benchmark_results_sample'
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 50)
    print("GÉNÉRATION DE DONNÉES DE TEST")
    print("=" * 50)
    print(f"\nParamètres du modèle:")
    print(f"  α = {ALPHA} s/worker")
    print(f"  β = {BETA} s")
    print(f"  BW_write = {BW_WRITE} MB/s")
    print(f"  V_cpu = {V_CPU} MB/s")
    print(f"  n_sat = {N_SAT}")
    print(f"  T_open = {T_OPEN} ms")
    print(f"  C = {C_MERGE} ms")
    print()

    generate_t_init(output_dir)
    generate_t_split(output_dir)
    generate_t_calc(output_dir)
    generate_t_merge(output_dir)

    print(f"\n✅ Données générées dans: {output_dir}/")
    print(f"\nPour analyser:")
    print(f"  python3 benchmarks/analyze_model.py {output_dir}")

if __name__ == "__main__":
    main()
