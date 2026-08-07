#!/usr/bin/env bash
# Run a preflight and then a 12-hour persistent v2 differential campaign.
set -Eeuo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
run_root=${RUN_ROOT:-"$repo_root/burnin"}
campaign_name=${CAMPAIGN_NAME:-"fuzz-v2-12h-$(date -u +%Y%m%dT%H%M%SZ)"}
campaign_dir=${CAMPAIGN_DIR:-"$run_root/campaigns/$campaign_name"}
if [[ -v SCRATCH_DIR ]]; then
    scratch_dir=$SCRATCH_DIR
elif [[ -d /dev/shm && -w /dev/shm ]]; then
    scratch_dir="/dev/shm/classic-worldgen-fuzz/$campaign_name"
else
    scratch_dir="$run_root/scratch/$campaign_name"
fi
classic_jar=${CLASSIC_JAR:-"$repo_root/classic.jar"}
cl_wlgen=${CL_WLGEN:-"$repo_root/cl-wlgen"}
image=${CLASSIC_HARNESS_IMAGE:-classic-worldgen-re-burnin}
jobs=${JOBS:-384}
startup_parallelism=${STARTUP_PARALLELISM:-32}
duration=${DURATION:-12h}
resume=${RESUME:-0}
preflight=${PREFLIGHT:-1}
rebuild_image=${REBUILD_IMAGE:-0}
state_file="$run_root/runner-state.txt"

require_command docker
require_command python3
require_command nproc
require_command sha256sum

[[ -r "$classic_jar" ]] || die "Classic JAR is not readable: $classic_jar"
[[ -x "$cl_wlgen" ]] || die "cl-wlgen is not executable: $cl_wlgen"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"
[[ "$startup_parallelism" =~ ^[1-9][0-9]*$ ]] || die "STARTUP_PARALLELISM must be a positive integer"
(( startup_parallelism <= jobs )) || die "STARTUP_PARALLELISM cannot exceed JOBS"

available_cpus=$(nproc)
(( jobs <= available_cpus )) || die "JOBS=$jobs exceeds the $available_cpus schedulable logical CPUs"

hard_nofile=$(ulimit -Hn)
if [[ "$hard_nofile" == unlimited ]] || (( hard_nofile > 16384 )); then
    target_nofile=16384
else
    target_nofile=$hard_nofile
fi
(( target_nofile >= 4096 )) || die "open-file hard limit is too low for $jobs lanes: $hard_nofile"
ulimit -n "$target_nofile"

mkdir -p "$run_root/campaigns" "$run_root/preflight" "$scratch_dir"

if [[ "$resume" == 1 ]]; then
    [[ -f "$campaign_dir/campaign.sqlite" ]] || die "cannot resume without $campaign_dir/campaign.sqlite"
    resume_args=(--resume)
else
    [[ ! -e "$campaign_dir/campaign.sqlite" ]] || die "campaign already exists; set RESUME=1 and CAMPAIGN_DIR to resume it"
    resume_args=()
fi

if [[ "$rebuild_image" == 1 ]] || ! docker image inspect "$image" >/dev/null 2>&1; then
    printf 'Building harness image %s from %s\n' "$image" "$repo_root"
    docker build --tag "$image" "$repo_root"
fi

# fuzzer_v2 parses these with Python shlex, so quote paths defensively.
printf -v quoted_jar '%q' "$classic_jar"
printf -v quoted_image '%q' "$image"
printf -v quoted_wlgen '%q' "$cl_wlgen"
# The oracle protocol is binary and can be tens of MiB per case.  Docker's
# default json-file logger duplicates every response onto the host filesystem,
# which quickly turns a CPU campaign into a disk-bound one.  The coordinator
# still receives stdout/stderr through the attached streams; this only disables
# redundant persistent container logs for these short-lived workers.
original_worker="docker run --rm -i --log-driver=none --mount type=bind,source=$quoted_jar,target=/harness/classic.jar,readonly --entrypoint java $quoted_image -javaagent:/opt/classic-harness/classic-harness.jar -cp /opt/classic-harness/classic-harness.jar:/harness/classic.jar org.crosscraft.classicworldgen.PersistentClassicHarness --serve"
reference_worker="$quoted_wlgen --serve"

if [[ "$preflight" == 1 && "$resume" != 1 ]]; then
    preflight_dir="$run_root/preflight/preflight-$(date -u +%Y%m%dT%H%M%SZ)"
    printf 'Preflight: validating each persistent worker against the known seed-zero hash\n'
    python3 "$repo_root/fuzzer_v2/smoke_worker.py" --worker "$original_worker" --timeout 120
    python3 "$repo_root/fuzzer_v2/smoke_worker.py" --worker "$reference_worker" --timeout 120
    printf 'Preflight: comparing the complete fixed corpus with one lane\n'
    python3 "$repo_root/fuzzer_v2/fuzzer.py" \
        --campaign-dir "$preflight_dir" \
        --duration 0 \
        --rng-seed 0 \
        --jobs 1 \
        --scratch-dir "$scratch_dir" \
        --oracle-a-worker "$original_worker" \
        --oracle-b-worker "$reference_worker"
fi

ln -sfn "$campaign_dir" "$run_root/current"

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
    printf 'state=running\n'
    printf 'runner_pid=%s\n' "$$"
    printf 'started_at=%s\n' "$started_at"
    printf 'campaign_dir=%s\n' "$campaign_dir"
    printf 'jobs=%s\n' "$jobs"
    printf 'duration=%s\n' "$duration"
    printf 'nofile=%s\n' "$(ulimit -Sn)"
    printf 'cl_wlgen_sha256=%s\n' "$(sha256sum "$cl_wlgen" | awk '{print $1}')"
} > "$state_file"

printf 'Starting campaign %s\n' "$campaign_dir"
printf '  jobs=%s, startup parallelism=%s, duration=%s, nofile=%s\n' \
    "$jobs" "$startup_parallelism" "$duration" "$(ulimit -Sn)"

fuzzer_pid=
forward_signal() {
    if [[ -n "$fuzzer_pid" ]]; then
        # SIGTERM is not ignored by a non-interactive background job.  The
        # fuzzer maps it to its normal, resumable interruption handler.
        kill -TERM "$fuzzer_pid" 2>/dev/null || true
    fi
}
trap forward_signal INT TERM HUP

python3 "$repo_root/fuzzer_v2/fuzzer.py" \
    --campaign-dir "$campaign_dir" \
    --duration "$duration" \
    --jobs "$jobs" \
    --startup-parallelism "$startup_parallelism" \
    --scratch-dir "$scratch_dir" \
    "${resume_args[@]}" \
    --oracle-a-worker "$original_worker" \
    --oracle-b-worker "$reference_worker" &
fuzzer_pid=$!

set +e
wait "$fuzzer_pid"
exit_code=$?
set -e

finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
    printf 'state=finished\n'
    printf 'runner_pid=%s\n' "$$"
    printf 'fuzzer_pid=%s\n' "$fuzzer_pid"
    printf 'started_at=%s\n' "$started_at"
    printf 'finished_at=%s\n' "$finished_at"
    printf 'exit_code=%s\n' "$exit_code"
    printf 'campaign_dir=%s\n' "$campaign_dir"
    printf 'jobs=%s\n' "$jobs"
    printf 'duration=%s\n' "$duration"
    printf 'nofile=%s\n' "$(ulimit -Sn)"
    printf 'cl_wlgen_sha256=%s\n' "$(sha256sum "$cl_wlgen" | awk '{print $1}')"
} > "$state_file"

exit "$exit_code"
