package network.master;

import config.Configuration;
import network.worker.WorkerInterface;

import java.rmi.Naming;

/**
 * Coordinates task execution on worker nodes via RMI.
 * Refactored to remove circular dependencies.
 */
public class MasterCoordinator {

    /**
     * Executes a command on a worker node.
     * Simplified version - assumes all input files are pre-deployed to workers.
     * @param command The command to execute
     * @param workerHost The worker hostname
     * @param workerPort The worker RMI port
     * @param masterHostname The master hostname
     * @param taskName The name of the task (used for result retrieval)
     * @return Exit code from the command
     */
    public static int executeOnWorker(String command, String workerHost, int workerPort, String masterHostname, String taskName) {
        if (command == null || command.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid command");
            return -1;
        }

        if (workerHost == null || workerHost.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid worker host");
            return -1;
        }

        try {
            System.out.println("[MASTER] Connecting to worker: " + workerHost + ":" + workerPort);
            String workerUrl = Configuration.buildRmiUrl(workerHost, workerPort);
            WorkerInterface worker = (WorkerInterface) Naming.lookup(workerUrl);

            System.out.println("[MASTER] Executing on " + workerHost + ":" + workerPort + ": " + command);
            int exitCode = worker.executeCommand(command);

            if (exitCode == 0 && taskName != null) {
                retrieveResults(taskName, workerHost, masterHostname);
            }

            return exitCode;

        } catch (Exception e) {
            System.err.println("[MASTER] Error executing on worker " + workerHost + ": " + e.getMessage());
            e.printStackTrace();
            return -1;
        }
    }

    /**
     * Retrieves result files from the worker back to master.
     */
    private static void retrieveResults(String taskName, String workerHost, String masterHost) {
        try {
            if (taskName != null && taskName.contains(".")) {
                System.out.println("[MASTER] Retrieving result: " + taskName);
                transferFile(workerHost, masterHost, taskName);
            }
        } catch (Exception e) {
            System.err.println("[MASTER] Error retrieving results: " + e.getMessage());
        }
    }

    /**
     * Transfers a file between hosts using scp.
     * Skips transfer if source and destination are both localhost.
     */
    private static void transferFile(String sourceHost, String destHost, String filename) {
        if (filename == null || filename.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid filename for transfer");
            return;
        }

        // Skip transfer if both hosts are localhost (file is already accessible)
        boolean sourceIsLocal = isLocalhost(sourceHost);
        boolean destIsLocal = isLocalhost(destHost);

        if (sourceIsLocal && destIsLocal) {
            System.out.println("[MASTER] ✅ File available locally: " + filename);
            return;
        }

        try {
            // Copy from worker's home directory to master's current directory
            // Use array form to properly handle arguments
            String[] command = {
                "scp",
                sourceHost + ":~/" + filename,
                "."
            };
            Process process = Runtime.getRuntime().exec(command);
            int exitCode = process.waitFor();

            if (exitCode == 0) {
                System.out.println("[MASTER] ✅ File transferred: " + filename);
            } else {
                // Print stderr to diagnose issues
                java.io.BufferedReader errorReader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(process.getErrorStream()));
                String line;
                System.err.println("[MASTER] ❌ File transfer failed: " + filename);
                while ((line = errorReader.readLine()) != null) {
                    System.err.println("[SCP ERROR] " + line);
                }
            }
        } catch (Exception e) {
            System.err.println("[MASTER] Error transferring file " + filename + ": " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Checks if a hostname refers to localhost.
     */
    private static boolean isLocalhost(String hostname) {
        if (hostname == null) return false;
        String normalized = hostname.trim().toLowerCase();
        return normalized.equals("localhost") ||
               normalized.equals("127.0.0.1") ||
               normalized.equals("::1") ||
               normalized.equals("0.0.0.0");
    }
}
