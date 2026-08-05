package org.crosscraft.classicworldgen;

import java.io.BufferedReader;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

/** Persistent v2 worker; the one-shot ClassicHarness CLI remains unchanged. */
public final class PersistentClassicHarness {
    private static final int MIN_DIMENSION = 16;
    private static final long MAX_VOLUME = (1L << 31) - 1;

    private PersistentClassicHarness() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !args[0].equals("--serve")) {
            System.err.println("usage: PersistentClassicHarness --serve");
            System.exit(2);
        }

        // Keep the framed binary protocol on the original stdout descriptor.
        // Original-server logging, if any, is redirected to stderr instead.
        PrintStream protocol = new PrintStream(
                new FileOutputStream(FileDescriptor.out), false, StandardCharsets.US_ASCII);
        OutputStream payload = new FileOutputStream(FileDescriptor.out);
        System.setOut(System.err);
        BufferedReader input = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.US_ASCII));

        protocol.println("READY 2");
        protocol.flush();
        for (String line; (line = input.readLine()) != null;) {
            if (line.equals("QUIT")) {
                protocol.println("BYE");
                protocol.flush();
                return;
            }
            handle(line, protocol, payload);
        }
    }

    private static void handle(String line, PrintStream protocol, OutputStream payload) {
        String[] fields = line.split(" ", -1);
        String id = fields.length > 1 ? fields[1] : "-1";
        try {
            if (fields.length != 6 || !fields[0].equals("CASE")) {
                throw new IllegalArgumentException("expected CASE id seed width height depth");
            }
            long requestId = parseNonnegativeLong(fields[1], "id");
            long seed = Long.parseLong(fields[2]);
            int width = Integer.parseInt(fields[3]);
            int height = Integer.parseInt(fields[4]);
            int depth = Integer.parseInt(fields[5]);
            validateDimensions(width, height, depth);

            // ClassicHarness.generate creates a fresh placeholder server and generator
            // for this request; only class loading and the JVM itself are reused.
            byte[] blocks = ClassicHarness.generate(seed, width, height, depth);
            protocol.println("OK " + requestId + " " + blocks.length);
            protocol.flush();
            payload.write(blocks);
            payload.flush();
        } catch (Throwable error) {
            System.err.println("persistent worker request " + id + " failed:");
            error.printStackTrace(System.err);
            protocol.println("FAIL " + id);
            protocol.flush();
        }
    }

    private static long parseNonnegativeLong(String text, String name) {
        long value = Long.parseLong(text);
        if (value < 0) {
            throw new IllegalArgumentException(name + " must be nonnegative");
        }
        return value;
    }

    private static void validateDimensions(int width, int height, int depth) {
        validateDimension(width, "width");
        validateDimension(height, "height");
        validateDimension(depth, "depth");
        long horizontalArea = (long) width * height;
        if (horizontalArea > MAX_VOLUME / depth) {
            throw new IllegalArgumentException("level volume exceeds Java maximum array length");
        }
    }

    private static void validateDimension(int value, String name) {
        if (value < MIN_DIMENSION || (value & (value - 1)) != 0) {
            throw new IllegalArgumentException(
                    name + " must be a power of two and at least " + MIN_DIMENSION);
        }
    }
}
