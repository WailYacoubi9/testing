#!/usr/bin/env python3
"""
Beautiful benchmark visualization for small files (0-1KB)
Shows latency, throughput, and speedup comparisons
"""

import os
import sys
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns

# Set seaborn style
sns.set_style("whitegrid")
sns.set_palette("Set2")

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULTS_FILE = os.path.join(SCRIPT_DIR, "results_small_files.csv")

def load_results():
    """Load results from CSV file"""
    if not os.path.exists(RESULTS_FILE):
        print(f"Error: Results file not found at {RESULTS_FILE}")
        sys.exit(1)
    
    df = pd.read_csv(RESULTS_FILE)
    df.columns = df.columns.str.strip()
    return df

def plot_grouped_latency(df):
    """Line chart for latency comparison - small files"""
    fig, ax = plt.subplots(figsize=(16, 9))
    
    plot_df = df.copy()
    plot_df['LatencyFirstByte(ms)'] = pd.to_numeric(plot_df['LatencyFirstByte(ms)'], errors='coerce')
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    # Plot lines with markers
    ax.plot(scp_data['Lines'].values, scp_data['LatencyFirstByte(ms)'].values, 
            marker='o', linewidth=3, markersize=10, label='SCP', 
            color='#FF6B6B', alpha=0.85)
    ax.plot(nfs_data['Lines'].values, nfs_data['LatencyFirstByte(ms)'].values, 
            marker='s', linewidth=3, markersize=10, label='NFS',
            color='#4ECDC4', alpha=0.85)
    
    ax.set_ylabel('Latency to First Byte (ms)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('Latency Comparison: SCP vs NFS (Small Files 0-1KB)\n(Lower is Better)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.legend(fontsize=12, loc='upper left', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(True, alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    return fig

def plot_grouped_throughput(df):
    """Line chart for throughput comparison - small files"""
    fig, ax = plt.subplots(figsize=(16, 9))
    
    plot_df = df.copy()
    plot_df['Throughput(MB/s)'] = pd.to_numeric(plot_df['Throughput(MB/s)'], errors='coerce')
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    # Plot lines with markers
    ax.plot(scp_data['Lines'].values, scp_data['Throughput(MB/s)'].values, 
            marker='o', linewidth=3, markersize=10, label='SCP',
            color='#FF6B6B', alpha=0.85)
    ax.plot(nfs_data['Lines'].values, nfs_data['Throughput(MB/s)'].values, 
            marker='s', linewidth=3, markersize=10, label='NFS',
            color='#4ECDC4', alpha=0.85)
    
    ax.set_ylabel('Throughput (MB/s)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('Throughput Comparison: SCP vs NFS (Small Files 0-1KB)\n(Higher is Better)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.legend(fontsize=12, loc='upper left', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(True, alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    return fig

def plot_speedup_bars(df):
    """Line chart showing speedup factor - small files"""
    fig, ax = plt.subplots(figsize=(16, 9))
    
    plot_df = df.copy()
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    latency_scp = pd.to_numeric(scp_data['LatencyFirstByte(ms)'], errors='coerce').values
    latency_nfs = pd.to_numeric(nfs_data['LatencyFirstByte(ms)'], errors='coerce').values
    throughput_scp = pd.to_numeric(scp_data['Throughput(MB/s)'], errors='coerce').values
    throughput_nfs = pd.to_numeric(nfs_data['Throughput(MB/s)'], errors='coerce').values
    
    speedup_latency = latency_scp / latency_nfs
    speedup_throughput = np.divide(throughput_nfs, throughput_scp, where=throughput_scp!=0, out=np.zeros_like(throughput_scp))
    
    lines = scp_data['Lines'].values
    
    # Plot lines with markers
    ax.plot(lines, speedup_latency, marker='o', linewidth=3, markersize=10, 
            label='Latency Speedup', color='#4ECDC4', alpha=0.85)
    ax.plot(lines, speedup_throughput, marker='s', linewidth=3, markersize=10, 
            label='Throughput Speedup', color='#FF6B6B', alpha=0.85)
    
    ax.set_ylabel('Speedup Factor (X times faster)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('How Much Faster is NFS? (Small Files 0-1KB)\n(Shows dominance of NFS over SCP)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.legend(fontsize=12, loc='upper right', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(True, alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    # Add baseline
    ax.axhline(y=1, color='red', linestyle='--', linewidth=2, alpha=0.5)
    
    plt.tight_layout()
    return fig

def main():
    """Main function"""
    print("\n" + "="*70)
    print("NFS vs SCP BENCHMARK - SMALL FILES (0-1KB)")
    print("="*70 + "\n")
    
    print(f"Loading results from: {RESULTS_FILE}")
    df = load_results()
    print(f"Loaded {len(df)} records\n")
    
    print("Generating visualizations...\n")
    
    output_dir = SCRIPT_DIR
    
    # Plot 1: Grouped latency
    fig1 = plot_grouped_latency(df)
    fig1.savefig(os.path.join(output_dir, "small_01_latency_grouped.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: small_01_latency_grouped.png")
    
    # Plot 2: Grouped throughput
    fig2 = plot_grouped_throughput(df)
    fig2.savefig(os.path.join(output_dir, "small_02_throughput_grouped.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: small_02_throughput_grouped.png")
    
    # Plot 3: Speedup bars
    fig3 = plot_speedup_bars(df)
    fig3.savefig(os.path.join(output_dir, "small_03_speedup_comparison.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: small_03_speedup_comparison.png")
    
    print(f"\nAll visualizations saved to: {output_dir}")
    print("Total: 3 high-quality PNG files\n")

if __name__ == "__main__":
    main()
