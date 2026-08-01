# Use 11-jdk-jammy instead if you hit compatibility issues
FROM eclipse-temurin:17-jdk-jammy

# Basic utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    gzip \
    unzip \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Optional but useful for seed injection / light patching
# (ASM, ByteBuddy, etc. can be downloaded at build time or mounted)
WORKDIR /harness

# The classic.jar / server.jar is *not* baked in.
# Mount it at runtime.
