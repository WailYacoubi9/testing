package utils;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public class TimingManager {
    private static long startTime;
    // On utilise synchronizedMap pour eviter des bugs si plusieurs threads ecrivent
    private static final Map<String, Long> timestamps = Collections.synchronizedMap(new LinkedHashMap<>());

    private TimingManager() {
        throw new UnsupportedOperationException("TimingManager is a utility class");
    }

    public static void startTiming() {
        timestamps.clear();
        startTime = System.nanoTime();
        timestamp("START");
    }

    public static void timestamp(String phase) {
        timestamps.put(phase, System.nanoTime());
    }

    // === C'EST LA METHODE QUI TE MANQUAIT ===
    public static Long getTime(String phase) {
        Long time = timestamps.get(phase);
        if (time == null) {
            return null;
        }
        // On retourne des millisecondes pour que MainNFS puisse faire ses calculs simplement
        return time / 1_000_000;
    }
    // ========================================

    public static void printReport() {
        System.out.println("\n------------------------------------------");
        System.out.println("           TIMING REPORT                ");
        System.out.println("------------------------------------------");

        synchronized (timestamps) {
            for (Map.Entry<String, Long> entry : timestamps.entrySet()) {
                // Calcul de la duree depuis le debut (startTime)
                long durationMs = (entry.getValue() - startTime) / 1_000_000;
                System.out.println(String.format(" %-30s : %4dms ", entry.getKey(), durationMs));
            }
        }
        System.out.println("------------------------------------------\n");
    }

    public static long getPhaseDuration(String phase) {
        Long phaseTime = timestamps.get(phase);
        if (phaseTime == null) return -1;
        return (phaseTime - startTime) / 1_000_000;
    }
}
