package org.crosscraft.classicworldgen;

import harness.SeedRand;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Random;

public final class ClassicHarness {
    /** The entire Java boundary: seed and size in, original block array out. */
    public static byte[] generate(
            long seed, int width, int height, int depth) throws Exception {
        SeedRand.use(seed);
        Class<?> serverClass = Class.forName(
                "com.mojang.minecraft.server.MinecraftServer");
        Class<?> generatorClass = Class.forName("com.mojang.minecraft.level.a.a");

        Object server = allocateWithoutConstructor(serverClass);
        Object generator = generatorClass.getConstructor(serverClass).newInstance(server);

        Field random = generatorClass.getDeclaredField("e");
        random.setAccessible(true);
        random.set(generator, new Random(seed));

        Object level = generatorClass
                .getMethod("a", String.class, int.class, int.class, int.class)
                // The generator takes width, horizontal depth, vertical height.
                .invoke(generator, "harness", width, depth, height);
        return (byte[]) level.getClass().getField("blocks").get(level);
    }

    // Avoid MinecraftServer's socket-opening constructor. Worldgen uses this
    // object only for static-backed logging callbacks.
    private static Object allocateWithoutConstructor(Class<?> type) throws Exception {
        Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeClass.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        return unsafeClass.getMethod("allocateInstance", Class.class)
                .invoke(singleton.get(null), type);
    }

    public static void main(String[] args) throws Exception {
        byte[] blocks = generate(
                Long.parseLong(args[0]),
                Integer.parseInt(args[1]),
                Integer.parseInt(args[2]),
                Integer.parseInt(args[3]));
        Files.write(Path.of(args[4]), blocks);
    }
}
