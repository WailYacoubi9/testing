package parser;

import cluster.ClusterManager;
import cluster.ComputeNode;
import config.Configuration;
import network.master.MasterCoordinator;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Represents a task with commands to execute.
 * Refactored to remove static dependencies and improve error handling.
 */
public class Task {
    private final String taskName;
    private final List<String> commands;
    private volatile TaskStatus status;
    private final ClusterManager clusterManager;
    private final Random random;

    /**
     * Creates a task with empty name (for special tasks like targets without commands).
     */
    public Task() {
        this("", null);
    }

    /**
     * Creates a task with a name but no cluster manager (for parsing only).
     * @param name The task name
     */
    public Task(String name) {
        this(name, null);
    }

    /**
     * Creates a fully configured task ready for execution.
     * @param name The task name
     * @param clusterManager The cluster manager for node allocation
     */
    public Task(String name, ClusterManager clusterManager) {
        if (name == null) {
            throw new IllegalArgumentException("Task name cannot be null");
        }
        this.taskName = name;
        this.commands = new ArrayList<>();
        this.status = TaskStatus.NOT_STARTED;
        this.clusterManager = clusterManager;
        this.random = new Random();
    }

    public String getTaskName() {
        return taskName;
    }

    public List<String> getCommands() {
        return new ArrayList<>(commands); // Return defensive copy
    }

    /**
     * Gets the current status of this task.
     * Thread-safe using volatile.
     * @return The current task status
     */
    public TaskStatus getStatus() {
        return status;
    }

    /**
     * Sets the status of this task.
     * Thread-safe using volatile.
     * @param status The new status
     */
    public void setStatus(TaskStatus status) {
        if (status == null) {
            throw new IllegalArgumentException("Status cannot be null");
        }
        this.status = status;
    }

    /**
     * Adds a command to this task.
     * @param command The command string
     * @throws IllegalArgumentException if command is null or empty
     */
    public void addCommand(String command) {
        if (command == null || command.trim().isEmpty()) {
            throw new IllegalArgumentException("Command cannot be null or empty");
        }
        this.commands.add(command);
    }

    /**
     * Sets the cluster manager for this task (used after parsing).
     * @param manager The cluster manager
     */
    public void setClusterManager(ClusterManager manager) {
        if (manager == null) {
            throw new IllegalArgumentException("ClusterManager cannot be null");
        }
        // Using reflection to set final field - not ideal but works for this case
        try {
            java.lang.reflect.Field field = Task.class.getDeclaredField("clusterManager");
            field.setAccessible(true);
            field.set(this, manager);
        } catch (Exception e) {
            throw new RuntimeException("Failed to set cluster manager", e);
        }
    }

    /**
     * Checks if this task is a final aggregation task that should run on master.
     * Aggregation tasks combine results from multiple workers and should have
     * access to all intermediate result files.
     * @return true if this is an aggregation task
     */
    private boolean isAggregationTask() {
        // Detect if this is the final aggregation (total.txt)
        // or any task that aggregates multiple count files
        return taskName.equals("total.txt") ||
               (commands.stream().anyMatch(cmd ->
                   cmd.contains("cat") && cmd.contains("count") && cmd.contains("awk")));
    }

    /**
     * Executes all commands for this task.
     * This method is thread-safe and handles node allocation properly.
     * Aggregation tasks run locally on the master to ensure access to all result files.
     */
    public void execute() {
        if (clusterManager == null) {
            System.err.println("[TASK " + taskName + "] ❌ No cluster manager configured");
            this.status = TaskStatus.FAILED;
            return;
        }

        if (commands.isEmpty()) {
            System.out.println("[TASK " + taskName + "] No commands to execute, marking as finished");
            this.status = TaskStatus.FINISHED;
            return;
        }

        try {
            // Aggregation tasks must run on the master node where all result files are collected
            if (isAggregationTask()) {
                System.out.println("[TASK " + taskName + "] 📊 Running aggregation locally on master node");
                for (String command : commands) {
                    if (!executeLocalCommand(command)) {
                        return; // Status already set to FAILED
                    }
                }
            } else {
                // Regular tasks can be distributed to any available worker
                for (String command : commands) {
                    if (!executeCommand(command)) {
                        return; // Status already set to FAILED
                    }
                }
            }

            this.status = TaskStatus.FINISHED;

        } catch (Exception e) {
            System.err.println("[TASK " + taskName + "] Exception: " + e.getMessage());
            e.printStackTrace();
            this.status = TaskStatus.FAILED;
        }
    }

    /**
     * Executes a command locally on the master node using bash.
     * Used for aggregation tasks that need access to all result files.
     * @param command The command to execute
     * @return true if successful, false if failed
     */
    private boolean executeLocalCommand(String command) {
        System.out.println("[TASK " + taskName + "] Executing locally: " + command);

        try {
            // Use bash -c to properly handle shell commands with pipes
            String[] execCommand = {"/bin/bash", "-c", command};
            Process process = Runtime.getRuntime().exec(execCommand);
            int exitCode = process.waitFor();

            if (exitCode == 0) {
                System.out.println("[TASK " + taskName + "] ✅ Local execution successful");
                return true;
            } else {
                // Print error output for diagnostics
                java.io.BufferedReader errorReader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(process.getErrorStream()));
                String line;
                System.err.println("[TASK " + taskName + "] ❌ Local execution failed with exit code: " + exitCode);
                while ((line = errorReader.readLine()) != null) {
                    System.err.println("[ERROR] " + line);
                }
                this.status = TaskStatus.FAILED;
                return false;
            }
        } catch (Exception e) {
            System.err.println("[TASK " + taskName + "] ❌ Exception during local execution: " + e.getMessage());
            e.printStackTrace();
            this.status = TaskStatus.FAILED;
            return false;
        }
    }

    /**
     * Executes a single command on an available worker.
     * @param command The command to execute
     * @return true if successful, false if failed
     */
    private boolean executeCommand(String command) {
        System.out.println("[TASK " + taskName + "] Searching for available worker...");

        ComputeNode availableWorker = null;
        int retryCount = 0;
        final int MAX_RETRIES = 100; // Prevent infinite loops

        while (availableWorker == null && retryCount < MAX_RETRIES) {
            availableWorker = clusterManager.acquireAvailableNode();

            if (availableWorker == null) {
                retryCount++;
                if (retryCount % 10 == 0) {
                    System.out.println("[TASK " + taskName + "] All workers busy, waiting... (retry " + retryCount + ")");
                }
                try {
                    Thread.sleep(Configuration.TASK_RETRY_BASE_WAIT_MS +
                                random.nextInt(Configuration.TASK_RETRY_RANDOM_RANGE_MS));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    System.err.println("[TASK " + taskName + "] Interrupted while waiting for worker");
                    this.status = TaskStatus.FAILED;
                    return false;
                }
            }
        }

        if (availableWorker == null) {
            System.err.println("[TASK " + taskName + "] ❌ Failed to acquire worker after " + MAX_RETRIES + " retries");
            this.status = TaskStatus.FAILED;
            return false;
        }

        try {
            System.out.println("[TASK " + taskName + "] Assigned to worker: " + availableWorker.hostname + ":" + availableWorker.port);

            int exitCode = MasterCoordinator.executeOnWorker(
                command,
                availableWorker.hostname,
                availableWorker.port,
                clusterManager.getMasterNode().hostname,
                this.taskName
            );

            if (exitCode == 0) {
                System.out.println("[TASK " + taskName + "] ✅ Completed successfully on " + availableWorker.hostname + ":" + availableWorker.port);
                return true;
            } else {
                System.err.println("[TASK " + taskName + "] ❌ Failed with exit code: " + exitCode);
                this.status = TaskStatus.FAILED;
                return false;
            }

        } finally {
            // Always release the node, even if execution failed
            clusterManager.releaseNode(availableWorker);
        }
    }

    @Override
    public String toString() {
        return "Task{name='" + taskName + "', status=" + status + ", commands=" + commands.size() + '}';
    }
}
