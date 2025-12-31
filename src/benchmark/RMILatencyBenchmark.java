package benchmark;

import network.worker.WorkerInterface;
import config.Configuration;
import java.rmi.Naming;
import java.io.PrintWriter;
import java.io.FileWriter;
import java.util.Arrays;

/**
 * Benchmark de latence RMI selon le modele LogP.
 *
 * Mesure:
 * - L (Latency): temps de Naming.lookup()
 * - o (overhead): temps d'un appel executeCommand()
 *
 * Reference: Culler et al. (1993) "LogP: A Practical Model of Parallel Computation"
 *
 * Usage: java benchmark.RMILatencyBenchmark worker_host:port output.csv
 */
public class RMILatencyBenchmark {

    private static final int WARMUP_ITERATIONS = 10;
    private static final int MEASURE_ITERATIONS = 100;

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: java benchmark.RMILatencyBenchmark <worker_host:port> <output_csv>");
            System.exit(1);
        }

        String workerSpec = args[0];
        String outputFile = args[1];

        String[] parts = workerSpec.split(":");
        String host = parts[0];
        int port = parts.length > 1 ? Integer.parseInt(parts[1]) : 3000;

        String url = Configuration.buildRmiUrl(host, port);

        System.out.println("=".repeat(60));
        System.out.println("BENCHMARK LATENCE RMI - Modele LogP");
        System.out.println("=".repeat(60));
        System.out.println("Worker: " + url);
        System.out.println("Warmup: " + WARMUP_ITERATIONS + " iterations");
        System.out.println("Mesures: " + MEASURE_ITERATIONS + " iterations");

        // PHASE 1: WARMUP
        System.out.println("\n[PHASE 1] Warmup...");
        for (int i = 0; i < WARMUP_ITERATIONS; i++) {
            WorkerInterface worker = (WorkerInterface) Naming.lookup(url);
            worker.executeCommand("echo warmup");
        }
        System.out.println("Warmup termine.");

        // PHASE 2: MESURES
        System.out.println("\n[PHASE 2] Mesures...");

        long[] lookupTimes = new long[MEASURE_ITERATIONS];
        long[] execTimes = new long[MEASURE_ITERATIONS];

        for (int i = 0; i < MEASURE_ITERATIONS; i++) {
            // Mesure L_rmi (Naming.lookup)
            long startLookup = System.nanoTime();
            WorkerInterface worker = (WorkerInterface) Naming.lookup(url);
            long endLookup = System.nanoTime();
            lookupTimes[i] = endLookup - startLookup;

            // Mesure o_rmi (appel distant minimal)
            long startExec = System.nanoTime();
            worker.executeCommand("true");
            long endExec = System.nanoTime();
            execTimes[i] = endExec - startExec;

            if ((i + 1) % 20 == 0) {
                System.out.println("  Progression: " + (i + 1) + "/" + MEASURE_ITERATIONS);
            }
        }

        // PHASE 3: STATISTIQUES
        double[] lookupMs = toMilliseconds(lookupTimes);
        double[] execMs = toMilliseconds(execTimes);

        Statistics lookupStats = calculateStatistics(lookupMs);
        Statistics execStats = calculateStatistics(execMs);

        // PHASE 4: AFFICHAGE
        System.out.println("\n" + "=".repeat(60));
        System.out.println("RESULTATS - PARAMETRES LogP");
        System.out.println("=".repeat(60));

        System.out.println("\nL_rmi (Naming.lookup):");
        System.out.println("  Moyenne:     " + String.format("%.3f", lookupStats.mean) + " ms");
        System.out.println("  Ecart-type:  " + String.format("%.3f", lookupStats.stdDev) + " ms");
        System.out.println("  IC 95%:      [" + String.format("%.3f", lookupStats.ci95Low) +
                          ", " + String.format("%.3f", lookupStats.ci95High) + "] ms");

        System.out.println("\no_rmi (executeCommand overhead):");
        System.out.println("  Moyenne:     " + String.format("%.3f", execStats.mean) + " ms");
        System.out.println("  Ecart-type:  " + String.format("%.3f", execStats.stdDev) + " ms");

        System.out.println("\nTotal (L_rmi + o_rmi):");
        System.out.println("  Moyenne:     " + String.format("%.3f", lookupStats.mean + execStats.mean) + " ms");

        // PHASE 5: EXPORT CSV
        exportCSV(outputFile, host, port, lookupMs, execMs, lookupStats, execStats);
        System.out.println("\nResultats exportes: " + outputFile);

        System.out.println("\n" + "=".repeat(60));
        System.out.println("VALEURS POUR LE MODELE:");
        System.out.println("  L_rmi = " + String.format("%.3f", lookupStats.mean) + " ms");
        System.out.println("  o_rmi = " + String.format("%.3f", execStats.mean) + " ms");
        System.out.println("=".repeat(60));
    }

    private static double[] toMilliseconds(long[] nanos) {
        double[] ms = new double[nanos.length];
        for (int i = 0; i < nanos.length; i++) {
            ms[i] = nanos[i] / 1_000_000.0;
        }
        return ms;
    }

    private static Statistics calculateStatistics(double[] values) {
        Statistics stats = new Statistics();

        double sum = 0;
        for (double v : values) sum += v;
        stats.mean = sum / values.length;

        double sumSquares = 0;
        for (double v : values) {
            sumSquares += Math.pow(v - stats.mean, 2);
        }
        stats.stdDev = Math.sqrt(sumSquares / (values.length - 1));

        double marginOfError = 1.96 * (stats.stdDev / Math.sqrt(values.length));
        stats.ci95Low = stats.mean - marginOfError;
        stats.ci95High = stats.mean + marginOfError;

        stats.min = Arrays.stream(values).min().orElse(0);
        stats.max = Arrays.stream(values).max().orElse(0);

        return stats;
    }

    private static void exportCSV(String filename, String host, int port,
                                   double[] lookupMs, double[] execMs,
                                   Statistics lookupStats, Statistics execStats) throws Exception {
        PrintWriter writer = new PrintWriter(new FileWriter(filename));

        writer.println("# RMI Latency Benchmark Results");
        writer.println("# Worker: " + host + ":" + port);
        writer.println("# Date: " + java.time.LocalDateTime.now());
        writer.println("# Iterations: " + lookupMs.length);
        writer.println("#");
        writer.println("# L_rmi_mean_ms," + String.format("%.6f", lookupStats.mean));
        writer.println("# L_rmi_std_ms," + String.format("%.6f", lookupStats.stdDev));
        writer.println("# o_rmi_mean_ms," + String.format("%.6f", execStats.mean));
        writer.println("# o_rmi_std_ms," + String.format("%.6f", execStats.stdDev));
        writer.println("#");
        writer.println("iteration,lookup_ms,exec_ms,total_ms");

        for (int i = 0; i < lookupMs.length; i++) {
            writer.println(i + "," +
                          String.format("%.6f", lookupMs[i]) + "," +
                          String.format("%.6f", execMs[i]) + "," +
                          String.format("%.6f", lookupMs[i] + execMs[i]));
        }

        writer.close();
    }

    static class Statistics {
        double mean, stdDev, ci95Low, ci95High, min, max;
    }
}
