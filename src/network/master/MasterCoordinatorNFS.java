package network.master;

import config.Configuration;
import network.worker.WorkerInterface;

import java.rmi.Naming;

/**
 * NFS-specific coordinator for task execution on worker nodes.
 *
 * KEY DIFFERENCE from MasterCoordinator:
 * - NO file transfer (scp) - all files accessible through shared NFS mount
 * - Simpler interface - no need for masterHostname or taskName parameters
 * - Commands execute in NFS directory context
 *
 * Architecture:
 * ┌────────┐                    ┌────────┐
 * │ Master │ ─── RMI call ───> │ Worker │
 * │        │                    │        │
 * │   NFS  │ <─── shared ────> │  NFS   │
 * └────────┘      mount         └────────┘
 *
 * All results are immediately accessible via NFS - no retrieval needed!
 */
public class MasterCoordinatorNFS {

    /**
     * Executes a command on a worker node via RMI.
     *
     * In NFS mode, there is NO result file transfer because:
     * 1. Input files are already accessible via NFS
     * 2. Output files are written to NFS directory
     * 3. All nodes (master + workers) share the same NFS mount
     *
     * @param command The shell command to execute (should include 'cd /nfs_path')
     * @param workerHost The worker hostname
     * @param workerPort The worker RMI port
     * @return Exit code from the command execution
     */
    public static int executeOnWorker(String command, String workerHost, int workerPort) {
        if (command == null || command.trim().isEmpty()) {
            System.err.println("[MASTER-NFS] Invalid command");
            return -1;
        }

        if (workerHost == null || workerHost.trim().isEmpty()) {
            System.err.println("[MASTER-NFS] Invalid worker host");
            return -1;
        }

        try {
            // Connect to worker via RMI
            System.out.println("[MASTER-NFS] Connecting to worker: " + workerHost + ":" + workerPort);
            String workerUrl = Configuration.buildRmiUrl(workerHost, workerPort);
            WorkerInterface worker = (WorkerInterface) Naming.lookup(workerUrl);

            // Execute command remotely
            System.out.println("[MASTER-NFS] Executing on " + workerHost + ":" + workerPort);
            System.out.println("[MASTER-NFS]   Command: " + command);
            int exitCode = worker.executeCommand(command);

            // Report success - no file transfer needed!
            if (exitCode == 0) {
                System.out.println("[MASTER-NFS] ✅ Execution successful (results accessible via NFS)");
            } else {
                System.err.println("[MASTER-NFS] ❌ Execution failed with exit code: " + exitCode);
            }

            return exitCode;

        } catch (java.rmi.NotBoundException e) {
            System.err.println("[MASTER-NFS] ❌ Worker not found at " + workerHost + ":" + workerPort);
            System.err.println("[MASTER-NFS]    Make sure the worker is running and bound to 'WorkerService'");
            return -1;
        } catch (java.rmi.ConnectException e) {
            System.err.println("[MASTER-NFS] ❌ Cannot connect to worker " + workerHost + ":" + workerPort);
            System.err.println("[MASTER-NFS]    Check network connectivity and firewall settings");
            return -1;
        } catch (Exception e) {
            System.err.println("[MASTER-NFS] ❌ Error executing on worker " + workerHost + ": " + e.getMessage());
            e.printStackTrace();
            return -1;
        }
    }

    /**
     * Utility method to check if a hostname refers to localhost.
     * Useful for testing and debugging.
     *
     * @param hostname The hostname to check
     * @return true if the hostname is localhost
     */
    public static boolean isLocalhost(String hostname) {
        if (hostname == null) return false;
        String normalized = hostname.trim().toLowerCase();
        return normalized.equals("localhost") ||
               normalized.equals("127.0.0.1") ||
               normalized.equals("::1") ||
               normalized.equals("0.0.0.0");
    }
}
