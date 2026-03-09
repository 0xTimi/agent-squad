#!/bin/bash
# squad-stop.sh — Stop a squad (keep all data)
# Usage: squad-stop.sh <squad-name>

set -euo pipefail

SQUAD_NAME="${1:?Usage: squad-stop.sh <squad-name>}"
TMUX_SESSION="squad-${SQUAD_NAME}"
SQUAD_DIR="${HOME}/.openclaw/workspace/squads/${SQUAD_NAME}"
CRON_NAME="squad-watchdog-${SQUAD_NAME}"

# --- Kill tmux session ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  tmux kill-session -t "$TMUX_SESSION"
  echo "Stopped tmux session: $TMUX_SESSION"
else
  echo "tmux session '$TMUX_SESSION' was not running."
fi

# --- Remove watchdog cron ---
openclaw cron remove --name "$CRON_NAME" 2>/dev/null && \
  echo "Removed watchdog cron: $CRON_NAME" || \
  echo "No watchdog cron found for '$CRON_NAME'."

# --- Log the stop event ---
if [ -d "$SQUAD_DIR/logs" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Squad stopped by user." >> "$SQUAD_DIR/logs/watchdog.log"
fi

echo ""
echo "Squad '$SQUAD_NAME' stopped. All data preserved at:"
echo "  $SQUAD_DIR"
echo ""
echo "To restart: squad-start.sh $SQUAD_NAME <engine>"
