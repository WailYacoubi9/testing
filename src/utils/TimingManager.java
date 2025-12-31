package utils;

import java.util.LinkedHashMap; // <--- Changement ici
import java.util.Map;

/**
 * Utility class for timing execution phases in the distributed word count system.
 * Follows the same pattern as Configuration.java - static utility class.
 */
public class TimingManager {
    private static long startTime;
    // Changement ici : LinkedHashMap garantit l'ordre d'insertion (chronologique)
    private static final Map<String, Long> timestamps = new LinkedHashMap<>();
    
    private TimingManager() {
        // Prevent instantiation like Configuration.java
        throw new UnsupportedOperationException("TimingManager is a utility class");
    }
    
    public static void startTiming() {
        timestamps.clear(); // Important : on nettoie les anciennes valeurs
        startTime = System.nanoTime();
        timestamp("START");
    }
    
    public static void timestamp(String phase) {
        timestamps.put(phase, System.nanoTime());
    }
    
    public static void printReport() {
        System.out.println("\n╔════════════════════════════════════════╗");
        System.out.println("║           TIMING REPORT                ║");
        System.out.println("╠════════════════════════════════════════╣");
        
        // Grâce au LinkedHashMap, cette boucle se fera dans l'ordre chronologique
        for (Map.Entry<String, Long> entry : timestamps.entrySet()) {
            long durationMs = (entry.getValue() - startTime) / 1_000_000;
            // J'ai ajouté un peu de formatage pour que ce soit aligné joliement
            System.out.println(String.format("║ %-30s : %4dms ║", entry.getKey(), durationMs));
        }
        System.out.println("╚════════════════════════════════════════╝\n");
    }
    
    public static long getPhaseDuration(String phase) {
        Long phaseTime = timestamps.get(phase);
        if (phaseTime == null) return -1;
        return (phaseTime - startTime) / 1_000_000;
    }
}