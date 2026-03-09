#!/bin/bash
# squad-ping.sh — Ask a squad to update its status report
# Usage: squad-ping.sh <squad-name>

set -euo pipefail

SQUAD_NAME="${1:?Usage: squad-ping.sh <squad-name>}"
TMUX_SESSION="squad-${SQUAD_NAME}"

# --- Check tmux session exists ---
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: Squad '$SQUAD_NAME' is not running (no tmux session '$TMUX_SESSION')."
  exit 1
fi

# --- Send ping ---
tmux send-keys -t "$TMUX_SESSION" Escape 2>/dev/null || true
sleep 1
tmux send-keys -t "$TMUX_SESSION" "Please update your report now: write your current progress, completed items, any issues, and next steps to the appropriate reports/task-*.md file. Update the ## Current section so it reflects your real-time state." Enter

echo "Pinged squad '$SQUAD_NAME'. Check status in a minute to see the updated report."
