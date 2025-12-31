#!/usr/bin/env python3
"""
Compare two launcher measurement CSV files and generate comparison graphs
"""

import pandas as pd
import matplotlib.pyplot as plt
import sys
from pathlib import Path

def load_csv(filepath):
    """Load and parse launcher CSV file"""
    df = pd.read_csv(filepath)
    # Convert timestamps to float
    df['StartTime'] = df['StartTime'].astype(float)
    df['WorkersReady'] = df['WorkersReady'].astype(float)
    df['MasterConnected'] = df['MasterConnected'].astype(float)
    df['LauncherTime'] = df['LauncherTime'].astype(float)
    return df

def main():
    # Get the directory where this script is located
    script_dir = Path(__file__).parent
    results_dir = script_dir / "launcher-results"
    print(f"🔍 Looking for launcher results in: {results_dir}")
    
    # Find CSV files
    csv_files = sorted(results_dir.glob("launcher_*.csv"))
    
    if len(csv_files) == 0:
        print(f"Error: No CSV files found")
        sys.exit(1)
    
    # If only one file, just visualize it
    if len(csv_files) == 1:
        visualize_single(csv_files[0])
    else:
        # If two or more, compare the two most recent
        compare_two(csv_files[-2], csv_files[-1])

def visualize_single(filepath):
    """Visualize a single launcher measurement CSV"""
    print(f" Visualizing launcher results:")
    print(f"   File: {filepath.name}")
    print("")
    
    df = load_csv(filepath)
    stats = df.groupby('Workers')['LauncherTime'].agg(['mean', 'std', 'count']).reset_index()
    
    print("Statistics:")
    print(stats.to_string(index=False))
    
    # Create single visualization
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    
    # Graph 1: Line plot with error bars
    ax1 = axes[0]
    ax1.errorbar(stats['Workers'], stats['mean'], yerr=stats['std'], 
                 fmt='o-', linewidth=2, markersize=8, capsize=5, capthick=2)
    ax1.set_xlabel('Number of Workers', fontsize=11, fontweight='bold')
    ax1.set_ylabel('Launcher Time (seconds)', fontsize=11, fontweight='bold')
    ax1.set_title('Launcher Time - Line Plot', fontsize=12, fontweight='bold')
    ax1.grid(True, alpha=0.3)
    
    # Graph 2: Bar plot
    ax2 = axes[1]
    ax2.bar(stats['Workers'], stats['mean'], alpha=0.8, color='steelblue', 
            error_kw={'elinewidth': 2, 'capsize': 5})
    ax2.set_xlabel('Number of Workers', fontsize=11, fontweight='bold')
    ax2.set_ylabel('Launcher Time (seconds)', fontsize=11, fontweight='bold')
    ax2.set_title('Launcher Time - Bar Chart', fontsize=12, fontweight='bold')
    ax2.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    
    # Save figure
    output_file = filepath.parent / f"visualization_{filepath.stem}.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"\nGraph saved: {output_file}")

def compare_two(file1, file2):
    """Compare two launcher measurement CSVs"""
    
    
    # Load data
    df1 = load_csv(file1)
    df2 = load_csv(file2)
    
    # Group by worker count and calculate mean launcher time
    stats1 = df1.groupby('Workers')['LauncherTime'].agg(['mean', 'std', 'count']).reset_index()
    stats2 = df2.groupby('Workers')['LauncherTime'].agg(['mean', 'std', 'count']).reset_index()
    
    print("Statistics:")
    print(f"\n{file1.name}:")
    if len(stats1) == 0:
        print("No data in this file")
    else:
        print(stats1.to_string(index=False))
    
    print(f"\n{file2.name}:")
    if len(stats2) == 0:
        print("No data in this file")
    else:
        print(stats2.to_string(index=False))
    
    # Only create graphs if both have data
    if len(stats1) == 0 or len(stats2) == 0:
        print("\nError: One or both CSV files have no data")
        sys.exit(1)
    
    # Create comparison graph
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    
    # Graph 1: Line comparison
    ax1 = axes[0]
    ax1.plot(stats1['Workers'], stats1['mean'], 'o-', label=file1.name, linewidth=2, markersize=8)
    ax1.plot(stats2['Workers'], stats2['mean'], 's-', label=file2.name, linewidth=2, markersize=8)
    ax1.fill_between(stats1['Workers'], 
                      stats1['mean'] - stats1['std'], 
                      stats1['mean'] + stats1['std'], 
                      alpha=0.2)
    ax1.fill_between(stats2['Workers'], 
                      stats2['mean'] - stats2['std'], 
                      stats2['mean'] + stats2['std'], 
                      alpha=0.2)
    ax1.set_xlabel('Number of Workers', fontsize=11, fontweight='bold')
    ax1.set_ylabel('Launcher Time (seconds)', fontsize=11, fontweight='bold')
    ax1.set_title('Launcher Time Comparison', fontsize=12, fontweight='bold')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # Graph 2: Bar comparison
    ax2 = axes[1]
    x = range(len(stats1))
    width = 0.35
    ax2.bar([i - width/2 for i in x], stats1['mean'], width, label=file1.name, alpha=0.8)
    ax2.bar([i + width/2 for i in x], stats2['mean'], width, label=file2.name, alpha=0.8)
    ax2.set_xlabel('Number of Workers', fontsize=11, fontweight='bold')
    ax2.set_ylabel('Launcher Time (seconds)', fontsize=11, fontweight='bold')
    ax2.set_title('Launcher Time - Bar Comparison', fontsize=12, fontweight='bold')
    ax2.set_xticks(x)
    ax2.set_xticklabels(stats1['Workers'])
    ax2.legend()
    ax2.grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    
    # Save figure
    output_file = results_dir / "comparison_launcher.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"\nGraph saved: {output_file}")
    
    # Calculate improvement/degradation
    print("\nImprovement Analysis:")
    for w in stats1['Workers'].values:
        if w in stats2['Workers'].values:
            t1 = stats1[stats1['Workers'] == w]['mean'].values[0]
            t2 = stats2[stats2['Workers'] == w]['mean'].values[0]
            diff = t2 - t1
            pct = (diff / t1) * 100 if t1 != 0 else 0
            
            status = "Slower" if diff > 0 else "Faster"
            print(f"   {int(w):2d} workers: {t1:.3f}s → {t2:.3f}s ({status} {abs(pct):+.1f}%)")

if __name__ == "__main__":
    main()
