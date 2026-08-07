#!/usr/bin/env bash
# Start run_burnin_12h.sh in an attachable tmux session and durable log.
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
run_root=${RUN_ROOT:-"$repo_root/burnin"}
session=${TMUX_SESSION:-cw-fuzz-12h}
log_file=${LOG_FILE:-"$run_root/logs/$session.log"}

command -v tmux >/dev/null 2>&1 || {
    printf 'error: tmux is required to launch the detached campaign\n' >&2
    exit 2
}

mkdir -p "$(dirname -- "$log_file")"

if tmux has-session -t "$session" 2>/dev/null; then
    printf 'error: tmux session %s already exists; attach with: tmux attach -t %s\n' \
        "$session" "$session" >&2
    exit 1
fi

printf -v tmux_command 'exec %q >> %q 2>&1' "$script_dir/run_burnin_12h.sh" "$log_file"
tmux new-session -d -s "$session" "$tmux_command"

sleep 1
if ! tmux has-session -t "$session" 2>/dev/null; then
    printf 'error: the tmux session exited immediately; last log lines follow:\n' >&2
    tail -n 80 "$log_file" >&2 || true
    exit 2
fi

printf 'Started tmux session %s.\n' "$session"
printf 'Attach: tmux attach -t %s\n' "$session"
printf 'Status: %s/status_burnin.sh\n' "$script_dir"
printf 'Log: %s\n' "$log_file"
