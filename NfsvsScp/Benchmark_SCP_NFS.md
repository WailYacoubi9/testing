# File Transfer Benchmark - Grid5000 Execution Guide

## Overview

This benchmark compares 4 file transfer methods on Grid5000 to show why NFS mode is optimal for the wordcount-distributed system.

---

## What Does This Benchmark Measure?

### 1. SCP All-to-All (Test approach)
- **Complexity:** O(M × N) where M = partitions, N = workers
- **Description:** Each partition copied to EVERY worker
- **Performance:** Slowest approach, but simple

### 2. SCP One-to-One (Optimized SCP)
- **Complexity:** O(M)
- **Description:** Each partition copied to ONE specific worker (round-robin)
- **Performance:** Better but still requires transfers

### 3. SCP Parallel (Parallelized SCP)
- **Complexity:** O(M × N / P) with P parallel connections
- **Description:** Uses 8 parallel SCP transfers simultaneously
- **Performance:** Reduces latency but still has overhead

### 4. NFS (Recommended) 
- **Complexity:** O(1)
- **Description:** Zero explicit transfers (files shared via /home NFS)
- **Performance:** Optimal - **1000x faster than all-to-all!**
