package benchmark;

import network.worker.WorkerInterface;
import config.Configuration;
import java.rmi.Naming;
import java.util.ArrayList;
import java.util.List;

/**
 * Benchmark du temps de lancement reel du cluster.
 *
 * Mesure le temps TOTAL pour:
 * 1. Connexion RMI a chaque worker (Naming.lookup)
 * 2. Verification que le worker repond (executeCommand)
 *
 * Usage: java benchmark.LauncherBenchmark worker1:3000 worker2:3000 ...
 *
 * Ce benchmark suppose que les workers sont DEJA demarres.
 * Il mesure uniquement le temps de connexion RMI depuis le master.
 */
public class LauncherBenchmark {

    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java benchmark.LauncherBenchmark worker1:port worker2:port ...");
            System.err.println("Example: java benchmark.LauncherBenchmark node1:3000 node2:3000 node3:3000");
            System.exit(1);
        }

        List<String> workers = new ArrayList<>();
        for (String arg : args) {
            workers.add(arg);
        }

        int numWorkers = workers.size();

        // Mesure: Connexion RMI a tous les workers
        long startTime = System.nanoTime();

        int successCount = 0;
        List<Long> lookupTimes = new ArrayList<>();
        List<Long> execTimes = new ArrayList<>();

        for (String workerSpec : workers) {
            String[] parts = workerSpec.split(":");
            String host = parts[0];
            int port = parts.length > 1 ? Integer.parseInt(parts[1]) : 3000;

            String url = Configuration.buildRmiUrl(host, port);

            try {
                // 1. Mesurer Naming.lookup (connexion RMI)
                long lookupStart = System.nanoTime();
                WorkerInterface worker = (WorkerInterface) Naming.lookup(url);
                long lookupEnd = System.nanoTime();
                lookupTimes.add(lookupEnd - lookupStart);

                // 2. Mesurer executeCommand (verification connexion)
                long execStart = System.nanoTime();
                int exitCode = worker.executeCommand("true");
                long execEnd = System.nanoTime();
                execTimes.add(execEnd - execStart);

                if (exitCode == 0) {
                    successCount++;
                }

            } catch (Exception e) {
                System.err.println("ERREUR connexion " + url + ": " + e.getMessage());
                lookupTimes.add(-1L);
                execTimes.add(-1L);
            }
        }

        long endTime = System.nanoTime();
        double totalTimeMs = (endTime - startTime) / 1_000_000.0;

        // Calculer les moyennes
        double avgLookupMs = lookupTimes.stream()
            .filter(t -> t > 0)
            .mapToLong(Long::longValue)
            .average()
            .orElse(0) / 1_000_000.0;

        double avgExecMs = execTimes.stream()
            .filter(t -> t > 0)
            .mapToLong(Long::longValue)
            .average()
            .orElse(0) / 1_000_000.0;

        // Sortie CSV-friendly pour le script shell
        // Format: num_workers,success_count,total_time_ms,avg_lookup_ms,avg_exec_ms
        System.out.println("RESULT:" + numWorkers + "," + successCount + "," +
                          String.format("%.3f", totalTimeMs) + "," +
                          String.format("%.3f", avgLookupMs) + "," +
                          String.format("%.3f", avgExecMs));

        // Affichage detaille
        System.err.println("--- Resultats ---");
        System.err.println("Workers: " + numWorkers + " (succes: " + successCount + ")");
        System.err.println("Temps total RMI: " + String.format("%.3f", totalTimeMs) + " ms");
        System.err.println("Moyenne lookup: " + String.format("%.3f", avgLookupMs) + " ms");
        System.err.println("Moyenne exec: " + String.format("%.3f", avgExecMs) + " ms");

        // Code de sortie
        if (successCount == numWorkers) {
            System.exit(0);
        } else {
            System.exit(1);
        }
    }
}
