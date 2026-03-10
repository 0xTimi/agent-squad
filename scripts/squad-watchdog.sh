#!/bin/bash
# squad-watchdog.sh — Health check and auto-restart for a squad
# Called by openclaw cron every 10 minutes
# Usage: squad-watchdog.sh <squad-name>

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:$PATH"

SQUADS_DIR="${HOME}/.openclaw/workspace/agent-squad/squads"
SQUAD_NAME="${1:?Usage: squad-watchdog.sh <squad-name>}"
SQUAD_DIR="${SQUADS_DIR}/${SQUAD_NAME}"
TMUX_SESSION="squad-${SQUAD_NAME}"
LOG_FILE="${SQUAD_DIR}/logs/watchdog.log"

# --- Check squad directory exists ---
if [ ! -d "$SQUAD_DIR" ]; then
  echo "ERROR: Squad directory not found: $SQUAD_DIR"
  exit 1
fi

# --- Read squad config ---
if [ ! -f "$SQUAD_DIR/squad.json" ]; then
  echo "ERROR: squad.json not found in $SQUAD_DIR"
  exit 1
fi

SQUAD_JSON="$SQUAD_DIR/squad.json"
ENGINE_CMD=$(python3 -c "import json; print(json.load(open('$SQUAD_JSON'))['engine_command'])" 2>/dev/null)
if [ -z "$ENGINE_CMD" ]; then
  echo "ERROR: Could not read engine_command from squad.json"
  exit 1
fi

PROJECT_DIR=$(python3 -c "import json; print(json.load(open('$SQUAD_JSON')).get('project_dir', ''))" 2>/dev/null)
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  PROJECT_DIR="$SQUAD_DIR"
fi

AGENT_TEAMS=$(python3 -c "import json; print(json.load(open('$SQUAD_JSON')).get('agent_teams', False))" 2>/dev/null)
TMUX_ENV="SQUAD_DIR=${SQUAD_DIR}"
if [ "$AGENT_TEAMS" = "True" ]; then
  TMUX_ENV="$TMUX_ENV CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
fi

# --- Check tmux session ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  # Session exists — check if the engine is still running inside
  PANE_PID=$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)
  if [ -n "$PANE_PID" ]; then
    # Check if pane has active child processes (the AI engine)
    CHILDREN=$(pgrep -P "$PANE_PID" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CHILDREN" -gt 0 ]; then
      # Engine is running, all good
      exit 0
    fi
  fi

  # tmux session exists but engine has exited — restart engine inside existing session
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Engine exited in session $TMUX_SESSION. Restarting..." >> "$LOG_FILE"
  tmux send-keys -t "$TMUX_SESSION" "$TMUX_ENV $ENGINE_CMD" Enter
  sleep 5
  tmux send-keys -t "$TMUX_SESSION" "You are ${SQUAD_NAME}, a persistent development coordinator. Your coordination directory is ${SQUAD_DIR} — read ${SQUAD_DIR}/PROTOCOL.md for your full instructions. Read ${SQUAD_DIR}/logs/coordinator-summary.md if it exists to resume. Check ${SQUAD_DIR}/tasks/pending/ and ${SQUAD_DIR}/tasks/in-progress/. Write code in ${PROJECT_DIR}. Continue working." Enter
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Engine restarted in existing session." >> "$LOG_FILE"
  echo "RESTARTED: Engine was dead inside tmux session. Restarted."
  exit 0
fi

# --- tmux session does not exist — full restart ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Session $TMUX_SESSION not found. Full restart..." >> "$LOG_FILE"

tmux new-session -d -s "$TMUX_SESSION" -c "$PROJECT_DIR" "$TMUX_ENV $ENGINE_CMD"

{
  sleep 5
  tmux send-keys -t "$TMUX_SESSION" "You are ${SQUAD_NAME}, a persistent development coordinator. Your coordination directory is ${SQUAD_DIR} — read ${SQUAD_DIR}/PROTOCOL.md for your full instructions. Read ${SQUAD_DIR}/logs/coordinator-summary.md if it exists to resume. Check ${SQUAD_DIR}/tasks/pending/ and ${SQUAD_DIR}/tasks/in-progress/. Write code in ${PROJECT_DIR}. Continue working." Enter
} &

echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Full restart completed." >> "$LOG_FILE"
echo "RESTARTED: tmux session was gone. Created new session and started engine."
