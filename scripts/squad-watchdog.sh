#!/bin/bash
# squad-watchdog.sh — Health check and auto-restart for a squad
# Called by openclaw cron every 5 minutes
# Usage: squad-watchdog.sh <squad-name>

set -euo pipefail

# --- Cross-platform PATH setup ---
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
[ -d "${HOME}/.local/bin" ] && export PATH="${HOME}/.local/bin:$PATH"

SQUADS_DIR="${HOME}/.openclaw/workspace/agent-squad/squads"
SQUAD_NAME="${1:?Usage: squad-watchdog.sh <squad-name>}"

# --- Validate squad name ---
if [[ ! "$SQUAD_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: Invalid squad name '$SQUAD_NAME'."
  exit 1
fi

SQUAD_DIR="${SQUADS_DIR}/${SQUAD_NAME}"
TMUX_SESSION="squad-${SQUAD_NAME}"
LOG_FILE="${SQUAD_DIR}/logs/watchdog.log"

# --- Log rotation (max ~5MB, keep 1 backup) ---
if [ -f "$LOG_FILE" ]; then
  LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
  if [ "${LOG_SIZE:-0}" -gt 5242880 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
fi

# --- Check squad directory exists ---
if [ ! -d "$SQUAD_DIR" ]; then
  echo "ERROR: Squad directory not found: $SQUAD_DIR"
  exit 1
fi

# --- Check python3 ---
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found."
  exit 1
fi

# --- Read squad config (safe via sys.argv) ---
SQUAD_JSON="$SQUAD_DIR/squad.json"
if [ ! -f "$SQUAD_JSON" ]; then
  echo "ERROR: squad.json not found in $SQUAD_DIR"
  exit 1
fi

# Read engine, project_dir, agent_teams from squad.json in a single python3 call
eval "$(python3 -c "
import json, sys, shlex
d = json.load(open(sys.argv[1]))
print(f'ENGINE={shlex.quote(d.get(\"engine\", \"\"))}')
print(f'PROJECT_DIR={shlex.quote(d.get(\"project_dir\", \"\"))}')
print(f'AGENT_TEAMS={\"true\" if d.get(\"agent_teams\") else \"false\"}')
" "$SQUAD_JSON" 2>/dev/null)"

if [ -z "$ENGINE" ]; then
  echo "ERROR: Could not read engine from squad.json"
  exit 1
fi

# Re-derive engine command from engine name (never trust stored engine_command)
get_engine_command() {
  case "$1" in
    claude)    echo "claude --dangerously-skip-permissions" ;;
    codex)     echo "codex --full-auto" ;;
    gemini)    echo "gemini" ;;
    opencode)  echo "opencode" ;;
    kimi)      echo "kimi" ;;
    trae)      echo "trae-agent" ;;
    aider)     echo "aider --yes" ;;
    goose)     echo "goose" ;;
    *)         echo "" ;;
  esac
}

ENGINE_CMD=$(get_engine_command "$ENGINE")
if [ -z "$ENGINE_CMD" ]; then
  echo "ERROR: Unknown engine '$ENGINE'"
  exit 1
fi

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  PROJECT_DIR="$SQUAD_DIR"
fi

# Build env-prefixed command
TMUX_CMD="env SQUAD_DIR='${SQUAD_DIR}'"
if [ "$AGENT_TEAMS" = "true" ]; then
  TMUX_CMD="$TMUX_CMD CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
fi
TMUX_CMD="$TMUX_CMD $ENGINE_CMD"

RESTART_PROMPT="You are ${SQUAD_NAME}, a persistent AI development coordinator. Your coordination directory is ${SQUAD_DIR} — read ${SQUAD_DIR}/PROTOCOL.md immediately for your complete instructions. Read ${SQUAD_DIR}/logs/coordinator-summary.md if it exists to resume. Check ${SQUAD_DIR}/tasks/pending/ and ${SQUAD_DIR}/tasks/in-progress/. Write code in ${PROJECT_DIR}. Continue working."

# --- Check tmux session ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  # Session exists — check if the engine is still running inside
  PANE_PID="$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)"
  if [ -n "$PANE_PID" ]; then
    if pgrep -P "$PANE_PID" >/dev/null 2>&1; then
      # Engine is running, all good
      exit 0
    fi
  fi

  # tmux session exists but engine has exited — restart engine inside existing session
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Engine exited in session $TMUX_SESSION. Restarting..." >> "$LOG_FILE"
  tmux send-keys -t "$TMUX_SESSION" "$TMUX_CMD" Enter
  sleep 5
  tmux send-keys -t "$TMUX_SESSION" "$RESTART_PROMPT" Enter
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Engine restarted in existing session." >> "$LOG_FILE"
  echo "RESTARTED: Engine was dead inside tmux session. Restarted."
  exit 0
fi

# --- tmux session does not exist — full restart ---
echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Session $TMUX_SESSION not found. Full restart..." >> "$LOG_FILE"

tmux new-session -d -s "$TMUX_SESSION" -c "$PROJECT_DIR" "$TMUX_CMD"

{
  sleep 5
  tmux send-keys -t "$TMUX_SESSION" "$RESTART_PROMPT" Enter
} &

echo "[$(date -u +%Y-%m-%dT%H:%M:%S+00:00)] Full restart completed." >> "$LOG_FILE"
echo "RESTARTED: tmux session was gone. Created new session and started engine."
