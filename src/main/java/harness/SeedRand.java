package harness;

import java.util.Random;

/** Deterministic stand-in for Level's constructor-created Random. */
public final class SeedRand extends Random {
    private static final ThreadLocal<Long> CONSTRUCTION_SEED =
            ThreadLocal.withInitial(() -> 0L);

    public static void use(long seed) {
        CONSTRUCTION_SEED.set(seed);
    }

    public SeedRand() {
        super(CONSTRUCTION_SEED.get());
    }
}
