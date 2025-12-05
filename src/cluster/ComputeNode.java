package cluster;

import config.Configuration;

/**
 * Represents a compute node in the cluster.
 * Refactored with proper encapsulation and thread-safe status management.
 */
public class ComputeNode {
    public final String hostname;
    public final int port;
    private volatile NodeStatus status;

    /**
     * Creates a compute node with the default RMI port.
     * @param hostname The hostname of the node
     */
    public ComputeNode(String hostname) {
        this(hostname, Configuration.RMI_REGISTRY_PORT);
    }

    /**
     * Creates a compute node with a specific RMI port.
     * @param hostname The hostname of the node
     * @param port The RMI registry port
     */
    public ComputeNode(String hostname, int port) {
        if (hostname == null || hostname.trim().isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        if (port < 1024 || port > 65535) {
            throw new IllegalArgumentException("Port must be between 1024 and 65535");
        }
        this.hostname = hostname;
        this.port = port;
        this.status = NodeStatus.FREE;
    }

    /**
     * Gets the current status of this node.
     * Thread-safe using volatile.
     * @return The current node status
     */
    public NodeStatus getStatus() {
        return status;
    }

    /**
     * Sets the status of this node.
     * Thread-safe using volatile.
     * @param status The new status
     */
    public void setStatus(NodeStatus status) {
        if (status == null) {
            throw new IllegalArgumentException("Status cannot be null");
        }
        this.status = status;
    }

    @Override
    public String toString() {
        return "ComputeNode{" + hostname + ":" + port + ", " + status + "}";
    }
}
