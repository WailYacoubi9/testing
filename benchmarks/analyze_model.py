#!/usr/bin/env python3
"""
=============================================================================
ANALYSE ET VISUALISATION DU MODÈLE THÉORIQUE
T_total = T_init + T_split + T_calc + T_merge
=============================================================================
"""

import os
import sys
import glob
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy import stats
from scipy.optimize import curve_fit

# Style des graphiques
plt.style.use('seaborn-v0_8-whitegrid')
COLORS = ['#2ecc71', '#3498db', '#e74c3c', '#9b59b6', '#f39c12']

def load_data(results_dir):
    """Charge tous les fichiers CSV de résultats"""
    data = {}

    # T_init
    init_files = glob.glob(os.path.join(results_dir, "t_init_*.csv"))
    if init_files:
        data['t_init'] = pd.read_csv(sorted(init_files)[-1])
        print(f"✓ T_init: {len(data['t_init'])} mesures")

    # T_split
    split_files = glob.glob(os.path.join(results_dir, "t_split_*.csv"))
    if split_files:
        data['t_split'] = pd.read_csv(sorted(split_files)[-1])
        print(f"✓ T_split: {len(data['t_split'])} mesures")

    # T_calc
    calc_files = glob.glob(os.path.join(results_dir, "t_calc_*.csv"))
    if calc_files:
        data['t_calc'] = pd.read_csv(sorted(calc_files)[-1])
        print(f"✓ T_calc: {len(data['t_calc'])} mesures")

    # T_merge
    merge_files = glob.glob(os.path.join(results_dir, "t_merge_*.csv"))
    if merge_files:
        data['t_merge'] = pd.read_csv(sorted(merge_files)[-1])
        print(f"✓ T_merge: {len(data['t_merge'])} mesures")

    return data


def analyze_t_init(df):
    """
    Analyse T_init(n) = α × n + β
    Retourne alpha, beta, R²
    """
    # Grouper par nombre de workers
    grouped = df.groupby('workers')['time_ms'].agg(['mean', 'std', 'count']).reset_index()

    n = grouped['workers'].values
    t = grouped['mean'].values / 1000  # Convertir en secondes

    # Régression linéaire
    slope, intercept, r_value, p_value, std_err = stats.linregress(n, t)

    return {
        'alpha': slope,
        'beta': intercept,
        'r_squared': r_value**2,
        'data': grouped
    }


def analyze_t_split(df):
    """
    Analyse T_split(S) = S / BW_write
    Retourne BW_write
    """
    grouped = df.groupby('size_mb')['time_ms'].agg(['mean', 'std', 'count']).reset_index()

    S = grouped['size_mb'].values
    t = grouped['mean'].values / 1000  # Convertir en secondes

    # BW = S / t
    BW_values = S / t
    BW_write = np.mean(BW_values)

    return {
        'BW_write': BW_write,
        'data': grouped
    }


def analyze_t_calc(df):
    """
    Analyse T_calc(n, S) = S / (min(n, n_sat) × V_cpu) + n × T_rmi
    """
    # Grouper par (workers, size_mb)
    grouped = df.groupby(['workers', 'size_mb'])['time_ms'].agg(['mean', 'std', 'count']).reset_index()

    # Estimer V_cpu pour chaque configuration
    grouped['t_sec'] = grouped['mean'] / 1000
    grouped['throughput'] = grouped['size_mb'] / grouped['t_sec']  # MB/s par worker
    grouped['throughput_per_worker'] = grouped['throughput'] / grouped['workers']

    # V_cpu moyen
    V_cpu = grouped['throughput_per_worker'].mean()

    # Détecter saturation: quand ajouter des workers n'améliore plus
    # Grouper par size et regarder si throughput plafonne
    n_sat = None
    for size in grouped['size_mb'].unique():
        subset = grouped[grouped['size_mb'] == size].sort_values('workers')
        throughputs = subset['throughput'].values

        # Chercher le point où le throughput ne double plus
        for i in range(1, len(throughputs)):
            ratio = throughputs[i] / throughputs[i-1]
            workers_ratio = subset['workers'].iloc[i] / subset['workers'].iloc[i-1]
            efficiency = ratio / workers_ratio

            if efficiency < 0.5:  # Moins de 50% d'efficacité
                n_sat = subset['workers'].iloc[i-1]
                break

    return {
        'V_cpu': V_cpu,
        'n_sat': n_sat,
        'data': grouped
    }


def analyze_t_merge(df):
    """
    Analyse T_merge(n) = n × T_open + C
    """
    grouped = df.groupby('workers')['time_ms'].agg(['mean', 'std', 'count']).reset_index()

    n = grouped['workers'].values
    t = grouped['mean'].values  # En ms

    # Régression linéaire
    slope, intercept, r_value, p_value, std_err = stats.linregress(n, t)

    return {
        'T_open': slope,
        'C': intercept,
        'r_squared': r_value**2,
        'data': grouped
    }


def plot_t_init(results, output_dir):
    """Trace T_init(n) avec la régression"""
    fig, ax = plt.subplots(figsize=(10, 6))

    data = results['data']
    n = data['workers'].values
    t_mean = data['mean'].values / 1000  # Secondes
    t_std = data['std'].values / 1000

    # Points mesurés
    ax.errorbar(n, t_mean, yerr=t_std, fmt='o', markersize=10,
                capsize=5, color=COLORS[0], label='Mesures')

    # Régression
    n_fit = np.linspace(0, max(n) * 1.1, 100)
    t_fit = results['alpha'] * n_fit + results['beta']
    ax.plot(n_fit, t_fit, '--', color=COLORS[1], linewidth=2,
            label=f'Modèle: T = {results["alpha"]:.3f}×n + {results["beta"]:.3f}')

    ax.set_xlabel('Nombre de Workers (n)', fontsize=12)
    ax.set_ylabel('T_init (secondes)', fontsize=12)
    ax.set_title(f'T_init(n) = α×n + β\nR² = {results["r_squared"]:.4f}', fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 't_init.png'), dpi=150)
    plt.savefig(os.path.join(output_dir, 't_init.pdf'))
    print(f"  → t_init.png/pdf")


def plot_t_split(results, output_dir):
    """Trace T_split(S)"""
    fig, ax = plt.subplots(figsize=(10, 6))

    data = results['data']
    S = data['size_mb'].values
    t_mean = data['mean'].values / 1000  # Secondes
    t_std = data['std'].values / 1000

    # Points mesurés
    ax.errorbar(S, t_mean, yerr=t_std, fmt='s', markersize=10,
                capsize=5, color=COLORS[2], label='Mesures')

    # Modèle
    S_fit = np.linspace(0, max(S) * 1.1, 100)
    t_fit = S_fit / results['BW_write']
    ax.plot(S_fit, t_fit, '--', color=COLORS[3], linewidth=2,
            label=f'Modèle: T = S / {results["BW_write"]:.1f} MB/s')

    ax.set_xlabel('Taille du fichier S (MB)', fontsize=12)
    ax.set_ylabel('T_split (secondes)', fontsize=12)
    ax.set_title(f'T_split(S) = S / BW_write\nBW_write = {results["BW_write"]:.1f} MB/s', fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 't_split.png'), dpi=150)
    plt.savefig(os.path.join(output_dir, 't_split.pdf'))
    print(f"  → t_split.png/pdf")


def plot_t_calc(results, output_dir):
    """Trace T_calc(n, S) - heatmap et courbes"""
    data = results['data']

    # 1. Courbes pour différentes tailles
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    sizes = sorted(data['size_mb'].unique())
    for i, size in enumerate(sizes):
        subset = data[data['size_mb'] == size].sort_values('workers')
        ax1.plot(subset['workers'], subset['mean']/1000, 'o-',
                 color=COLORS[i % len(COLORS)], markersize=8,
                 label=f'{size} MB')

    ax1.set_xlabel('Nombre de Workers (n)', fontsize=12)
    ax1.set_ylabel('T_calc (secondes)', fontsize=12)
    ax1.set_title('T_calc vs Workers (par taille)', fontsize=14)
    ax1.legend(fontsize=10)
    ax1.grid(True, alpha=0.3)

    # 2. Speedup
    for i, size in enumerate(sizes):
        subset = data[data['size_mb'] == size].sort_values('workers')
        t1 = subset[subset['workers'] == subset['workers'].min()]['mean'].values[0]
        speedup = t1 / subset['mean'].values
        ax2.plot(subset['workers'], speedup, 'o-',
                 color=COLORS[i % len(COLORS)], markersize=8,
                 label=f'{size} MB')

    # Ligne idéale
    max_workers = data['workers'].max()
    ax2.plot([1, max_workers], [1, max_workers], 'k--', alpha=0.5, label='Idéal')

    if results['n_sat']:
        ax2.axvline(x=results['n_sat'], color='red', linestyle=':',
                    label=f'Saturation (n={results["n_sat"]})')

    ax2.set_xlabel('Nombre de Workers (n)', fontsize=12)
    ax2.set_ylabel('Speedup', fontsize=12)
    ax2.set_title('Speedup vs Workers', fontsize=14)
    ax2.legend(fontsize=10)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 't_calc.png'), dpi=150)
    plt.savefig(os.path.join(output_dir, 't_calc.pdf'))
    print(f"  → t_calc.png/pdf")


def plot_t_merge(results, output_dir):
    """Trace T_merge(n)"""
    fig, ax = plt.subplots(figsize=(10, 6))

    data = results['data']
    n = data['workers'].values
    t_mean = data['mean'].values  # En ms
    t_std = data['std'].values

    # Points mesurés
    ax.errorbar(n, t_mean, yerr=t_std, fmt='^', markersize=10,
                capsize=5, color=COLORS[4], label='Mesures')

    # Régression
    n_fit = np.linspace(0, max(n) * 1.1, 100)
    t_fit = results['T_open'] * n_fit + results['C']
    ax.plot(n_fit, t_fit, '--', color=COLORS[0], linewidth=2,
            label=f'Modèle: T = {results["T_open"]:.2f}×n + {results["C"]:.2f}')

    ax.set_xlabel('Nombre de Workers (n)', fontsize=12)
    ax.set_ylabel('T_merge (ms)', fontsize=12)
    ax.set_title(f'T_merge(n) = T_open×n + C\nR² = {results["r_squared"]:.4f}', fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 't_merge.png'), dpi=150)
    plt.savefig(os.path.join(output_dir, 't_merge.pdf'))
    print(f"  → t_merge.png/pdf")


def plot_total_model(all_results, output_dir):
    """Trace le modèle complet avec décomposition - VERSION CORRIGÉE"""
    fig, axes = plt.subplots(2, 2, figsize=(14, 12))

    # Paramètres du modèle
    alpha = all_results.get('t_init', {}).get('alpha', 0.5)
    beta = all_results.get('t_init', {}).get('beta', 1.0)
    BW_write = all_results.get('t_split', {}).get('BW_write', 100)
    V_cpu = all_results.get('t_calc', {}).get('V_cpu', 50)
    BW_nfs = 200  # MB/s - à calibrer
    T_rmi = 0.05  # secondes - constant (appels parallèles!)
    C_merge = 0.02  # secondes - constant

    workers = np.array([1, 2, 4, 8, 16, 32])
    sizes = [100, 500, 1000]

    def V_eff(n):
        """Vitesse effective avec saturation NFS"""
        return np.minimum(V_cpu, BW_nfs / n)

    # 1. Décomposition par composante (S fixe)
    ax1 = axes[0, 0]
    S = 500  # MB fixe

    t_init = alpha * workers + beta
    t_split = np.ones_like(workers, dtype=float) * (S / BW_write)
    t_calc = S / (workers * V_eff(workers)) + T_rmi  # CORRIGÉ: T_rmi constant
    t_merge = np.ones_like(workers, dtype=float) * C_merge

    width = 0.6
    ax1.bar(workers, t_init, width, label='T_init', color=COLORS[0])
    ax1.bar(workers, t_split, width, bottom=t_init, label='T_split', color=COLORS[1])
    ax1.bar(workers, t_calc, width, bottom=t_init+t_split, label='T_calc', color=COLORS[2])
    ax1.bar(workers, t_merge, width, bottom=t_init+t_split+t_calc, label='T_merge', color=COLORS[3])

    ax1.set_xlabel('Workers', fontsize=12)
    ax1.set_ylabel('Temps (s)', fontsize=12)
    ax1.set_title(f'Décomposition T_total (S={S}MB)', fontsize=14)
    ax1.legend()
    ax1.set_xticks(workers)

    # 2. T_total vs Workers (différentes tailles)
    ax2 = axes[0, 1]
    for i, S in enumerate(sizes):
        t_init = alpha * workers + beta
        t_split = S / BW_write
        t_calc = S / (workers * V_eff(workers)) + T_rmi
        t_merge = C_merge
        t_total = t_init + t_split + t_calc + t_merge

        ax2.plot(workers, t_total, 'o-', color=COLORS[i], markersize=8, label=f'{S} MB')

    ax2.set_xlabel('Workers', fontsize=12)
    ax2.set_ylabel('T_total (s)', fontsize=12)
    ax2.set_title('T_total vs Workers', fontsize=14)
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    # 3. Speedup
    ax3 = axes[1, 0]
    for i, S in enumerate(sizes):
        t_init = alpha * workers + beta
        t_split = S / BW_write
        t_calc = S / (workers * V_eff(workers)) + T_rmi
        t_merge = C_merge
        t_total = t_init + t_split + t_calc + t_merge

        # T(1)
        t_1 = alpha * 1 + beta + S / BW_write + S / V_cpu + T_rmi + C_merge
        speedup = t_1 / t_total

        ax3.plot(workers, speedup, 'o-', color=COLORS[i], markersize=8, label=f'{S} MB')

    ax3.plot(workers, workers, 'k--', alpha=0.5, label='Idéal')

    # Point de saturation: n_sat = BW_nfs / V_cpu
    n_sat = BW_nfs / V_cpu
    if n_sat < max(workers):
        ax3.axvline(x=n_sat, color='red', linestyle=':', label=f'Saturation n≈{n_sat:.0f}')

    ax3.set_xlabel('Workers', fontsize=12)
    ax3.set_ylabel('Speedup', fontsize=12)
    ax3.set_title('Speedup S(n) = T(1)/T(n)', fontsize=14)
    ax3.legend()
    ax3.grid(True, alpha=0.3)

    # 4. Efficacité
    ax4 = axes[1, 1]
    for i, S in enumerate(sizes):
        t_init = alpha * workers + beta
        t_split = S / BW_write
        t_calc = S / (workers * V_eff(workers)) + T_rmi
        t_merge = C_merge
        t_total = t_init + t_split + t_calc + t_merge

        t_1 = alpha * 1 + beta + S / BW_write + S / V_cpu + T_rmi + C_merge
        speedup = t_1 / t_total
        efficiency = speedup / workers * 100

        ax4.plot(workers, efficiency, 'o-', color=COLORS[i], markersize=8, label=f'{S} MB')

    ax4.axhline(y=100, color='k', linestyle='--', alpha=0.5, label='Idéal (100%)')
    ax4.axhline(y=50, color='orange', linestyle=':', alpha=0.5, label='50%')
    ax4.set_xlabel('Workers', fontsize=12)
    ax4.set_ylabel('Efficacité (%)', fontsize=12)
    ax4.set_title('Efficacité E(n) = S(n)/n', fontsize=14)
    ax4.legend()
    ax4.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'model_complete.png'), dpi=150)
    plt.savefig(os.path.join(output_dir, 'model_complete.pdf'))
    print(f"  → model_complete.png/pdf")


def print_model_parameters(all_results, output_dir):
    """Affiche et sauvegarde les paramètres du modèle"""

    params = []
    params.append("=" * 70)
    params.append("PARAMÈTRES DU MODÈLE THÉORIQUE")
    params.append("=" * 70)
    params.append("")

    # T_init
    if 't_init' in all_results:
        r = all_results['t_init']
        params.append("T_init(n) = α × n + β")
        params.append(f"  α = {r['alpha']:.4f} s/worker")
        params.append(f"  β = {r['beta']:.4f} s")
        params.append(f"  R² = {r['r_squared']:.4f}")
        params.append("")

    # T_split
    if 't_split' in all_results:
        r = all_results['t_split']
        params.append("T_split(S) = S / BW_write")
        params.append(f"  BW_write = {r['BW_write']:.2f} MB/s")
        params.append("")

    # T_calc
    if 't_calc' in all_results:
        r = all_results['t_calc']
        params.append("T_calc(n, S) = S / (min(n, n_sat) × V_cpu)")
        params.append(f"  V_cpu = {r['V_cpu']:.2f} MB/s")
        if r['n_sat']:
            params.append(f"  n_sat = {r['n_sat']} workers (saturation NFS)")
        params.append("")

    # T_merge
    if 't_merge' in all_results:
        r = all_results['t_merge']
        params.append("T_merge(n) = T_open × n + C")
        params.append(f"  T_open = {r['T_open']:.4f} ms/fichier")
        params.append(f"  C = {r['C']:.4f} ms")
        params.append(f"  R² = {r['r_squared']:.4f}")
        params.append("")

    params.append("=" * 70)
    params.append("FORMULE COMPLÈTE")
    params.append("=" * 70)
    params.append("")
    params.append("T_total(n, S) = T_init(n) + T_split(S) + T_calc(n, S) + T_merge(n)")
    params.append("")

    # Afficher
    for line in params:
        print(line)

    # Sauvegarder
    with open(os.path.join(output_dir, 'model_parameters.txt'), 'w') as f:
        f.write('\n'.join(params))

    print(f"\n  → model_parameters.txt")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_model.py <results_dir>")
        print("Example: python3 analyze_model.py benchmark_results")
        sys.exit(1)

    results_dir = sys.argv[1]

    if not os.path.exists(results_dir):
        print(f"Erreur: Répertoire '{results_dir}' non trouvé")
        sys.exit(1)

    print("=" * 70)
    print("ANALYSE DU MODÈLE THÉORIQUE")
    print("=" * 70)
    print()

    # Charger les données
    print("[1/4] Chargement des données...")
    data = load_data(results_dir)

    if not data:
        print("Erreur: Aucune donnée trouvée")
        sys.exit(1)

    # Analyser chaque composante
    print("\n[2/4] Analyse des composantes...")
    all_results = {}

    if 't_init' in data:
        all_results['t_init'] = analyze_t_init(data['t_init'])
        print(f"  T_init: α={all_results['t_init']['alpha']:.4f}, β={all_results['t_init']['beta']:.4f}")

    if 't_split' in data:
        all_results['t_split'] = analyze_t_split(data['t_split'])
        print(f"  T_split: BW_write={all_results['t_split']['BW_write']:.2f} MB/s")

    if 't_calc' in data:
        all_results['t_calc'] = analyze_t_calc(data['t_calc'])
        print(f"  T_calc: V_cpu={all_results['t_calc']['V_cpu']:.2f} MB/s")

    if 't_merge' in data:
        all_results['t_merge'] = analyze_t_merge(data['t_merge'])
        print(f"  T_merge: T_open={all_results['t_merge']['T_open']:.4f} ms")

    # Générer les graphiques
    print("\n[3/4] Génération des graphiques...")

    if 't_init' in all_results:
        plot_t_init(all_results['t_init'], results_dir)

    if 't_split' in all_results:
        plot_t_split(all_results['t_split'], results_dir)

    if 't_calc' in all_results:
        plot_t_calc(all_results['t_calc'], results_dir)

    if 't_merge' in all_results:
        plot_t_merge(all_results['t_merge'], results_dir)

    # Modèle complet
    if len(all_results) >= 2:
        plot_total_model(all_results, results_dir)

    # Afficher les paramètres
    print("\n[4/4] Paramètres du modèle...")
    print_model_parameters(all_results, results_dir)

    print("\n" + "=" * 70)
    print("ANALYSE TERMINÉE")
    print("=" * 70)
    print(f"\nGraphiques sauvegardés dans: {results_dir}/")


if __name__ == "__main__":
    main()
