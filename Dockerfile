FROM eclipse-temurin:17-jdk-jammy

RUN apt-get update && apt-get install -y --no-install-recommends python3 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG LEAN_TOOLCHAIN=leanprover/lean4:v4.32.2
RUN curl -sSfL https://elan.lean-lang.org/elan-init.sh \
        | sh -s -- -y --default-toolchain "${LEAN_TOOLCHAIN}" \
    && /root/.elan/bin/elan default "${LEAN_TOOLCHAIN}"
ENV PATH="/root/.elan/bin:${PATH}"
RUN lean --version && lake --version

COPY src/main/java /tmp/src
COPY src/main/resources/META-INF/MANIFEST.MF /tmp/MANIFEST.MF
COPY run_harness.py /opt/classic-harness/run_harness.py
RUN mkdir -p /opt/classic-harness/classes \
    && find /tmp/src -name '*.java' -print0 \
        | xargs -0 javac --release 17 -d /opt/classic-harness/classes \
    && jar --create \
        --file /opt/classic-harness/classic-harness.jar \
        --manifest /tmp/MANIFEST.MF \
        -C /opt/classic-harness/classes . \
    && rm -rf /tmp/src /tmp/MANIFEST.MF /opt/classic-harness/classes

WORKDIR /harness

ENTRYPOINT ["python3", "/opt/classic-harness/run_harness.py"]
