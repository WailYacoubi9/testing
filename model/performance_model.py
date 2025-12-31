#!/usr/bin/env python3
"""
Modele Theorique de Performance - Wordcount Distribue
Systemes Distribues - Projet Makefile Parallele

References academiques:
- Graham, R.L. (1969). Bounds on Multiprocessing Timing Anomalies
- Culler et al. (1993). LogP: A Practical Model of Parallel Computation
- Valiant, L.G. (1990). A Bridging Model for Parallel Computation (BSP)
- Amdahl, G.M. (1967). Validity of the single processor approach

Formule:
    T_total = T_init + T_seq + T_comm + T_calc + T_agg
"""

import os
import configparser
from dataclasses import dataclass
from typing import Literal, Tuple


@dataclass
class ModelParameters:
    """Parametres calibres du modele theorique"""

    # Initialisation: T_init(n) = alpha * n + beta
    alpha: float = 0.5      # secondes par worker
    beta: float = 1.0       # overhead fixe (secondes)

    # RMI: latence et overhead
    L_rmi: float = 50.0     # latence lookup (ms)
    o_rmi: float = 10.0     # overhead appel (ms)

    # Transfert SCP
    L_scp: float = 200.0    # latence SCP (ms)
    BW_scp: float = 100.0   # bande passante SCP (MB/s)

    # Transfert NFS
    L_nfs: float = 5.0      # latence NFS (ms)
    BW_nfs: float = 500.0   # bande passante NFS (MB/s)

    # Calcul
    V_wc: float = 100000.0  # vitesse wordcount (lignes/s)

    # Agregation
    T_agg: float = 0.05     # temps fixe (secondes)

    # Sequentiel
    T_parse: float = 0.01   # parsing Makefile (secondes)
    V_split: float = 500.0  # vitesse split (MB/s)


def load_parameters(config_file: str) -> ModelParameters:
    """Charge les parametres depuis un fichier de configuration"""
    params = ModelParameters()

    if not os.path.exists(config_file):
        return params

    config = configparser.ConfigParser()
    config.read(config_file)

    if config.has_section('initialization'):
        params.alpha = float(config['initialization'].get('alpha', params.alpha))
        params.beta = float(config['initialization'].get('beta', params.beta))

    if config.has_section('rmi'):
        params.L_rmi = float(config['rmi'].get('L_rmi', params.L_rmi))
        params.o_rmi = float(config['rmi'].get('o_rmi', params.o_rmi))

    if config.has_section('transfer_scp'):
        params.L_scp = float(config['transfer_scp'].get('L_scp', params.L_scp))
        params.BW_scp = float(config['transfer_scp'].get('BW_scp', params.BW_scp))

    if config.has_section('transfer_nfs'):
        params.L_nfs = float(config['transfer_nfs'].get('L_nfs', params.L_nfs))
        params.BW_nfs = float(config['transfer_nfs'].get('BW_nfs', params.BW_nfs))

    if config.has_section('compute'):
        params.V_wc = float(config['compute'].get('V_wc', params.V_wc))

    if config.has_section('sequential'):
        params.T_parse = float(config['sequential'].get('T_parse', params.T_parse))
        params.V_split = float(config['sequential'].get('V_split', params.V_split))

    if config.has_section('aggregation'):
        params.T_agg = float(config['aggregation'].get('T_agg', params.T_agg))

    return params


def T_init(n: int, params: ModelParameters) -> float:
    """
    Temps d'initialisation du cluster.
    Modele lineaire: T = alpha * n + beta

    Fondement: Overhead de creation de connexions RMI/TCP
    """
    return params.alpha * n + params.beta


def T_seq(size_mb: float, params: ModelParameters) -> float:
    """
    Temps de traitement sequentiel (parsing + split).
    Modele I/O bound: T = T_parse + S / V_split
    """
    return params.T_parse + size_mb / params.V_split


def T_comm(size_mb: float, n: int, mode: str, params: ModelParameters) -> float:
    """
    Temps de distribution aux workers.

    SCP: T = n * (L + S/n / BW)  [sequentiel]
    NFS: T = L                   [acces direct]

    Fondement: Modele LogP - overhead par message
    """
    if mode.upper() == 'NFS':
        return params.L_nfs / 1000  # ms -> s
    else:  # SCP
        partition_size = size_mb / n
        return n * (params.L_scp / 1000 + partition_size / params.BW_scp)


def T_calc(size_mb: float, n: int, params: ModelParameters,
           lines_per_mb: int = 10000) -> float:
    """
    Temps de calcul parallele.

    Modele de Graham: T <= sum(T_i) / m + T_max

    Fondement: Borne de Graham (1969) pour List Scheduling
    """
    total_lines = size_mb * lines_per_mb
    lines_per_worker = total_lines / n

    # Temps de calcul par worker
    T_worker = lines_per_worker / params.V_wc

    # Overhead RMI pour chaque appel
    T_rmi_overhead = n * (params.L_rmi + params.o_rmi) / 1000

    return T_worker + T_rmi_overhead


def T_agg(params: ModelParameters) -> float:
    """Temps d'agregation final (cat | awk)."""
    return params.T_agg


def predict_time(n: int, size_mb: float, mode: str,
                 params: ModelParameters) -> float:
    """
    Temps total predit par le modele.

    T_total = T_init + T_seq + T_comm + T_calc + T_agg
    """
    return (T_init(n, params) +
            T_seq(size_mb, params) +
            T_comm(size_mb, n, mode, params) +
            T_calc(size_mb, n, params) +
            T_agg(params))


def speedup(n: int, size_mb: float, mode: str,
            params: ModelParameters) -> float:
    """
    Acceleration: S(n) = T(1) / T(n)

    Fondement: Loi d'Amdahl / Gustafson
    """
    T_1 = predict_time(1, size_mb, mode, params)
    T_n = predict_time(n, size_mb, mode, params)
    return T_1 / T_n


def efficiency(n: int, size_mb: float, mode: str,
               params: ModelParameters) -> float:
    """
    Efficacite: E(n) = S(n) / n

    E = 1 -> parfaitement parallele
    E < 1 -> overhead de parallelisation
    """
    return speedup(n, size_mb, mode, params) / n


def print_predictions(params: ModelParameters, size_mb: float = 1000,
                      mode: str = 'NFS'):
    """Affiche les predictions du modele"""

    print("=" * 60)
    print("MODELE THEORIQUE DE PERFORMANCE")
    print("Wordcount Distribue sur Grid5000")
    print("=" * 60)

    print(f"\nConfiguration: {size_mb} MB, mode {mode}")
    print("-" * 60)
    print(f"{'Workers':<10} {'T_total (s)':<15} {'Speedup':<10} {'Efficacite':<12}")
    print("-" * 60)

    for n in [1, 2, 4, 8, 16, 32, 64]:
        t = predict_time(n, size_mb, mode, params)
        s = speedup(n, size_mb, mode, params)
        e = efficiency(n, size_mb, mode, params)
        print(f"{n:<10} {t:<15.2f} {s:<10.2f} {e:<12.2%}")

    print("\n" + "=" * 60)
    print(f"Decomposition pour 32 workers ({size_mb} MB, {mode}):")
    print("-" * 60)
    n = 32
    print(f"T_init:   {T_init(n, params):.3f} s")
    print(f"T_seq:    {T_seq(size_mb, params):.3f} s")
    print(f"T_comm:   {T_comm(size_mb, n, mode, params):.3f} s")
    print(f"T_calc:   {T_calc(size_mb, n, params):.3f} s")
    print(f"T_agg:    {T_agg(params):.3f} s")
    print(f"TOTAL:    {predict_time(n, size_mb, mode, params):.3f} s")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Modele theorique de performance"
    )
    parser.add_argument("--config", default="model/model_config.ini",
                       help="Fichier de configuration")
    parser.add_argument("--size", type=float, default=1000,
                       help="Taille du fichier en MB")
    parser.add_argument("--mode", default="NFS", choices=["NFS", "SCP"],
                       help="Mode de transfert")

    args = parser.parse_args()

    # Charger les parametres
    params = load_parameters(args.config)

    # Afficher les predictions
    print_predictions(params, args.size, args.mode)
