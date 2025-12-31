#!/usr/bin/env python3
"""
Beautiful benchmark comparison visualizations
Shows the dramatic difference between SCP and NFS with multiple perspectives
"""

import os
import sys
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from pathlib import Path

# Set seaborn style
sns.set_style("whitegrid")
sns.set_palette("Set2")

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULTS_FILE = os.path.join(SCRIPT_DIR, "results.csv")

def load_results():
    """Load results from CSV file"""
    if not os.path.exists(RESULTS_FILE):
        print(f"Error: Results file not found at {RESULTS_FILE}")
        sys.exit(1)
    
    df = pd.read_csv(RESULTS_FILE)
    df.columns = df.columns.str.strip()
    return df

def plot_grouped_latency(df):
    """Grouped bar chart for latency comparison - up to 3M lines (excluding 100K)"""
    fig, ax = plt.subplots(figsize=(20, 10))
    
    plot_df = df.copy()
    plot_df['LatencyFirstByte(ms)'] = pd.to_numeric(plot_df['LatencyFirstByte(ms)'], errors='coerce')
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    # Limit to 3M lines and exclude 100K lines
    plot_df = plot_df[plot_df['Lines'] <= 3000000]
    plot_df = plot_df[plot_df['Lines'] != 100000]
    
    # Create grouped bar chart
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    x = np.arange(len(scp_data))
    width = 0.35
    
    bars1 = ax.bar(x - width/2, scp_data['LatencyFirstByte(ms)'].values, width, 
                   label='SCP', color='#FF6B6B', alpha=0.85, edgecolor='black', linewidth=1.5)
    bars2 = ax.bar(x + width/2, nfs_data['LatencyFirstByte(ms)'].values, width,
                   label='NFS', color='#4ECDC4', alpha=0.85, edgecolor='black', linewidth=1.5)
    
    # Add value labels on bars
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{height:.1f}ms',
                   ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    ax.set_ylabel('Latency to First Byte (ms)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('Latency Comparison: SCP vs NFS (Up to 3M lines)\n(Lower is Better)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels([f'{int(v):,}' for v in scp_data['Lines'].values], rotation=45, ha='right')
    ax.set_ylim(0, 1600)  # Focus on lower range to show NFS better
    ax.legend(fontsize=12, loc='upper left', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    return fig

def plot_grouped_throughput(df):
    """Grouped bar chart for throughput comparison - up to 3M lines (excluding 100K)"""
    fig, ax = plt.subplots(figsize=(20, 10))
    
    plot_df = df.copy()
    plot_df['Throughput(MB/s)'] = pd.to_numeric(plot_df['Throughput(MB/s)'], errors='coerce')
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    # Limit to 3M lines and exclude 100K lines
    plot_df = plot_df[plot_df['Lines'] <= 3000000]
    plot_df = plot_df[plot_df['Lines'] != 100000]
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    x = np.arange(len(scp_data))
    width = 0.35
    
    bars1 = ax.bar(x - width/2, scp_data['Throughput(MB/s)'].values, width,
                   label='SCP', color='#FF6B6B', alpha=0.85, edgecolor='black', linewidth=1.5)
    bars2 = ax.bar(x + width/2, nfs_data['Throughput(MB/s)'].values, width,
                   label='NFS', color='#4ECDC4', alpha=0.85, edgecolor='black', linewidth=1.5)
    
    # Add value labels
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{height:.0f}',
                   ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    ax.set_ylabel('Throughput (MB/s)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('Throughput Comparison: SCP vs NFS (Up to 3M lines)\n(Higher is Better)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels([f'{int(v):,}' for v in scp_data['Lines'].values], rotation=45, ha='right')
    ax.legend(fontsize=12, loc='upper left', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    plt.tight_layout()
    return fig

def plot_dual_axis_latency(df):
    """Dual axis plot - separate scales for SCP and NFS latency (up to 3M lines, excluding 100K)"""
    fig, ax1 = plt.subplots(figsize=(18, 10))
    
    plot_df = df.copy()
    plot_df['LatencyFirstByte(ms)'] = pd.to_numeric(plot_df['LatencyFirstByte(ms)'], errors='coerce')
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    # Limit to 3M lines and exclude 100K lines
    plot_df = plot_df[plot_df['Lines'] <= 3000000]
    plot_df = plot_df[plot_df['Lines'] != 100000]
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    x = np.arange(len(scp_data))
    
    # SCP on left axis
    color = '#FF6B6B'
    ax1.set_xlabel('File Size (number of lines)', fontsize=12, fontweight='bold')
    ax1.set_ylabel('SCP Latency (ms)', color=color, fontsize=12, fontweight='bold')
    line1 = ax1.plot(x, scp_data['LatencyFirstByte(ms)'].values, marker='o', linewidth=3.5, 
                     markersize=10, color=color, label='SCP', alpha=0.85)
    ax1.tick_params(axis='y', labelcolor=color)
    ax1.grid(True, alpha=0.2)
    
    # NFS on right axis
    ax2 = ax1.twinx()
    color = '#4ECDC4'
    ax2.set_ylabel('NFS Latency (ms)', color=color, fontsize=12, fontweight='bold')
    line2 = ax2.plot(x, nfs_data['LatencyFirstByte(ms)'].values, marker='s', linewidth=3.5,
                     markersize=10, color=color, label='NFS', alpha=0.85)
    ax2.tick_params(axis='y', labelcolor=color)
    
    # Title and legend
    fig.suptitle('Latency with Separate Axes - Up to 3M lines\n(Each mode has its own scale)', 
                 fontsize=15, fontweight='bold', y=0.98)
    
    ax1.set_xticks(x)
    ax1.set_xticklabels([f'{int(v):,}' for v in scp_data['Lines'].values], rotation=45, ha='right')
    
    # Combined legend
    lines = line1 + line2
    labels = [l.get_label() for l in lines]
    ax1.legend(lines, labels, fontsize=12, loc='upper left', framealpha=0.95, 
              edgecolor='black', fancybox=True)
    
    plt.tight_layout()
    return fig

def plot_speedup_bars(df):
    """Bar chart showing speedup factor - up to 3M lines (excluding 100K)"""
    fig, ax = plt.subplots(figsize=(18, 10))
    
    plot_df = df.copy()
    plot_df['Lines'] = pd.to_numeric(plot_df['Lines'], errors='coerce')
    
    # Limit to 3M lines and exclude 100K lines
    plot_df = plot_df[plot_df['Lines'] <= 3000000]
    plot_df = plot_df[plot_df['Lines'] != 100000]
    
    scp_data = plot_df[plot_df['Mode'] == 'SCP'].sort_values('Lines', ascending=True)
    nfs_data = plot_df[plot_df['Mode'] == 'NFS'].sort_values('Lines', ascending=True)
    
    latency_scp = pd.to_numeric(scp_data['LatencyFirstByte(ms)'], errors='coerce').values
    latency_nfs = pd.to_numeric(nfs_data['LatencyFirstByte(ms)'], errors='coerce').values
    throughput_scp = pd.to_numeric(scp_data['Throughput(MB/s)'], errors='coerce').values
    throughput_nfs = pd.to_numeric(nfs_data['Throughput(MB/s)'], errors='coerce').values
    
    speedup_latency = latency_scp / latency_nfs
    speedup_throughput = throughput_nfs / throughput_scp
    
    x = np.arange(len(scp_data))
    width = 0.35
    
    bars1 = ax.bar(x - width/2, speedup_latency, width, label='Latency Speedup', 
                   color='#4ECDC4', alpha=0.85, edgecolor='black', linewidth=1.5)
    bars2 = ax.bar(x + width/2, speedup_throughput, width, label='Throughput Speedup',
                   color='#FF6B6B', alpha=0.85, edgecolor='black', linewidth=1.5)
    
    # Add value labels
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{height:.1f}x',
                   ha='center', va='bottom', fontsize=10, fontweight='bold')
    
    ax.set_ylabel('Speedup Factor (X times faster)', fontsize=13, fontweight='bold')
    ax.set_xlabel('File Size (number of lines)', fontsize=13, fontweight='bold')
    ax.set_title('How Much Faster is NFS? (Up to 3M lines)\n(Shows dominance of NFS over SCP)', 
                 fontsize=15, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels([f'{int(v):,}' for v in scp_data['Lines'].values], rotation=45, ha='right')
    ax.legend(fontsize=12, loc='upper right', framealpha=0.95, edgecolor='black', fancybox=True)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    ax.set_axisbelow(True)
    
    # Add baseline
    ax.axhline(y=1, color='red', linestyle='--', linewidth=2, alpha=0.5, label='Baseline (equal)')
    
    plt.tight_layout()
    return fig

def main():
    """Main function"""
    print("\n" + "="*70)
    print("BEAUTIFUL NFS vs SCP BENCHMARK VISUALIZATIONS")
    print("(Limited to 3M lines, excluding 100K lines)")
    print("="*70 + "\n")
    
    print(f"Loading results from: {RESULTS_FILE}")
    df = load_results()
    print(f"Loaded {len(df)} records\n")
    
    print("Generating beautiful visualizations (up to 3M lines, excluding 100K)...\n")
    
    output_dir = SCRIPT_DIR
    
    # Plot 1: Grouped latency
    fig1 = plot_grouped_latency(df)
    fig1.savefig(os.path.join(output_dir, "01_latency_grouped.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: 01_latency_grouped.png")
    
    # Plot 2: Grouped throughput
    fig2 = plot_grouped_throughput(df)
    fig2.savefig(os.path.join(output_dir, "02_throughput_grouped.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: 02_throughput_grouped.png")
    
    # Plot 3: Speedup bars
    fig3 = plot_speedup_bars(df)
    fig3.savefig(os.path.join(output_dir, "03_speedup_comparison.png"), dpi=300, bbox_inches='tight', facecolor='white')
    print("  Saved: 03_speedup_comparison.png")
    
    print(f"\nAll visualizations saved to: {output_dir}")
    print("Total: 3 high-quality PNG files\n")

if __name__ == "__main__":
    main()
