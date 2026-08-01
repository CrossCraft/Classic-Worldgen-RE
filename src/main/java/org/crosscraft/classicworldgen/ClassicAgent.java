package org.crosscraft.classicworldgen;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.security.ProtectionDomain;
import java.util.Arrays;
import java.util.HexFormat;

/** Narrow class-load transformer for the supported server 1.10 JAR. */
public final class ClassicAgent {
    private static final byte[] RANDOM = ascii("java/util/Random");
    private static final byte[] SEEDED_RANDOM = ascii("harness/SeedRand");

    private static final byte[] FIXED_DIMENSION_SETUP = hex(
            "2a110100b50041" + "2a110100b50042" + "2a1040b50043"
                    + "2a1020b50046" + "2a110100100878100678bc08b50045");
    private static final byte[] PARAMETER_DIMENSION_SETUP = hex(
            "2a1c0000b50041" + "2a1d0000b50042" + "2a1504b50043"
                    + "2a1504056cb50046" + "2a1c1d68150468bc08b5004500");

    // The field-based handoff needs four extra bytes. It reuses createTime,
    // which is outside the byte[] result, and leaves NOPs to preserve offsets.
    private static final byte[] FIXED_LEVEL_HANDOFF = hex(
            "2d11010010401101002ab40045b6005e" + "2db8006ab5003c");
    private static final byte[] PARAMETER_LEVEL_HANDOFF = hex(
            "2d2ab400412ab400432ab400422ab40045b6005e000000");

    public static void premain(String ignored, Instrumentation instrumentation) {
        instrumentation.addTransformer(new Transformer());
    }

    private static final class Transformer implements ClassFileTransformer {
        @Override
        public byte[] transform(
                ClassLoader loader,
                String className,
                Class<?> redefinedClass,
                ProtectionDomain domain,
                byte[] classFile) throws IllegalClassFormatException {
            try {
                return switch (className) {
                    case "com/mojang/minecraft/level/Level" ->
                            replace(classFile, RANDOM, SEEDED_RANDOM, 3);
                    case "com/mojang/minecraft/level/a/a" -> replace(
                            replace(
                                    classFile,
                                    FIXED_DIMENSION_SETUP,
                                    PARAMETER_DIMENSION_SETUP,
                                    1),
                            FIXED_LEVEL_HANDOFF,
                            PARAMETER_LEVEL_HANDOFF,
                            1);
                    default -> null;
                };
            } catch (IllegalArgumentException error) {
                throw new IllegalClassFormatException(error.getMessage());
            }
        }
    }

    private static byte[] replace(
            byte[] input, byte[] target, byte[] replacement, int expected) {
        if (target.length != replacement.length) {
            throw new AssertionError("class patch must preserve byte length");
        }

        byte[] output = input.clone();
        int count = 0;
        for (int offset = 0; offset <= output.length - target.length; offset++) {
            if (matches(output, target, offset)) {
                System.arraycopy(replacement, 0, output, offset, replacement.length);
                count++;
                offset += target.length - 1;
            }
        }
        if (count != expected) {
            throw new IllegalArgumentException(
                    "unsupported classic.jar: expected " + expected
                            + " patch site(s), found " + count);
        }
        return output;
    }

    private static boolean matches(byte[] input, byte[] target, int offset) {
        return Arrays.equals(input, offset, offset + target.length, target, 0, target.length);
    }

    private static byte[] ascii(String value) {
        return value.getBytes(StandardCharsets.US_ASCII);
    }

    private static byte[] hex(String value) {
        return HexFormat.of().parseHex(value);
    }
}
