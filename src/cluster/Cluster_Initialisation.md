#  Cluster Initialization Time - What Can Be Measured?

## Overview

Le temps d'initialisation du cluster dans votre projet inclut **plusieurs étapes**. Ce guide montre **exactement ce qui peut être mesuré** sans modifications de code.

---

## Composants Mesurables de l'Initialisation

### **Ce QU'ON PEUT Mesurer Facilement**

```
Total Initialization Time
├─ A) ClusterManager parsing (listing nodes)
├─ B) RMI registry creation on workers (10ms × N workers)
├─ C) Worker registration with master (RMI handshake)
├─ D) File compilation (if not done)
└─ E) SSH key exchange (first connection only)
```

### ** Ce QU'ON NE PEUT PAS Mesurer**

```
Network latency (hidden in SSH/RMI calls)
Worker startup time (happens in background)
Exact moment workers become "ready" (no health check)
Time to detect worker failures (no heartbeat)
```

---

## Mesurables Dans Votre Code

### **A) ClusterManager Parsing** (Very Fast - ~1ms)

**Ce qui se passe:**
```java
// Main.java, line 60
ClusterManager clusterManager = new ClusterManager(workerList);
```

**Logs générés:**
```
[CLUSTER] Initializing cluster with 4 nodes:
[CLUSTER]   - nancy-2:3000
[CLUSTER]   - nancy-3:3000
[CLUSTER]   - nancy-4:3000
[CLUSTER]   - nancy-5:3000
[CLUSTER] Master node: nancy-2 (coordination only)
[CLUSTER] Worker nodes: 3
[CLUSTER] Cluster initialized: 1 master + 3 worker(s)
```

**Comment mesurer:**
```bash
# Extraire le timing exact
time java -cp bin scheduler.Main "[localhost:3000]" 2>&1 | \
    grep "\[CLUSTER\]" | head -1  # Premiers log = début init

# Ou avec timestamps
date +%s%N; \
java -cp bin scheduler.Main "[localhost:3000]"; \
date +%s%N
```

**Temps réel:** ~1-5ms (parsing string + object creation)

---

### **B) RMI Registry Initialization** (Per Worker)

**Ce qui se passe:**
```java
// WorkerNode.java
LocateRegistry.createRegistry(port);  // ~10ms per worker
WorkerImpl worker = new WorkerImpl();
Naming.rebind(url, worker);           // ~20ms per worker
```

**Logs générés:**
```
[WORKER] Creating RMI registry on port 3000...
[WORKER] Worker ready and waiting for tasks!
```

**Comment mesurer:**
```bash
# Temps de startup d'un worker
time java -cp bin network.worker.WorkerNode localhost 3000 &
sleep 1  # Attendre que le worker démarre
pkill -f "WorkerNode"
```

**Temps réel:**
- Registry creation: ~10ms
- Worker registration: ~20ms
- **Total par worker: ~30ms**

---

### **C) Worker Discovery/Handshake** (Via First RMI Call)

**Ce qui se passe:**
```java
// MasterCoordinator.java or MasterCoordinatorNFS.java
String workerUrl = Configuration.buildRmiUrl(workerHost, workerPort);
WorkerInterface worker = (WorkerInterface) Naming.lookup(workerUrl);  // ← First contact!
int exitCode = worker.executeCommand(command);
```

**Logs générés:**
```
[MASTER] Connecting to worker: nancy-3:3000
[MASTER] Executing on nancy-3:3000: ./wordcount part1.txt
```

**Comment mesurer:**
```bash
# Temps du premier RMI lookup
time java -cp bin scheduler.Main "[localhost:3100,localhost:3101,localhost:3102]"
```

**Temps réel:**
- Local machine: ~5-10ms
- Same site (Grid5000): ~5-20ms
- Different sites: ~50-500ms (latency!)

---

### **D) SSH Connection Setup** (First Connection Only)

**Ce qui se passe au premier SSH:**
```bash
ssh nancy-3 "echo 'test'"  # First connection = key exchange
```

**Logs générés:** Aucun (silencieux)

**Comment mesurer:**
```bash
# Temps du premier SSH (avec key exchange)
time ssh nancy-3 "echo 'Connected'" 2>&1

# Temps SSH suivants (cached connection)
time ssh nancy-3 "echo 'Second call'" 2>&1
```

**Temps réel:**
- First SSH: ~100-300ms (handshake)
- Cached SSH: ~10-50ms (reuse connection)

---

##  Formule de Temps d'Initialisation

### **En Local (Localhost)**

```
T_init_local = T_cluster_manager + T_rmi_registry_total + T_first_rmi_call
             = 1ms + (30ms × N_workers) + 10ms
             = 1 + 30N + 10 ms
             
Exemple avec 3 workers:
T_init = 1 + 90 + 10 = 101 ms
```

### **Sur Grid5000 Mono-Site**

```
T_init_grid5000 = T_cluster_manager + T_ssh_setup + T_rmi_registry_total + T_ssh_job_overhead
                = 1ms + (100ms × 1 first SSH) + (30ms × N_workers) + 200ms
                = 1 + 100 + 30N + 200 ms
                
Exemple avec 4 nœuds (1 master + 3 workers):
T_init = 1 + 100 + 90 + 200 = 391 ms ≈ 0.4s
```

### **Sur Grid5000 Multi-Site**

```
T_init_multi = T_cluster_manager + T_ssh_per_site + T_rmi_registry_total + T_network_latency
             = 1ms + (100ms × M_sites) + (30ms × N_workers) + (100ms × N_workers) latency
             
Exemple: 2 sites, 2 workers chacun:
T_init = 1 + 200 + 60 + 200 = 461 ms ≈ 0.5s
```

---

## 📊 Tableau: Temps Mesurables vs Non-Mesurables

| Component | Mesurable? | Valeur Typique | Comment Mesurer |
|-----------|-----------|-----------------|-----------------|
| **ClusterManager parsing** | YES | 1-5ms | `time java scheduler.Main "[...]"` |
| **RMI registry creation** | YES | 10-20ms | Temps startup d'un worker |
| **First RMI lookup** | YES | 10-50ms (local) | Lookup seul |
| **SSH first connection** | YES (Grid5000) | 100-300ms | `time ssh node "echo test"` |
| **Worker readiness** |  PARTIAL | ~50-100ms | Attend log "Worker ready" |
| **Network propagation** | NO | Hidden | Dans les RMI calls |
| **OAR job overhead** |  PARTIAL | 200-500ms | Entre `oarsub` et première exécution |
| **Java startup** | YES | 100-500ms | `time java -version` |

---

##  Ce Qu'il FAUT Vraiment Mesurer

### **Pour Votre Modèle de Performance:**

```
T_init = T_Java_startup + T_ClusterManager + T_SSH_handshake + (T_RMI_per_worker × N_workers) + T_first_RMI_call

Temps RÉEL à mesurer:
1. T_total_main = time java scheduler.Main "[...]" (avant première tâche)
2. T_ssh = time ssh first_worker "echo test" (si Grid5000)
3. T_worker_startup = time java WorkerNode localhost 3000 (par worker)
4. T_rmi_handshake = Mesurer le premier executeCommand()
```

### **Formule Simplifiée Pour Votre Présentation:**

```
T_init_total ≈ 0.5s (local) à 1.5s (Grid5000 multi-site)

Composants principaux:
- Java startup: ~0.2-0.5s
- ClusterManager + RMI: ~0.1-0.3s
- SSH/Network overhead: ~0s (local) à 0.8s (multi-site)
```

---

## Recommandations

### **Pour Votre Benchmark:**

1. **Mesurer le temps TOTAL** (avec `time`)
2. **Soustraire le temps de calcul** (compilation + wordcount)
3. **Ce qui reste = overhead d'initialisation**

```bash
# Total time
TIME_TOTAL=$( { time java -cp bin scheduler.Main input.txt "[...]"; } 2>&1 | grep real)

# Est composé de:
# T_total = T_init + T_split + T_exec + T_agg

# T_init = ce qu'on cherche
T_INIT = T_TOTAL - T_SPLIT - T_EXEC - T_AGG
```

4. **Ne pas inclure le démarrage des workers** (c'est fait par le script de déploiement, pas par Java)
