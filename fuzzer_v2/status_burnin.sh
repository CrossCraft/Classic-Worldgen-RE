#!/usr/bin/env bash
# Show the detached burn-in session, persisted state, live SQLite counts, and log tail.
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
run_root=${RUN_ROOT:-"$repo_root/burnin"}
session=${TMUX_SESSION:-cw-fuzz-12h}
log_file=${LOG_FILE:-"$run_root/logs/$session.log"}
state_file="$run_root/runner-state.txt"
current_link="$run_root/current"

printf 'tmux session: '
if tmux has-session -t "$session" 2>/dev/null; then
    printf 'running (%s)\n' "$session"
    tmux list-panes -t "$session" -F '  pane pid=#{pane_pid} command=#{pane_current_command}'
else
    printf 'not present\n'
fi

if [[ -f "$state_file" ]]; then
    printf '\nrunner state:\n'
    sed -n '1,80p' "$state_file"
fi

if [[ -e "$current_link" ]]; then
    campaign_dir=$(readlink -f "$current_link" 2>/dev/null || printf '%s' "$current_link")
    database="$campaign_dir/campaign.sqlite"
    if [[ -f "$database" ]]; then
        printf '\nlive campaign database:\n'
        python3 - "$database" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
try:
    connection = sqlite3.connect("file:" + database + "?mode=ro", uri=True, timeout=2)
    run = connection.execute(
        "SELECT status, random_elapsed_seconds, created_at, updated_at "
        "FROM runs ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    counts = connection.execute(
        "SELECT COUNT(*), "
        "SUM(CASE WHEN phase = 'fixed' THEN 1 ELSE 0 END), "
        "SUM(CASE WHEN phase = 'random' THEN 1 ELSE 0 END), "
        "SUM(CASE WHEN outcome = 'match' THEN 1 ELSE 0 END), "
        "SUM(CASE WHEN outcome = 'mismatch' THEN 1 ELSE 0 END), "
        "SUM(CASE WHEN outcome = 'error' THEN 1 ELSE 0 END), "
        "COALESCE(SUM(CASE WHEN outcome IN ('match', 'mismatch') THEN volume ELSE 0 END), 0) "
        "FROM case_results"
    ).fetchone()
    connection.close()
    print("campaign_dir=" + database.rsplit("/", 1)[0])
    print("status=%s random_elapsed_seconds=%.1f created_at=%s updated_at=%s" % run)
    print(
        "cases=%s fixed=%s random=%s matches=%s mismatches=%s errors=%s blocks_compared=%s"
        % counts
    )
except Exception as error:
    print("database read unavailable: " + str(error))
PY
    fi
fi

if [[ -f "$log_file" ]]; then
    printf '\nlast 35 log lines (%s):\n' "$log_file"
    tail -n 35 "$log_file"
fi
