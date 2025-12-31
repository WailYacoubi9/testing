package network.worker;

import java.rmi.Remote;
import java.rmi.RemoteException;

public interface WorkerInterface extends Remote {
    int executeCommand(String command) throws RemoteException;
}
