package network.worker;

import config.Configuration;
import java.rmi.Naming;
import java.rmi.registry.LocateRegistry;

/**
 * Worker node that registers with RMI and waits for tasks.
 * Uses proper thread blocking instead of Long.MAX_VALUE sleep.
 */
public class WorkerNode {
    private static volatile boolean running = true;
    private static final Object lock = new Object();

    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java network.worker.WorkerNode <hostname> [port]");
            System.err.println("  hostname: Worker hostname (e.g., localhost)");
            System.err.println("  port: Optional RMI port (default: " + Configuration.RMI_REGISTRY_PORT + ")");
            System.exit(1);
        }

        String hostname = args[0];
        if (hostname == null || hostname.trim().isEmpty()) {
            System.err.println("[WORKER] ❌ Hostname cannot be empty");
            System.exit(1);
        }

        int 
        port = Configuration.RMI_REGISTRY_PORT;
        if (args.length >= 2) {
            try {
                port = Integer.parseInt(args[1]);
                if (port < 1024 || port > 65535) {
                    System.err.println("[WORKER] ❌ Port must be between 1024 and 65535");
                    System.exit(1);
                }
            } catch (NumberFormatException e) {
                System.err.println("[WORKER] ❌ Invalid port number: " + args[1]);
                System.exit(1);
            }
        }

        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   WORKER NODE STARTING                                   ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝");
        System.out.println("[WORKER] Node: " + hostname);
        System.out.println("[WORKER] Port: " + port);

        // Add shutdown hook for graceful termination
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("\n[WORKER] Shutting down gracefully...");
            running = false;
            synchronized (lock) {
                lock.notifyAll();
            }
        }));

        try {
            System.out.println("[WORKER] Creating RMI registry on port " + port + "...");
            LocateRegistry.createRegistry(port);

            System.out.println("[WORKER] Creating worker implementation...");
            WorkerImpl worker = new WorkerImpl();

            String url = Configuration.buildRmiUrl(hostname, port);
            Naming.rebind(url, worker);

            System.out.println("[WORKER] ✅ Worker ready and waiting for tasks!");
            System.out.println("[WORKER] RMI URL: " + url);
            System.out.println("[WORKER] Press Ctrl+C to stop");

            // Proper blocking mechanism
            synchronized (lock) {
                while (running) {
                    lock.wait();
                }
            }

            System.out.println("[WORKER] Worker stopped.");

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("[WORKER] Worker interrupted");
        } catch (Exception e) {
            System.err.println("[WORKER] ❌ Failed to start: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
