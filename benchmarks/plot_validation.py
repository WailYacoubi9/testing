#!/usr/bin/env python3
"""
Generation des courbes de validation du modele theorique
Comparaison Modele vs Mesures Reelles

Genere:
- Courbes de temps d'execution
- Courbes de speedup
- Courbes d'efficacite
- Graphique d'erreur du modele
- Graphique recapitulatif avec R²
"""

import os
import csv
import argparse
import configparser
from collections import defaultdict
from typing import Dict, List, Tuple

# Verifier si matplotlib est disponible
try:
    import numpy as np
    import matplotlib.pyplot as plt
    PLOTTING_AVAILABLE = True
except ImportError:
    PLOTTING_AVAILABLE = False
    print("Warning: matplotlib/numpy not available. Install with: pip install matplotlib numpy")


def load_model_config(config_file: str) -> dict:
    """Charge la configuration du modele"""
    config = configparser.ConfigParser()
    config.read(config_file)

    params = {}

    if config.has_section('initialization'):
        params['alpha'] = float(config['initialization']['alpha'])
        params['beta'] = float(config['initialization']['beta'])
    else:
        params['alpha'] = 0.5
        params['beta'] = 1.0

    if config.has_section('rmi'):
        params['L_rmi'] = float(config['rmi']['L_rmi'])
        params['o_rmi'] = float(config['rmi']['o_rmi'])
    else:
        params['L_rmi'] = 50.0
        params['o_rmi'] = 10.0

    if config.has_section('transfer_scp'):
        params['L_scp'] = float(config['transfer_scp']['L_scp'])
        params['BW_scp'] = float(config['transfer_scp']['BW_scp'])
    else:
        params['L_scp'] = 200.0
        params['BW_scp'] = 100.0

    if config.has_section('transfer_nfs'):
        params['L_nfs'] = float(config['transfer_nfs']['L_nfs'])
        params['BW_nfs'] = float(config['transfer_nfs']['BW_nfs'])
    else:
        params['L_nfs'] = 5.0
        params['BW_nfs'] = 500.0

    if config.has_section('compute'):
        params['V_wc'] = float(config['compute']['V_wc'])
    else:
        params['V_wc'] = 100000.0

    if config.has_section('sequential'):
        params['T_parse'] = float(config['sequential']['T_parse'])
        params['V_split'] = float(config['sequential']['V_split'])
    else:
        params['T_parse'] = 0.01
        params['V_split'] = 500.0

    if config.has_section('aggregation'):
        params['T_agg'] = float(config['aggregation']['T_agg'])
    else:
        params['T_agg'] = 0.05

    return params


def predict_time(n: int, size_mb: float, mode: str, params: dict) -> float:
    """Predit le temps d'execution selon le modele theorique"""

    # T_init = alpha * n + beta
    T_init = params['alpha'] * n + params['beta']

    # T_seq = T_parse + S / V_split
    T_seq = params['T_parse'] + size_mb / params['V_split']

    # T_comm
    if mode.upper() == 'NFS':
        T_comm = params['L_nfs'] / 1000  # ms -> s
    else:  # SCP
        T_comm = n * (params['L_scp'] / 1000 + (size_mb / n) / params['BW_scp'])

    # T_calc (lignes ≈ size_mb * 10000)
    lines = size_mb * 10000
    T_worker = lines / n / params['V_wc']
    T_rmi_overhead = n * (params['L_rmi'] + params['o_rmi']) / 1000
    T_calc = T_worker + T_rmi_overhead

    # T_agg
    T_agg = params['T_agg']

    return T_init + T_seq + T_comm + T_calc + T_agg


def load_measurements(csv_file: str) -> Dict:
    """Charge les mesures depuis le fichier CSV"""
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            n = int(row['num_workers'])
            size = int(row['file_size_mb'])
            mode = row['mode'].upper()
            time = float(row['measured_time_s'])
            data[mode][size][n].append(time)

    return data


def calculate_stats(values: List[float]) -> Tuple[float, float]:
    """Calcule moyenne et intervalle de confiance 95%"""
    if not PLOTTING_AVAILABLE:
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
        std = variance ** 0.5
        ci = 1.96 * std / (len(values) ** 0.5)
        return mean, ci

    mean = np.mean(values)
    std = np.std(values, ddof=1)
    ci = 1.96 * std / np.sqrt(len(values))
    return mean, ci


def print_text_summary(measurements: Dict, params: dict):
    """Affiche un resume textuel des resultats"""
    print("\n" + "=" * 70)
    print("RESUME DES RESULTATS DE VALIDATION")
    print("=" * 70)

    for mode in sorted(measurements.keys()):
        print(f"\n--- Mode: {mode} ---")

        for size_mb in sorted(measurements[mode].keys()):
            print(f"\n  Taille: {size_mb} MB")
            print(f"  {'Workers':<10} {'Mesure (s)':<15} {'Modele (s)':<15} {'Erreur (%)':<12} {'Speedup':<10}")
            print("  " + "-" * 62)

            workers = sorted(measurements[mode][size_mb].keys())
            T1_measured = None

            for n in workers:
                measured_mean, measured_ci = calculate_stats(measurements[mode][size_mb][n])
                predicted = predict_time(n, size_mb, mode, params)
                error = abs(measured_mean - predicted) / measured_mean * 100

                if T1_measured is None:
                    T1_measured = measured_mean

                speedup = T1_measured / measured_mean

                print(f"  {n:<10} {measured_mean:<15.3f} {predicted:<15.3f} {error:<12.1f} {speedup:<10.2f}")


def plot_validation(measurements: Dict, params: dict, output_dir: str):
    """Genere les graphiques de validation"""

    if not PLOTTING_AVAILABLE:
        print("Matplotlib non disponible, generation de graphiques ignoree.")
        print_text_summary(measurements, params)
        return

    os.makedirs(output_dir, exist_ok=True)

    for mode in measurements:
        for size_mb in sorted(measurements[mode].keys()):
            fig, axes = plt.subplots(2, 2, figsize=(14, 10))
            fig.suptitle(f'Validation du Modele - {mode}, {size_mb}MB', fontsize=14)

            workers = sorted(measurements[mode][size_mb].keys())

            # Donnees mesurees
            measured_means = []
            measured_cis = []
            for n in workers:
                mean, ci = calculate_stats(measurements[mode][size_mb][n])
                measured_means.append(mean)
                measured_cis.append(ci)

            # Predictions du modele
            predicted = [predict_time(n, size_mb, mode, params) for n in workers]

            # === Plot 1: Temps d'execution ===
            ax1 = axes[0, 0]
            ax1.errorbar(workers, measured_means, yerr=measured_cis,
                        fmt='ro-', capsize=5, label='Mesure (IC 95%)')
            ax1.plot(workers, predicted, 'b^--', label='Modele theorique')
            ax1.set_xlabel('Nombre de workers')
            ax1.set_ylabel('Temps (secondes)')
            ax1.set_title("Temps d'execution")
            ax1.legend()
            ax1.grid(True, alpha=0.3)

            # === Plot 2: Speedup ===
            ax2 = axes[0, 1]
            T1_measured = measured_means[0]
            T1_predicted = predicted[0]

            speedup_measured = [T1_measured / t for t in measured_means]
            speedup_predicted = [T1_predicted / t for t in predicted]
            speedup_ideal = list(workers)

            ax2.plot(workers, speedup_ideal, 'g--', label='Ideal', linewidth=2)
            ax2.plot(workers, speedup_predicted, 'b^--', label='Modele')
            ax2.plot(workers, speedup_measured, 'ro-', label='Mesure')
            ax2.set_xlabel('Nombre de workers')
            ax2.set_ylabel('Speedup')
            ax2.set_title('Acceleration (Speedup)')
            ax2.legend()
            ax2.grid(True, alpha=0.3)

            # === Plot 3: Efficacite ===
            ax3 = axes[1, 0]
            eff_measured = [s / n for s, n in zip(speedup_measured, workers)]
            eff_predicted = [s / n for s, n in zip(speedup_predicted, workers)]

            ax3.axhline(y=1.0, color='g', linestyle='--', label='Ideal')
            ax3.plot(workers, eff_predicted, 'b^--', label='Modele')
            ax3.plot(workers, eff_measured, 'ro-', label='Mesure')
            ax3.set_xlabel('Nombre de workers')
            ax3.set_ylabel('Efficacite')
            ax3.set_title('Efficacite parallele')
            ax3.set_ylim(0, 1.2)
            ax3.legend()
            ax3.grid(True, alpha=0.3)

            # === Plot 4: Erreur relative ===
            ax4 = axes[1, 1]
            errors = [(abs(m - p) / m) * 100 for m, p in zip(measured_means, predicted)]

            bars = ax4.bar(range(len(workers)), errors, tick_label=workers)
            avg_error = np.mean(errors)
            ax4.axhline(y=avg_error, color='r', linestyle='--',
                       label=f'Erreur moyenne: {avg_error:.1f}%')
            ax4.set_xlabel('Nombre de workers')
            ax4.set_ylabel('Erreur relative (%)')
            ax4.set_title('Precision du modele')
            ax4.legend()

            # Couleur selon l'erreur
            for bar, err in zip(bars, errors):
                if err < 10:
                    bar.set_color('green')
                elif err < 20:
                    bar.set_color('orange')
                else:
                    bar.set_color('red')

            plt.tight_layout()

            filename = f'{output_dir}/validation_{mode}_{size_mb}MB.png'
            plt.savefig(filename, dpi=150)
            plt.close()

            print(f"  Graphique genere: {filename}")

    # Graphique recapitulatif
    plot_summary(measurements, params, output_dir)


def plot_summary(measurements: Dict, params: dict, output_dir: str):
    """Genere un graphique recapitulatif"""

    if not PLOTTING_AVAILABLE:
        return

    fig, ax = plt.subplots(figsize=(10, 8))

    all_measured = []
    all_predicted = []

    for mode in measurements:
        for size_mb in measurements[mode]:
            workers = sorted(measurements[mode][size_mb].keys())

            for n in workers:
                measured = np.mean(measurements[mode][size_mb][n])
                predicted = predict_time(n, size_mb, mode, params)

                all_measured.append(measured)
                all_predicted.append(predicted)

    ax.scatter(all_measured, all_predicted, alpha=0.6, s=50)

    # Ligne parfaite
    max_val = max(max(all_measured), max(all_predicted)) * 1.1
    ax.plot([0, max_val], [0, max_val], 'r--', label='Prediction parfaite', linewidth=2)

    # R²
    ss_res = sum((p - m) ** 2 for m, p in zip(all_measured, all_predicted))
    ss_tot = sum((m - np.mean(all_measured)) ** 2 for m in all_measured)
    r_squared = 1 - ss_res / ss_tot

    # Erreur moyenne
    errors = [abs(m - p) / m * 100 for m, p in zip(all_measured, all_predicted)]
    avg_error = np.mean(errors)

    ax.set_xlabel('Temps mesure (secondes)', fontsize=12)
    ax.set_ylabel('Temps predit (secondes)', fontsize=12)
    ax.set_title(f'Validation globale du modele\nR² = {r_squared:.4f}, Erreur moyenne = {avg_error:.1f}%', fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, max_val)
    ax.set_ylim(0, max_val)

    plt.tight_layout()

    filename = f'{output_dir}/validation_summary.png'
    plt.savefig(filename, dpi=150)
    plt.close()

    print(f"\n  Graphique recapitulatif: {filename}")
    print(f"  R² = {r_squared:.4f}")
    print(f"  Erreur moyenne = {avg_error:.1f}%")


def main():
    parser = argparse.ArgumentParser(
        description="Generation des courbes de validation du modele theorique"
    )
    parser.add_argument("csv_file", help="Fichier CSV des mesures de validation")
    parser.add_argument("--config", default="model/model_config.ini",
                       help="Fichier de configuration du modele")
    parser.add_argument("--output", default="benchmarks/results/plots",
                       help="Repertoire de sortie pour les graphiques")

    args = parser.parse_args()

    print("=" * 60)
    print("GENERATION DES COURBES DE VALIDATION")
    print("=" * 60)

    # Charger la configuration du modele
    print("\n[1/3] Chargement de la configuration du modele...")
    if os.path.exists(args.config):
        params = load_model_config(args.config)
        print(f"  Configuration chargee: {args.config}")
    else:
        print(f"  Config non trouvee, utilisation des valeurs par defaut")
        params = load_model_config("")

    # Charger les mesures
    print("\n[2/3] Chargement des mesures...")
    measurements = load_measurements(args.csv_file)

    total_points = sum(
        len(measurements[m][s][n])
        for m in measurements
        for s in measurements[m]
        for n in measurements[m][s]
    )
    print(f"  {total_points} points de mesure charges")

    # Generer les graphiques
    print("\n[3/3] Generation des graphiques...")
    plot_validation(measurements, params, args.output)

    # Afficher le resume textuel
    print_text_summary(measurements, params)

    print("\n" + "=" * 60)
    print("VALIDATION TERMINEE")
    print("=" * 60)


if __name__ == "__main__":
    main()
