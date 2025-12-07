package network.worker;

import java.rmi.RemoteException;
import java.rmi.server.UnicastRemoteObject;

public class WorkerImpl extends UnicastRemoteObject implements WorkerInterface {

    protected WorkerImpl() throws RemoteException {
        super();
    }

    @Override
    public int executeCommand(String command) throws RemoteException {
        System.out.println("[WORKER] Received command: " + command);

        try {
            Process process = Runtime.getRuntime().exec(
                new String[] { "/bin/bash", "-c", command }
            );

            int exitCode = process.waitFor();

            System.out.println("[WORKER] Command finished with exit code: " + exitCode);
            return exitCode;

        } catch (Exception e) {
            System.err.println("[WORKER] Error executing command: " + e.getMessage());
            throw new RemoteException("Error executing command", e);
        }
    }
}
