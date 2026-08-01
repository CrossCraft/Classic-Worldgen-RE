set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

root := justfile_directory()
image := env_var_or_default("CLASSIC_HARNESS_IMAGE", "classic-worldgen-re")
classic_jar := env_var_or_default("CLASSIC_JAR", root + "/classic.jar")
output_dir := env_var_or_default("CLASSIC_OUT_DIR", root + "/out")

# List the available harness commands.
default:
    @just --list

# Build the Docker harness image.
build:
    docker build -t "{{ image }}" "{{ root }}"

# Generate a seed at an optional power-of-two width, height, and depth.
run seed width="256" height="64" depth="256": _check-jar
    harness_jar_path="$(realpath "{{ classic_jar }}")"; \
    docker run --rm \
      --mount "type=bind,source=$harness_jar_path,target=/harness/classic.jar,readonly" \
      "{{ image }}" --seed "{{ seed }}" \
      --width "{{ width }}" --height "{{ height }}" --depth "{{ depth }}"

# Check repeatability and an adjacent-seed control.
verify seed width="256" height="64" depth="256": _check-jar
    harness_jar_path="$(realpath "{{ classic_jar }}")"; \
    docker run --rm \
      --mount "type=bind,source=$harness_jar_path,target=/harness/classic.jar,readonly" \
      "{{ image }}" --seed "{{ seed }}" \
      --width "{{ width }}" --height "{{ height }}" --depth "{{ depth }}" \
      --verify

# Report block IDs and verify plausible terrain-material quantities.
composition seed="12345" width="256" height="64" depth="256": _check-jar
    harness_jar_path="$(realpath "{{ classic_jar }}")"; \
    docker run --rm \
      --mount "type=bind,source=$harness_jar_path,target=/harness/classic.jar,readonly" \
      "{{ image }}" --seed "{{ seed }}" \
      --width "{{ width }}" --height "{{ height }}" --depth "{{ depth }}" \
      --composition --check-composition

# Generate a level and retain its raw block array under CLASSIC_OUT_DIR.
extract seed filename="level.blocks" width="256" height="64" depth="256": _check-jar
    mkdir -p "{{ output_dir }}"
    harness_jar_path="$(realpath "{{ classic_jar }}")"; \
    harness_output_path="$(realpath "{{ output_dir }}")"; \
    docker run --rm \
      --mount "type=bind,source=$harness_jar_path,target=/harness/classic.jar,readonly" \
      --mount "type=bind,source=$harness_output_path,target=/out" \
      "{{ image }}" --seed "{{ seed }}" \
      --width "{{ width }}" --height "{{ height }}" --depth "{{ depth }}" \
      --blocks-out "/out/{{ filename }}"

# Build and run an end-to-end smoke test (seed 12345 by default).
smoke seed="12345": build
    just verify "{{ seed }}"

# Run the Python unit tests inside the harness image.
test: build
    docker run --rm --entrypoint python3 \
      --mount "type=bind,source={{ root }},target=/work,readonly" \
      --workdir /work \
      "{{ image }}" -m unittest discover -s tests -v

_check-jar:
    @test -f "{{ classic_jar }}" || { \
      echo "classic JAR not found: {{ classic_jar }}" >&2; \
      echo "Set CLASSIC_JAR=/absolute/path/to/classic.jar if needed." >&2; \
      exit 1; \
    }
