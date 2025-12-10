package scheduler;

import config.Configuration;
import parser.Task;
import parser.TaskNFS;
import parser.TaskStatus;

import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * Schedules and executes tasks based on their dependencies.
 * Refactored to remove static state and improve testability.
 * Supports both Task (SCP) and TaskNFS (NFS) versions.
 */
public class TaskScheduler {
    private final Map<Task, List<Task>> dependencyGraph;
    private final Map<TaskNFS, List<TaskNFS>> dependencyGraphNFS;

    public TaskScheduler() {
        this.dependencyGraph = new HashMap<>();
        this.dependencyGraphNFS = new HashMap<>();
    }

    /**
     * Adds a task with its dependencies to the scheduler.
     * @param task The task to add
     * @param dependencies List of tasks that must complete before this task
     * @throws IllegalArgumentException if task is null
     */
    public void addTask(Task task, List<Task> dependencies) {
        if (task == null) {
            throw new IllegalArgumentException("Task cannot be null");
        }
        if (dependencies == null) {
            dependencies = new ArrayList<>();
        }
        dependencyGraph.put(task, dependencies);
    }

    /**
     * Executes all tasks in the dependency graph, respecting dependencies.
     * Automatically detects whether SCP (Task) or NFS (TaskNFS) mode is being used.
     * @throws InterruptedException if execution is interrupted
     * @throws IllegalStateException if no tasks are scheduled
     */
    public void executeTasks() throws InterruptedException {
        // Detect which mode we're in
        boolean isSCPMode = !dependencyGraph.isEmpty();
        boolean isNFSMode = !dependencyGraphNFS.isEmpty();

        if (!isSCPMode && !isNFSMode) {
            throw new IllegalStateException("No tasks scheduled for execution");
        }

        if (isSCPMode) {
            executeTasksSCP();
        } else {
            executeTasksNFS();
        }
    }

    /**
     * Executes tasks in SCP mode.
     */
    private void executeTasksSCP() throws InterruptedException {
        System.out.println("\n[SCHEDULER] Starting task execution (SCP mode)...");
        ExecutorService executor = Executors.newCachedThreadPool();

        int iteration = 0;
        while (!allTasksCompleted()) {
            iteration++;
            System.out.println("\n[SCHEDULER] Iteration " + iteration + " - Checking for ready tasks...");

            for (Map.Entry<Task, List<Task>> entry : dependencyGraph.entrySet()) {
                Task task = entry.getKey();

                if (canBeExecuted(task)) {
                    task.setStatus(TaskStatus.IN_PROGRESS);
                    System.out.println("[SCHEDULER] Launching task: " + task.getTaskName());
                    executor.submit(task::execute);
                }
            }

            Thread.sleep(Configuration.SCHEDULER_POLL_INTERVAL_MS);
        }

        System.out.println("\n[SCHEDULER] All tasks submitted, waiting for completion...");
        executor.shutdown();
        if (!executor.awaitTermination(Configuration.SCHEDULER_TIMEOUT_HOURS, TimeUnit.HOURS)) {
            System.err.println("[SCHEDULER] ⚠️  Timeout waiting for tasks to complete");
            executor.shutdownNow();
        }

        System.out.println("\n[SCHEDULER] ✅ All tasks completed!");
        printFinalStatus();
    }

    /**
     * Executes tasks in NFS mode.
     */
    private void executeTasksNFS() throws InterruptedException {
        System.out.println("\n[SCHEDULER-NFS] Starting task execution (NFS mode)...");
        ExecutorService executor = Executors.newCachedThreadPool();

        int iteration = 0;
        while (!allTasksCompletedNFS()) {
            iteration++;
            System.out.println("\n[SCHEDULER-NFS] Iteration " + iteration + " - Checking for ready tasks...");

            for (Map.Entry<TaskNFS, List<TaskNFS>> entry : dependencyGraphNFS.entrySet()) {
                TaskNFS task = entry.getKey();

                if (canBeExecutedNFS(task)) {
                    task.setStatus(TaskStatus.IN_PROGRESS);
                    System.out.println("[SCHEDULER-NFS] Launching task: " + task.getTaskName());
                    executor.submit(task::execute);
                }
            }

            Thread.sleep(Configuration.SCHEDULER_POLL_INTERVAL_MS);
        }

        System.out.println("\n[SCHEDULER-NFS] All tasks submitted, waiting for completion...");
        executor.shutdown();
        if (!executor.awaitTermination(Configuration.SCHEDULER_TIMEOUT_HOURS, TimeUnit.HOURS)) {
            System.err.println("[SCHEDULER-NFS] ⚠️  Timeout waiting for tasks to complete");
            executor.shutdownNow();
        }

        System.out.println("\n[SCHEDULER-NFS] ✅ All tasks completed!");
        printFinalStatusNFS();
    }

    /**
     * Checks if a task can be executed based on its status and dependencies.
     * @param task The task to check
     * @return true if the task can be executed now
     */
    private boolean canBeExecuted(Task task) {
        if (task.getStatus() != TaskStatus.NOT_STARTED) {
            return false;
        }

        List<Task> dependencies = dependencyGraph.get(task);
        if (dependencies == null || dependencies.isEmpty()) {
            return true;
        }

        return dependencies.stream()
                .allMatch(dep -> dep.getStatus() == TaskStatus.FINISHED);
    }

    /**
     * Checks if all tasks have completed (either finished or failed).
     * @return true if all tasks are done
     */
    private boolean allTasksCompleted() {
        return dependencyGraph.keySet().stream()
                .allMatch(task -> task.getStatus() == TaskStatus.FINISHED ||
                                  task.getStatus() == TaskStatus.FAILED);
    }

    /**
     * Prints the final status of all tasks.
     */
    private void printFinalStatus() {
        System.out.println("\n[SCHEDULER] Final Status:");
        System.out.println("========================");
        for (Task task : dependencyGraph.keySet()) {
            String statusSymbol = task.getStatus() == TaskStatus.FINISHED ? "✅" : "❌";
            System.out.println(statusSymbol + " " + task.getTaskName() + " - " + task.getStatus());
        }
        System.out.println("========================\n");
    }

    /**
     * Gets the number of tasks in the scheduler.
     * @return The task count
     */
    public int getTaskCount() {
        if (!dependencyGraph.isEmpty()) {
            return dependencyGraph.size();
        }
        return dependencyGraphNFS.size();
    }

    // ==================== NFS VERSION METHODS ====================

    /**
     * Adds an NFS task with its dependencies to the scheduler.
     */
    public void addTaskNFS(TaskNFS task, List<TaskNFS> dependencies) {
        if (task == null) {
            throw new IllegalArgumentException("Task cannot be null");
        }
        if (dependencies == null) {
            dependencies = new ArrayList<>();
        }
        dependencyGraphNFS.put(task, dependencies);
    }

    /**
     * Checks if an NFS task can be executed.
     */
    private boolean canBeExecutedNFS(TaskNFS task) {
        if (task.getStatus() != TaskStatus.NOT_STARTED) {
            return false;
        }

        List<TaskNFS> dependencies = dependencyGraphNFS.get(task);
        if (dependencies == null || dependencies.isEmpty()) {
            return true;
        }

        return dependencies.stream()
                .allMatch(dep -> dep.getStatus() == TaskStatus.FINISHED);
    }

    /**
     * Checks if all NFS tasks have completed.
     */
    private boolean allTasksCompletedNFS() {
        return dependencyGraphNFS.keySet().stream()
                .allMatch(task -> task.getStatus() == TaskStatus.FINISHED ||
                                  task.getStatus() == TaskStatus.FAILED);
    }

    /**
     * Prints the final status of all NFS tasks.
     */
    private void printFinalStatusNFS() {
        System.out.println("\n[SCHEDULER-NFS] Final Status:");
        System.out.println("========================");
        for (TaskNFS task : dependencyGraphNFS.keySet()) {
            String statusSymbol = task.getStatus() == TaskStatus.FINISHED ? "✅" : "❌";
            System.out.println(statusSymbol + " " + task.getTaskName() + " - " + task.getStatus());
        }
        System.out.println("========================\n");
    }
}
