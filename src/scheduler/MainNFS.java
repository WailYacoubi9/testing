package scheduler;

import utils.TimingManager;
import parser.MakefileParser;
import parser.TaskNFS;
import parser.TaskStatus;
import cluster.ClusterManager;
import utils.FileSplitter;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class MainNFS {
    private static final String DEFAULT_NFS_PATH = "/tmp/nfs_shared";

    public static void main(String[] args) {
        TimingManager.startTiming();

        if (args.length < 1) {
            System.err.println("Usage:");
            System.err.println("  Static mode:  java scheduler.MainNFS \"[worker1,worker2,...]\" [nfs-path]");
            System.err.println("  Dynamic mode: java scheduler.MainNFS <input-file> \"[worker1,worker2,...]\" [nfs-path]");
            System.exit(1);
        }

        try {
            TimingManager.timestamp("ARGUMENTS_PARSED");

            boolean dynamicMode = args.length >= 2 && !args[0].startsWith("[");
            String inputFile = null;
            String workerList = null;
            String nfsPath = DEFAULT_NFS_PATH;
            String makefilePath = "Makefile";
            List<String> splitFiles = null;

            if (dynamicMode) {
                inputFile = args[0];
                workerList = args[1];
                if (args.length >= 3) {
                    nfsPath = args[2];
                }
                System.out.println("[MAIN-NFS] Dynamic mode: Auto-generating Makefile from input file");
                System.out.println("[MAIN-NFS] Input file: " + inputFile);
                System.out.println("[MAIN-NFS] NFS shared path: " + nfsPath);
            } else {
                workerList = args[0];
                if (args.length >= 2) {
                    nfsPath = args[1];
                }
                System.out.println("[MAIN-NFS] Static mode: Using existing Makefile");
                System.out.println("[MAIN-NFS] NFS shared path: " + nfsPath);
            }

            File nfsDir = new File(nfsPath);
            if (!nfsDir.exists()) {
                System.out.println("[MAIN-NFS] Creating NFS directory: " + nfsPath);
                if (!nfsDir.mkdirs()) {
                    System.err.println("[MAIN-NFS] Failed to create NFS directory");
                    System.exit(1);
                }
            }

            System.out.println("[MAIN-NFS] Initializing cluster...");
            TimingManager.timestamp("CLUSTER_INIT_START");
            ClusterManager clusterManager = new ClusterManager(workerList);
            int numWorkers = clusterManager.getNodes().size();
            TimingManager.timestamp("CLUSTER_INITIALIZED");

            if (dynamicMode) {
                TimingManager.timestamp("FILE_PROCESSING_START");

                File file = new File(inputFile);
                if (!file.exists() || !file.isFile()) {
                    System.err.println("[MAIN-NFS] Input file not found: " + inputFile);
                    System.exit(1);
                }

                System.out.println("[MAIN-NFS] File size: " + file.length() + " bytes");
                System.out.println("[MAIN-NFS] Splitting file into " + numWorkers + " parts in NFS directory...");

                TimingManager.timestamp("FILE_SPLITTING_START");
                String nfsPrefix = nfsPath + "/part";
                splitFiles = FileSplitter.splitFileEquitably(inputFile, numWorkers, nfsPrefix);
                TimingManager.timestamp("FILE_SPLITTED");

                System.out.println("[MAIN-NFS] Files available in shared NFS directory");
                TimingManager.timestamp("FILES_DISTRIBUTED");

                makefilePath = nfsPath + "/Makefile.generated";
                System.out.println("[MAIN-NFS] Generating Makefile: " + makefilePath);
                TimingManager.timestamp("MAKEFILE_GENERATION_START");
                generateMakefileNFS(makefilePath, splitFiles, nfsPath);
                TimingManager.timestamp("MAKEFILE_GENERATED");

                TimingManager.timestamp("FILE_PROCESSING_COMPLETED");
            }

            System.out.println("[MAIN-NFS] Parsing Makefile...");
            TimingManager.timestamp("MAKEFILE_PARSING_START");
            MakefileParser parser = new MakefileParser();
            Map<TaskNFS, List<TaskNFS>> graph = parser.processFileNFS(makefilePath);
            TimingManager.timestamp("MAKEFILE_PARSED");

            if (graph.isEmpty()) {
                System.err.println("[MAIN-NFS] No tasks found in Makefile. Exiting.");
                System.exit(1);
            }

            parser.printGraphNFS();

            System.out.println("[MAIN-NFS] Configuring tasks with cluster manager and NFS path...");
            TimingManager.timestamp("TASK_CONFIGURATION_START");

            Set<TaskNFS> allTasks = new HashSet<>(graph.keySet());
            for (List<TaskNFS> deps : graph.values()) {
                allTasks.addAll(deps);
            }

            for (TaskNFS task : allTasks) {
                task.setClusterManager(clusterManager);
                task.setNfsPath(nfsPath);
                if (task.getCommands().isEmpty()) {
                    task.setStatus(TaskStatus.FINISHED);
                    System.out.println("[MAIN-NFS] File dependency " + task.getTaskName() + " marked as FINISHED");
                }
            }
            TimingManager.timestamp("TASKS_CONFIGURED");

            System.out.println("[MAIN-NFS] Creating task scheduler...");
            TaskScheduler scheduler = new TaskScheduler();

            for (Map.Entry<TaskNFS, List<TaskNFS>> entry : graph.entrySet()) {
                scheduler.addTaskNFS(entry.getKey(), entry.getValue());
            }

            System.out.println("[MAIN-NFS] Scheduler configured with " + scheduler.getTaskCount() + " tasks");
            System.out.println("[MAIN-NFS] Starting distributed execution...");

            TimingManager.timestamp("DISTRIBUTED_EXECUTION_START");
            scheduler.executeTasks();
            TimingManager.timestamp("EXECUTION_COMPLETED");

            System.out.println("[MAIN-NFS] Distributed execution completed successfully!");

            // =================================================================
            // CALCUL DES METRIQUES ET AFFICHAGE POUR LE CSV
            // =================================================================
            try {
                long tStart = TimingManager.getTime("START");

                // Calcul Bootstrap (Start -> Split)
                Long tSplitStartObj = TimingManager.getTime("FILE_SPLITTING_START");
                long tSplitStart = (tSplitStartObj != null) ? tSplitStartObj : tStart;
                long bootstrapTime = tSplitStart - tStart;

                System.out.println("[METRICS] BOOTSTRAP_TIME_MS=" + bootstrapTime);

                // Calcul MAP vs REDUCE (si disponible)
                Long tExecStartObj = TimingManager.getTime("DISTRIBUTED_EXECUTION_START");
                Long tExecEndObj = TimingManager.getTime("EXECUTION_COMPLETED");
                Long tReduceStartObj = TimingManager.getTime("REDUCE_START");

                if (tExecStartObj != null && tExecEndObj != null && tReduceStartObj != null) {
                    long mapTime = tReduceStartObj - tExecStartObj;
                    long reduceTime = tExecEndObj - tReduceStartObj;
                    System.out.println("Temps MAP (Calcul)    : " + mapTime + " ms");
                    System.out.println("Temps REDUCE (Merge)  : " + reduceTime + " ms");
                    System.out.println("Temps TOTAL           : " + (tExecEndObj - tExecStartObj) + " ms");
                }

            } catch (Exception e) {
                System.err.println("[MAIN-NFS] Warning: Could not calculate detailed metrics: " + e.getMessage());
            }
            // =================================================================

            TimingManager.printReport();

            File resultFile = new File(nfsPath + "/total.txt");
            if (resultFile.exists()) {
                try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(resultFile))) {
                    String result = reader.readLine();
                    System.out.println("Total word count: " + result);
                }
            }

        } catch (IllegalArgumentException e) {
            System.err.println("[MAIN-NFS] Configuration error: " + e.getMessage());
            System.exit(1);
        } catch (java.io.FileNotFoundException e) {
            System.err.println("[MAIN-NFS] Makefile not found: " + e.getMessage());
            System.exit(1);
        } catch (java.io.IOException e) {
            System.err.println("[MAIN-NFS] IO error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("[MAIN-NFS] Execution interrupted: " + e.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("[MAIN-NFS] Unexpected error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    private static void generateMakefileNFS(String makefilePath, List<String> splitFiles, String nfsPath) throws Exception {
        PrintWriter writer = new PrintWriter(new FileWriter(makefilePath));

        String projectDir = System.getProperty("user.home") + "/wordcount-distributed";
        String wordcountSource = projectDir + "/test/wordcount.c";

        writer.println("wordcount: " + wordcountSource);
        writer.println("\tgcc -o " + nfsPath + "/wordcount " + wordcountSource);
        writer.println();

        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            String countFile = nfsPath + "/count" + (i + 1) + ".txt";

            writer.println(countFile + ": " + splitFile + " wordcount");
            writer.println("\t" + nfsPath + "/wordcount " + splitFile + " > " + countFile);
            writer.println();
        }

        writer.print(nfsPath + "/total.txt:");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" " + nfsPath + "/count" + (i + 1) + ".txt");
        }
        writer.println();
        writer.print("\tcat");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" " + nfsPath + "/count" + (i + 1) + ".txt");
        }
        writer.println(" | awk '{sum += $1} END {print sum}' > " + nfsPath + "/total.txt");

        writer.close();
        System.out.println("[MAIN-NFS] Makefile generated with " + splitFiles.size() + " parts (NFS paths)");
    }
}
