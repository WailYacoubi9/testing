package config;

/**
 * Central configuration for the distributed word count system.
 * Eliminates magic numbers and provides a single source of truth for settings.
 */
public class Configuration {
    // RMI Configuration
    public static final int RMI_REGISTRY_PORT = 3000;
    public static final String RMI_SERVICE_NAME = "WorkerService";

    // Scheduler Configuration
    public static final int SCHEDULER_POLL_INTERVAL_MS = 500;
    public static final int SCHEDULER_TIMEOUT_HOURS = 1;

    // Task Configuration
    public static final int TASK_RETRY_BASE_WAIT_MS = 100;
    public static final int TASK_RETRY_RANDOM_RANGE_MS = 100;

    // Validation
    // Note: These are TOTAL nodes (master + workers)
    // Minimum 2 = 1 master + 1 worker
    public static final int MIN_WORKER_NODES = 2;
    public static final int MAX_WORKER_NODES = 1000;

    private Configuration() {
        // Prevent instantiation
        throw new UnsupportedOperationException("Configuration is a utility class");
    }

    /**
     * Builds the RMI URL for a given hostname using the default port.
     * @param hostname The hostname of the worker
     * @return The complete RMI URL
     */
    public static String buildRmiUrl(String hostname) {
        return buildRmiUrl(hostname, RMI_REGISTRY_PORT);
    }

    /**
     * Builds the RMI URL for a given hostname and port.
     * @param hostname The hostname of the worker
     * @param port The RMI registry port
     * @return The complete RMI URL
     */
    public static String buildRmiUrl(String hostname, int port) {
        if (hostname == null || hostname.trim().isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        if (port < 1024 || port > 65535) {
            throw new IllegalArgumentException("Port must be between 1024 and 65535");
        }
        return String.format("rmi://%s:%d/%s", hostname, port, RMI_SERVICE_NAME);
    }
}
