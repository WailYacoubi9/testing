#!/usr/bin/env python3
"""
=============================================================================
MODÈLE THÉORIQUE DE PERFORMANCE - WORDCOUNT DISTRIBUÉ
=============================================================================

Calibré avec les données réelles mesurées sur Grid5000.

Références académiques:
- Graham, R.L. (1969). "Bounds on Multiprocessing Timing Anomalies"
- Culler et al. (1993). "LogP: A Practical Model of Parallel Computation"
- Amdahl, G.M. (1967). "Validity of the single processor approach"

Formule principale:
    T_total = T_init(n) + T_split(S) + T_dist(S,n) + T_calc(S,n) + T_agg

=============================================================================
"""

import math

# =============================================================================
# PARAMÈTRES CALIBRÉS DEPUIS VOS DONNÉES RÉELLES
# =============================================================================

# Depuis launcher-results/launcher_20251224_174358.csv
# Régression linéaire sur: 2w->2.06s, 3w->2.57s, 4w->3.07s, 5w->3.57s, 6w->4.09s, 7w->4.60s, 8w->5.10s
ALPHA = 0.507  # secondes par worker (pente)
BETA = 1.046   # overhead fixe en secondes (ordonnée à l'origine)

# Depuis NfsvsScp/results_big_files.csv - Mode SCP
L_SCP = 419.0      # Latence SCP en ms (premier byte pour 12MB)
BW_SCP = 400.0     # Bande passante SCP en MB/s (moyenne gros fichiers)

# Depuis NfsvsScp/results_big_files.csv - Mode NFS
L_NFS = 4.0        # Latence NFS en ms (quasi-constante)
BW_NFS = 5000.0    # Bande passante NFS en MB/s (accès mémoire partagée)

# Paramètres de calcul (à calibrer avec benchmark wordcount)
# Estimation basée sur un wordcount typique
V_WC = 500000      # Vitesse wordcount: lignes/seconde (estimation)
WORDS_PER_LINE = 5 # Mots moyens par ligne

# Paramètres séquentiels
T_PARSE = 0.010    # Temps de parsing Makefile (10ms)
V_SPLIT = 500.0    # Vitesse de split fichier (MB/s)

# Paramètres d'agrégation
T_AGG = 0.050      # Temps d'agrégation finale (50ms)

# Overhead RMI (estimation - à mesurer avec RMILatencyBenchmark)
L_RMI = 50.0       # Latence lookup RMI (ms)
O_RMI = 10.0       # Overhead appel RMI (ms)


# =============================================================================
# FONCTIONS DU MODÈLE
# =============================================================================

def T_init(n: int) -> float:
    """
    Temps d'initialisation du cluster.

    Formule: T_init(n) = α × n + β

    Calibré depuis launcher-results:
    - α = 0.507 s/worker
    - β = 1.046 s

    Fondement: Overhead linéaire pour établir n connexions RMI
    """
    return ALPHA * n + BETA


def T_split(size_mb: float) -> float:
    """
    Temps de découpage du fichier d'entrée.

    Formule: T_split = S / V_split

    Fondement: Opération I/O-bound, limitée par vitesse disque
    """
    return size_mb / V_SPLIT


def T_dist(size_mb: float, n: int, mode: str = "NFS") -> float:
    """
    Temps de distribution des partitions aux workers.

    Mode SCP: T = n × (L_scp + (S/n) / BW_scp)
    Mode NFS: T = L_nfs (accès direct, quasi-instantané)

    Calibré depuis NfsvsScp/results_big_files.csv:
    - SCP: L=419ms, BW=400 MB/s
    - NFS: L=4ms, BW=5000 MB/s

    Fondement: Modèle LogP - Latence + Temps de transfert
    """
    if mode.upper() == "NFS":
        return L_NFS / 1000  # Conversion ms -> s
    else:  # SCP
        partition_size = size_mb / n
        time_per_worker = (L_SCP / 1000) + (partition_size / BW_SCP)
        # Transferts parallèles mais limités par le master
        return time_per_worker * min(n, 3)  # 3 transferts simultanés max


def T_calc(size_mb: float, n: int) -> float:
    """
    Temps de calcul parallèle.

    Formule: T_calc = max(T_worker_i) + overhead_RMI

    Avec partitions équilibrées:
    T_calc ≈ (S × lines_per_MB) / (n × V_wc) + n × (L_rmi + O_rmi)

    Fondement:
    - Graham (1969): T ≤ Σtᵢ/m + t_max
    - Pour partitions égales: t_max ≈ moyenne
    """
    lines_per_mb = 10000  # Estimation: 10000 lignes par MB
    total_lines = size_mb * lines_per_mb
    lines_per_worker = total_lines / n

    # Temps de calcul par worker
    T_worker = lines_per_worker / V_WC

    # Overhead RMI pour chaque appel (n appels au total)
    T_rmi = n * (L_RMI + O_RMI) / 1000  # ms -> s

    return T_worker + T_rmi


def T_agg() -> float:
    """
    Temps d'agrégation des résultats (cat | awk).

    Fondement: Opération séquentielle finale (reduction)
    """
    return T_AGG


def T_total(size_mb: float, n: int, mode: str = "NFS") -> float:
    """
    Temps total d'exécution prédit par le modèle.

    T_total = T_init + T_split + T_dist + T_calc + T_agg
    """
    return (T_init(n) +
            T_split(size_mb) +
            T_dist(size_mb, n, mode) +
            T_calc(size_mb, n) +
            T_agg())


# =============================================================================
# MÉTRIQUES DE PERFORMANCE
# =============================================================================

def speedup(size_mb: float, n: int, mode: str = "NFS") -> float:
    """
    Accélération (Speedup): S(n) = T(1) / T(n)

    Fondement: Loi d'Amdahl
    """
    T_1 = T_total(size_mb, 1, mode)
    T_n = T_total(size_mb, n, mode)
    return T_1 / T_n


def efficiency(size_mb: float, n: int, mode: str = "NFS") -> float:
    """
    Efficacité: E(n) = S(n) / n

    E = 1 → Parallélisation parfaite
    E < 1 → Overhead de communication/synchronisation
    """
    return speedup(size_mb, n, mode) / n


# =============================================================================
# DÉCOMPOSITION DÉTAILLÉE
# =============================================================================

def decompose(size_mb: float, n: int, mode: str = "NFS") -> dict:
    """
    Retourne la décomposition complète du temps d'exécution.
    """
    t_init = T_init(n)
    t_split = T_split(size_mb)
    t_dist = T_dist(size_mb, n, mode)
    t_calc = T_calc(size_mb, n)
    t_agg = T_agg()
    t_total = t_init + t_split + t_dist + t_calc + t_agg

    return {
        'T_init': t_init,
        'T_split': t_split,
        'T_dist': t_dist,
        'T_calc': t_calc,
        'T_agg': t_agg,
        'T_total': t_total,
        'T_init_pct': (t_init / t_total) * 100,
        'T_split_pct': (t_split / t_total) * 100,
        'T_dist_pct': (t_dist / t_total) * 100,
        'T_calc_pct': (t_calc / t_total) * 100,
        'T_agg_pct': (t_agg / t_total) * 100,
    }


# =============================================================================
# AFFICHAGE ET PRÉDICTIONS
# =============================================================================

def print_parameters():
    """Affiche les paramètres calibrés du modèle."""
    print("=" * 70)
    print("PARAMÈTRES DU MODÈLE (Calibrés depuis vos données)")
    print("=" * 70)
    print()
    print("Initialisation (depuis launcher-results):")
    print(f"  α = {ALPHA:.3f} s/worker")
    print(f"  β = {BETA:.3f} s")
    print(f"  → T_init(n) = {ALPHA:.3f} × n + {BETA:.3f}")
    print()
    print("Transfert SCP (depuis NfsvsScp):")
    print(f"  L_scp = {L_SCP:.1f} ms")
    print(f"  BW_scp = {BW_SCP:.1f} MB/s")
    print()
    print("Transfert NFS (depuis NfsvsScp):")
    print(f"  L_nfs = {L_NFS:.1f} ms")
    print(f"  BW_nfs = {BW_NFS:.1f} MB/s")
    print()
    print("Calcul:")
    print(f"  V_wc = {V_WC:,} lignes/s")
    print()
    print("RMI (estimation):")
    print(f"  L_rmi = {L_RMI:.1f} ms")
    print(f"  O_rmi = {O_RMI:.1f} ms")
    print()


def print_predictions(size_mb: float = 100, mode: str = "NFS"):
    """Affiche les prédictions du modèle."""
    print("=" * 70)
    print(f"PRÉDICTIONS DU MODÈLE - Fichier {size_mb} MB, Mode {mode}")
    print("=" * 70)
    print()
    print(f"{'Workers':<10} {'T_total (s)':<12} {'Speedup':<10} {'Efficacité':<12}")
    print("-" * 44)

    for n in [1, 2, 4, 8, 16, 32, 64]:
        t = T_total(size_mb, n, mode)
        s = speedup(size_mb, n, mode)
        e = efficiency(size_mb, n, mode)
        print(f"{n:<10} {t:<12.2f} {s:<10.2f} {e:<12.1%}")

    print()


def print_decomposition(size_mb: float = 100, n: int = 8, mode: str = "NFS"):
    """Affiche la décomposition du temps pour une configuration."""
    print("=" * 70)
    print(f"DÉCOMPOSITION - {size_mb} MB, {n} workers, mode {mode}")
    print("=" * 70)
    print()

    d = decompose(size_mb, n, mode)

    print(f"T_init  = {d['T_init']:.3f} s  ({d['T_init_pct']:.1f}%) - Initialisation cluster")
    print(f"T_split = {d['T_split']:.3f} s  ({d['T_split_pct']:.1f}%) - Découpage fichier")
    print(f"T_dist  = {d['T_dist']:.3f} s  ({d['T_dist_pct']:.1f}%) - Distribution partitions")
    print(f"T_calc  = {d['T_calc']:.3f} s  ({d['T_calc_pct']:.1f}%) - Calcul parallèle")
    print(f"T_agg   = {d['T_agg']:.3f} s  ({d['T_agg_pct']:.1f}%) - Agrégation résultats")
    print("-" * 40)
    print(f"T_total = {d['T_total']:.3f} s")
    print()


def compare_modes(size_mb: float = 100):
    """Compare les modes SCP et NFS."""
    print("=" * 70)
    print(f"COMPARAISON SCP vs NFS - Fichier {size_mb} MB")
    print("=" * 70)
    print()
    print(f"{'Workers':<10} {'T_SCP (s)':<12} {'T_NFS (s)':<12} {'Gain NFS':<12}")
    print("-" * 46)

    for n in [1, 2, 4, 8, 16, 32]:
        t_scp = T_total(size_mb, n, "SCP")
        t_nfs = T_total(size_mb, n, "NFS")
        gain = ((t_scp - t_nfs) / t_scp) * 100
        print(f"{n:<10} {t_scp:<12.2f} {t_nfs:<12.2f} {gain:<12.1f}%")

    print()


# =============================================================================
# FORMULE THÉORIQUE POUR LE RAPPORT
# =============================================================================

def print_formula():
    """Affiche la formule théorique complète pour le rapport."""
    print("=" * 70)
    print("FORMULE THÉORIQUE COMPLÈTE")
    print("=" * 70)
    print("""
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   T_total(S, n, mode) = T_init + T_split + T_dist + T_calc + T_agg │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   T_init(n) = α × n + β                                            │
│             = 0.507 × n + 1.046  [secondes]                        │
│                                                                     │
│   T_split(S) = S / V_split                                         │
│              = S / 500  [secondes, S en MB]                        │
│                                                                     │
│   T_dist(S, n, mode):                                              │
│     SCP: n × (L_scp + S/n / BW_scp)                                │
│        = n × (0.419 + S/n / 400)  [secondes]                       │
│     NFS: L_nfs = 0.004  [secondes, quasi-constant]                 │
│                                                                     │
│   T_calc(S, n) = S × 10000 / (n × V_wc) + n × (L_rmi + O_rmi)     │
│                = S × 10000 / (n × 500000) + n × 0.060  [secondes] │
│                                                                     │
│   T_agg = 0.050  [secondes, constant]                              │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Speedup:    S(n) = T(1) / T(n)                                   │
│   Efficacité: E(n) = S(n) / n                                      │
│                                                                     │
│   Fondements:                                                       │
│   - Graham (1969): Borne d'ordonnancement par liste                │
│   - Culler (1993): Modèle LogP (Latence, overhead, gap)           │
│   - Amdahl (1967): Loi du speedup                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
""")


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    print()
    print_formula()
    print()
    print_parameters()
    print()
    print_predictions(size_mb=100, mode="NFS")
    print()
    print_decomposition(size_mb=100, n=8, mode="NFS")
    print()
    compare_modes(size_mb=100)
    print()

    # Exemple pour différentes tailles de fichiers
    print("=" * 70)
    print("PRÉDICTIONS POUR DIFFÉRENTES TAILLES DE FICHIERS (8 workers, NFS)")
    print("=" * 70)
    print()
    print(f"{'Taille':<12} {'T_total (s)':<12} {'Speedup':<10}")
    print("-" * 34)
    for size in [10, 50, 100, 500, 1000]:
        t = T_total(size, 8, "NFS")
        s = speedup(size, 8, "NFS")
        print(f"{size} MB{'':<6} {t:<12.2f} {s:<10.2f}")
