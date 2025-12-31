package scheduler;

import cluster.ClusterManager;
import cluster.ComputeNode;
import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import parser.MakefileParser;
import parser.Task;
import parser.TaskStatus;
import utils.FileSplitter;

/**
 * Main entry point for the distributed word count system (MASTER NODE).
 * 
 * MASTER-ONLY ROLE:
 * - Splits input file into partitions
 * - Distributes partitions to worker nodes
 * - Coordinates task execution on workers (does NOT execute itself)
 * - Aggregates results from all workers
 * 
 * Worker nodes run independently - see WorkerNode.java
 */
public class Main {
    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DISTRIBUTED WORD COUNT - MASTER NODE (Coordinator)   ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 2) {
            System.err.println("MASTER NODE USAGE:");
            System.err.println("  java scheduler.Main <input-file> \"[worker1,worker2,worker3,...]\"");
            System.err.println("");
            System.err.println("This is the MASTER node that:");
            System.err.println("  1. Splits input file into N partitions (N = number of workers)");
            System.err.println("  2. Distributes partitions to worker nodes via SCP");
            System.err.println("  3. Coordinates execution on workers (does NOT execute locally)");
            System.err.println("  4. Aggregates results from all workers");
            System.err.println("");
            System.err.println("Worker nodes run SEPARATELY on each machine:");
            System.err.println("  java network.worker.WorkerNode <hostname> [port]");
            System.err.println("");
            System.err.println("Example:");
            System.err.println("  Master:  java scheduler.Main data.txt \"[worker1.grid5000.fr,worker2.grid5000.fr,worker3.grid5000.fr,worker4.grid5000.fr]\"");
            System.err.println("  Worker1: java network.worker.WorkerNode worker1.grid5000.fr 1099");
            System.err.println("  Worker2: java network.worker.WorkerNode worker2.grid5000.fr 1099");
            System.err.println("  Worker3: java network.worker.WorkerNode worker3.grid5000.fr 1099");
            System.err.println("  Worker4: java network.worker.WorkerNode worker4.grid5000.fr 1099");
            System.exit(1);
        }

        try {
            // Master node only accepts dynamic mode (input file + workers)
            String inputFile = args[0];
            String workerList = args[1];
            
            System.out.println("[MASTER] MASTER MODE: Auto-generating Makefile from input file");
            System.out.println("[MASTER] Input file: " + inputFile);
            System.out.println("[MASTER] Workers: " + workerList);

            // Initialize cluster with worker nodes (MASTER does NOT participate in execution)
            System.out.println("[MASTER] Initializing worker nodes...");
            ClusterManager clusterManager = new ClusterManager(workerList);
            int numWorkers = clusterManager.getNodes().size();
            System.out.println("[MASTER] " + numWorkers + " worker nodes configured");

            // Step 1: Split input file
            File file = new File(inputFile);
            if (!file.exists() || !file.isFile()) {
                System.err.println("[MASTER] Input file not found: " + inputFile);
                System.exit(1);
            }

            System.out.println("[MASTER] File size: " + file.length() + " bytes");
            System.out.println("[MASTER] Splitting file into " + numWorkers + " partitions...");

            // Split the input file into N parts (N = number of workers)
            List<String> splitFiles = FileSplitter.splitFileEquitably(inputFile, numWorkers, "part");
            System.out.println("[MASTER] Created " + splitFiles.size() + " partitions");

            // Step 2: Distribute split files to worker nodes
            System.out.println("[MASTER] Distributing partitions to worker nodes...");
            distributeSplitFiles(splitFiles, clusterManager);
            System.out.println("[MASTER] All partitions distributed");
            // Step 3: Generate Makefile
            String makefilePath = "Makefile.generated";
            System.out.println("[MASTER] Generating task specification...");
            generateMakefile(makefilePath, splitFiles);
            System.out.println("[MASTER] Task specification generated");
            // Step 4: Parse task specification
            System.out.println("[MASTER] Parsing task specification...");
            MakefileParser parser = new MakefileParser();
            Map<Task, List<Task>> graph = parser.processFile(makefilePath);

            if (graph.isEmpty()) {
                System.err.println("[MASTER] No tasks found in specification. Exiting.");
                System.exit(1);
            }

            parser.printGraph();

            // Step 5: Configure all tasks to execute on workers
            System.out.println("[MASTER] Configuring tasks for execution on workers...");

            // First, collect all tasks (including those only in dependency lists)
            Set<Task> allTasks = new HashSet<>(graph.keySet());
            for (List<Task> deps : graph.values()) {
                allTasks.addAll(deps);
            }

            // Configure all tasks
            for (Task task : allTasks) {
                task.setClusterManager(clusterManager);
                // Tasks with no commands represent files that already exist
                if (task.getCommands().isEmpty()) {
                    task.setStatus(TaskStatus.FINISHED);
                    System.out.println("[MASTER] File/partition " + task.getTaskName() + " marked as FINISHED");
                }
            }

            // Step 6: Create and execute task scheduler

            TaskScheduler scheduler = new TaskScheduler();

            for (Map.Entry<Task, List<Task>> entry : graph.entrySet()) {
                scheduler.addTask(entry.getKey(), entry.getValue());
            }

            System.out.println("[MASTER] Scheduler configured with " + scheduler.getTaskCount() + " tasks");
            System.out.println("[MASTER] Starting task coordination on workers...\n");

            scheduler.executeTasks();

            System.out.println("\n[MASTER] All worker tasks completed successfully!");

            // Step 7: Cleanup
            System.out.println("\n[MASTER] Cleaning up temporary files...");
            FileSplitter.cleanupFiles(splitFiles);
            new File(makefilePath).delete();
            System.out.println("[MASTER] Cleanup complete");
            System.out.println("[MASTER] Distributed execution completed!");


        } catch (IllegalArgumentException e) {
            System.err.println("\n[MASTER] Configuration error: " + e.getMessage());
            System.exit(1);
        } catch (java.io.FileNotFoundException e) {
            System.err.println("\n[MASTER] Task specification not found: " + e.getMessage());
            System.err.println("[MASTER] Please ensure input file exists");
            System.exit(1);
        } catch (java.io.IOException e) {
            System.err.println("\n[MASTER] IO error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("\n[MASTER] Coordination interrupted: " + e.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("\n[MASTER] Unexpected error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    /**
     * Distributes split partitions to all worker nodes using SCP.
     * Master sends each partition to its designated worker.
     */
    private static void distributeSplitFiles(List<String> splitFiles, ClusterManager clusterManager) {
        List<ComputeNode> nodes = clusterManager.getNodes();
        
        // Distribute partitions round-robin to workers
        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            ComputeNode targetWorker = nodes.get(i % nodes.size());
            
            try {
                String hostname = targetWorker.hostname;
                System.out.println("[MASTER] Sending " + splitFile + " → " + hostname);
                String[] command = {"scp", "-q", splitFile, hostname + ":~/"};
                Process process = Runtime.getRuntime().exec(command);
                int exitCode = process.waitFor();

                if (exitCode != 0) {
                    System.err.println("[MASTER] ⚠️  Failed to copy " + splitFile + " to " + hostname);
                }
            } catch (Exception e) {
                System.err.println("[MASTER] Error distributing " + splitFile + ": " + e.getMessage());
            }
        }
        System.out.println("[MASTER] All partitions distributed to workers");
    }

    /**
     * Generates task specification (Makefile) for worker execution.
     * 
     * IMPORTANT: All tasks in this Makefile execute on WORKERS, not the master.
     * 
     * Dependency graph:
     * - wordcount binary depends on test/wordcount.c (available on workers)
     * - count*.txt depends on part*.txt (distributed) + wordcount (binary compilation)
     * - total.txt depends on all count*.txt (aggregates results)
     */
    private static void generateMakefile(String makefilePath, List<String> splitFiles) throws Exception {
        PrintWriter writer = new PrintWriter(new FileWriter(makefilePath));

        writer.println("# Task Specification for Worker Nodes");
        writer.println("# Generated by MASTER - All tasks execute on WORKERS");
        writer.println();

        // Generate wordcount binary target
        writer.println("wordcount: test/wordcount.c");
        writer.println("\tgcc -o wordcount test/wordcount.c");
        writer.println();

        // Generate count targets for each partition
        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            String countFile = "count" + (i + 1) + ".txt";

            writer.println(countFile + ": " + splitFile + " wordcount");
            writer.println("\t./wordcount " + splitFile + " > " + countFile);
            writer.println();
        }

        // Generate total.txt target (aggregation)
        writer.print("total.txt:");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" count" + (i + 1) + ".txt");
        }
        writer.println();
        writer.print("\tcat");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" count" + (i + 1) + ".txt");
        }
        writer.println(" | awk '{sum += $1} END {print sum}' > total.txt");

        writer.close();
        System.out.println("[MASTER] Task specification generated with " + splitFiles.size() + " partitions");
    }
}
