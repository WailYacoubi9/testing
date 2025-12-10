package utils;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/**
 * Utility class to split large files equitably among workers.
 * Ensures fair load distribution based on line count.
 */
public class FileSplitter {

    /**
     * Splits a file into N parts with equitable line distribution.
     * @param inputFile Path to the input file
     * @param numWorkers Number of workers (parts to create)
     * @param outputPrefix Prefix for output files (e.g., "part")
     * @return List of generated file paths
     * @throws IOException if file operations fail
     */
    public static List<String> splitFileEquitably(String inputFile, int numWorkers, String outputPrefix)
            throws IOException {

        if (inputFile == null || inputFile.trim().isEmpty()) {
            throw new IllegalArgumentException("Input file cannot be null or empty");
        }

        if (numWorkers < 1) {
            throw new IllegalArgumentException("Number of workers must be at least 1");
        }

        // Count total lines
        long totalLines = Files.lines(Paths.get(inputFile)).count();
        System.out.println("[SPLITTER] Total lines in input: " + totalLines);

        // Calculate lines per worker (with remainder distribution)
        long linesPerWorker = totalLines / numWorkers;
        long remainder = totalLines % numWorkers;

        System.out.println("[SPLITTER] Base lines per worker: " + linesPerWorker);
        System.out.println("[SPLITTER] Workers with extra line: " + remainder);

        List<String> outputFiles = new ArrayList<>();

        try (BufferedReader reader = new BufferedReader(new FileReader(inputFile))) {
            for (int workerId = 0; workerId < numWorkers; workerId++) {
                // First 'remainder' workers get one extra line
                long linesToWrite = linesPerWorker + (workerId < remainder ? 1 : 0);

                String outputFile = outputPrefix + (workerId + 1) + ".txt";
                outputFiles.add(outputFile);

                try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputFile))) {
                    long linesWritten = 0;
                    String line;

                    while (linesWritten < linesToWrite && (line = reader.readLine()) != null) {
                        writer.write(line);
                        writer.newLine();
                        linesWritten++;
                    }

                    System.out.println("[SPLITTER] Created " + outputFile + " with " + linesWritten + " lines");
                }
            }
        }

        return outputFiles;
    }

    /**
     * Splits a file by approximate size (in bytes) rather than lines.
     * Useful for files with very uneven line lengths.
     * @param inputFile Path to the input file
     * @param numWorkers Number of workers
     * @param outputPrefix Prefix for output files
     * @return List of generated file paths
     * @throws IOException if file operations fail
     */
    public static List<String> splitFileBySize(String inputFile, int numWorkers, String outputPrefix)
            throws IOException {

        File file = new File(inputFile);
        long fileSize = file.length();
        long bytesPerWorker = fileSize / numWorkers;

        System.out.println("[SPLITTER] Total file size: " + fileSize + " bytes");
        System.out.println("[SPLITTER] Target bytes per worker: " + bytesPerWorker);

        List<String> outputFiles = new ArrayList<>();

        try (BufferedReader reader = new BufferedReader(new FileReader(inputFile))) {
            for (int workerId = 0; workerId < numWorkers; workerId++) {
                String outputFile = outputPrefix + (workerId + 1) + ".txt";
                outputFiles.add(outputFile);

                long bytesWritten = 0;
                long targetBytes = bytesPerWorker * (workerId + 1);

                try (BufferedWriter writer = new BufferedWriter(new FileWriter(outputFile))) {
                    String line;

                    while ((line = reader.readLine()) != null) {
                        writer.write(line);
                        writer.newLine();
                        bytesWritten += line.length() + 1; // +1 for newline

                        // Move to next file after reaching target (except last worker gets remainder)
                        if (workerId < numWorkers - 1 && bytesWritten >= bytesPerWorker) {
                            break;
                        }
                    }

                    System.out.println("[SPLITTER] Created " + outputFile + " with ~" + bytesWritten + " bytes");
                }
            }
        }

        return outputFiles;
    }

    /**
     * Cleans up generated split files.
     * @param files List of file paths to delete
     */
    public static void cleanupFiles(List<String> files) {
        if (files == null) return;

        for (String file : files) {
            try {
                Files.deleteIfExists(Paths.get(file));
                System.out.println("[SPLITTER] Deleted: " + file);
            } catch (IOException e) {
                System.err.println("[SPLITTER] Failed to delete " + file + ": " + e.getMessage());
            }
        }
    }

    /**
     * Main method for command-line usage.
     * Usage: java utils.FileSplitter <inputFile> <numWorkers> <outputPrefix>
     */
    public static void main(String[] args) {
        if (args.length < 3) {
            System.err.println("Usage: java utils.FileSplitter <inputFile> <numWorkers> <outputPrefix>");
            System.err.println("Example: java utils.FileSplitter data.txt 4 part");
            System.exit(1);
        }

        String inputFile = args[0];
        int numWorkers = Integer.parseInt(args[1]);
        String outputPrefix = args[2];

        try {
            List<String> splitFiles = splitFileEquitably(inputFile, numWorkers, outputPrefix);
            System.out.println("[SPLITTER] ✅ Successfully created " + splitFiles.size() + " files");
        } catch (IOException e) {
            System.err.println("[SPLITTER] ❌ Error: " + e.getMessage());
            System.exit(1);
        }
    }
}
