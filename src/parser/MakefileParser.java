package parser;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.*;

/**
 * Parses Makefile format and builds a dependency graph.
 * Improved error handling and validation.
 */
public class MakefileParser {
    private BufferedReader reader;
    private String currentLine;
    private final HashMap<Task, List<Task>> graph;
    private final HashMap<String, Task> taskMap;

    public MakefileParser() {
        this.graph = new HashMap<>();
        this.taskMap = new HashMap<>();
    }

    /**
     * Processes a Makefile and returns the dependency graph.
     * @param filePath Path to the Makefile
     * @return A map of tasks to their dependencies
     * @throws IOException if file cannot be read
     * @throws IllegalArgumentException if filePath is null or empty
     */
    public HashMap<Task, List<Task>> processFile(String filePath) throws IOException {
        if (filePath == null || filePath.trim().isEmpty()) {
            throw new IllegalArgumentException("File path cannot be null or empty");
        }

        System.out.println("[PARSER] Reading Makefile from: " + filePath);

        try {
            reader = new BufferedReader(new FileReader(filePath));
            currentLine = reader.readLine();

            while (currentLine != null) {
                parseRule();
                currentLine = reader.readLine();
            }

            reader.close();
            System.out.println("[PARSER] Successfully parsed Makefile: " + graph.size() + " tasks found");

            if (graph.isEmpty()) {
                System.err.println("[PARSER] ⚠️  Warning: No tasks found in Makefile");
            }

        } catch (IOException e) {
            System.err.println("[PARSER] ❌ Error reading Makefile: " + e.getMessage());
            throw e; // Re-throw instead of silently continuing
        }

        return graph;
    }

    private void parseRule() {
        if (currentLine == null || currentLine.trim().isEmpty() || currentLine.startsWith("#")) {
            return;
        }

        if (currentLine.contains(":") && !currentLine.startsWith("\t")) {
            String[] parts = currentLine.split(":", 2);
            String targetName = parts[0].trim();
            String dependenciesStr = parts.length > 1 ? parts[1].trim() : "";

            Task targetTask = taskMap.getOrDefault(targetName, new Task(targetName));
            taskMap.put(targetName, targetTask);

            List<Task> dependencies = new ArrayList<>();
            if (!dependenciesStr.isEmpty()) {
                String[] depNames = dependenciesStr.split("\\s+");
                for (String depName : depNames) {
                    if (!depName.trim().isEmpty()) {
                        Task depTask = taskMap.getOrDefault(depName, new Task(depName));
                        taskMap.put(depName, depTask);
                        dependencies.add(depTask);
                    }
                }
            }

            try {
                currentLine = reader.readLine();
                while (currentLine != null && currentLine.startsWith("\t")) {
                    String command = currentLine.substring(1);
                    if (!command.trim().isEmpty()) {
                        targetTask.addCommand(command);
                    }
                    currentLine = reader.readLine();
                }
            } catch (IOException e) {
                System.err.println("[PARSER] Error reading commands for task " + targetName);
                e.printStackTrace();
            }

            graph.put(targetTask, dependencies);
        }
    }

    public void printGraph() {
        System.out.println("\n[PARSER] Dependency Graph:");
        System.out.println("========================");
        for (Map.Entry<Task, List<Task>> entry : graph.entrySet()) {
            Task task = entry.getKey();
            List<Task> deps = entry.getValue();
            System.out.print(task.getTaskName() + " depends on: ");
            if (deps.isEmpty()) {
                System.out.println("nothing (can start immediately)");
            } else {
                System.out.println(deps.stream()
                    .map(Task::getTaskName)
                    .reduce((a, b) -> a + ", " + b)
                    .orElse(""));
            }
            System.out.println("  Commands: " + task.getCommands().size());
        }
        System.out.println("========================\n");
    }

    /**
     * Gets the task map (for testing purposes).
     * @return The map of task names to tasks
     */
    public Map<String, Task> getTaskMap() {
        return Collections.unmodifiableMap(taskMap);
    }

    // ==================== NFS VERSION METHODS ====================

    private HashMap<TaskNFS, List<TaskNFS>> graphNFS;
    private HashMap<String, TaskNFS> taskMapNFS;

    /**
     * Processes a Makefile and returns the dependency graph for NFS-based tasks.
     * @param filePath Path to the Makefile
     * @return A map of TaskNFS to their dependencies
     * @throws IOException if file cannot be read
     */
    public HashMap<TaskNFS, List<TaskNFS>> processFileNFS(String filePath) throws IOException {
        if (filePath == null || filePath.trim().isEmpty()) {
            throw new IllegalArgumentException("File path cannot be null or empty");
        }

        this.graphNFS = new HashMap<>();
        this.taskMapNFS = new HashMap<>();

        System.out.println("[PARSER-NFS] Reading Makefile from: " + filePath);

        try {
            reader = new BufferedReader(new FileReader(filePath));
            currentLine = reader.readLine();

            while (currentLine != null) {
                parseRuleNFS();
                currentLine = reader.readLine();
            }

            reader.close();
            System.out.println("[PARSER-NFS] Successfully parsed Makefile: " + graphNFS.size() + " tasks found");

            if (graphNFS.isEmpty()) {
                System.err.println("[PARSER-NFS] ⚠️  Warning: No tasks found in Makefile");
            }

        } catch (IOException e) {
            System.err.println("[PARSER-NFS] ❌ Error reading Makefile: " + e.getMessage());
            throw e;
        }

        return graphNFS;
    }

    private void parseRuleNFS() {
        if (currentLine == null || currentLine.trim().isEmpty() || currentLine.startsWith("#")) {
            return;
        }

        if (currentLine.contains(":") && !currentLine.startsWith("\t")) {
            String[] parts = currentLine.split(":", 2);
            String targetName = parts[0].trim();
            String dependenciesStr = parts.length > 1 ? parts[1].trim() : "";

            TaskNFS targetTask = taskMapNFS.getOrDefault(targetName, new TaskNFS(targetName));
            taskMapNFS.put(targetName, targetTask);

            List<TaskNFS> dependencies = new ArrayList<>();
            if (!dependenciesStr.isEmpty()) {
                String[] depNames = dependenciesStr.split("\\s+");
                for (String depName : depNames) {
                    if (!depName.trim().isEmpty()) {
                        TaskNFS depTask = taskMapNFS.getOrDefault(depName, new TaskNFS(depName));
                        taskMapNFS.put(depName, depTask);
                        dependencies.add(depTask);
                    }
                }
            }

            try {
                currentLine = reader.readLine();
                while (currentLine != null && currentLine.startsWith("\t")) {
                    String command = currentLine.substring(1);
                    if (!command.trim().isEmpty()) {
                        targetTask.addCommand(command);
                    }
                    currentLine = reader.readLine();
                }
            } catch (IOException e) {
                System.err.println("[PARSER-NFS] Error reading commands for task " + targetName);
                e.printStackTrace();
            }

            graphNFS.put(targetTask, dependencies);
        }
    }

    public void printGraphNFS() {
        System.out.println("\n[PARSER-NFS] Dependency Graph:");
        System.out.println("========================");
        for (Map.Entry<TaskNFS, List<TaskNFS>> entry : graphNFS.entrySet()) {
            TaskNFS task = entry.getKey();
            List<TaskNFS> deps = entry.getValue();
            System.out.print(task.getTaskName() + " depends on: ");
            if (deps.isEmpty()) {
                System.out.println("nothing (can start immediately)");
            } else {
                System.out.println(deps.stream()
                    .map(TaskNFS::getTaskName)
                    .reduce((a, b) -> a + ", " + b)
                    .orElse(""));
            }
            System.out.println("  Commands: " + task.getCommands().size());
        }
        System.out.println("========================\n");
    }

    public Map<String, TaskNFS> getTaskMapNFS() {
        return Collections.unmodifiableMap(taskMapNFS);
    }
}
