#!/bin/bash
# squad-start.sh — Create and launch a new squad
# Usage: squad-start.sh <squad-name> <engine> [context-text]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="${HOME}/.openclaw/workspace/agent-squad"
SQUADS_DIR="${BASE_DIR}/squads"

# --- Args ---
SQUAD_NAME="${1:?Usage: squad-start.sh <squad-name> <engine> [context-text] [--project <dir>] [--restart] [--agent-teams]}"
ENGINE="${2:?Usage: squad-start.sh <squad-name> <engine> [context-text] [--project <dir>] [--restart] [--agent-teams]}"
CONTEXT=""
RESTART=false
AGENT_TEAMS=false
PROJECT_DIR=""
args=("${@:3}")
i=0
while [ $i -lt ${#args[@]} ]; do
  case "${args[$i]}" in
    --restart)     RESTART=true ;;
    --agent-teams) AGENT_TEAMS=true ;;
    --project)     i=$((i + 1)); PROJECT_DIR="${args[$i]}" ;;
    *)             CONTEXT="${args[$i]}" ;;
  esac
  i=$((i + 1))
done

# Default project dir (read from config or use built-in default)
if [ -z "$PROJECT_DIR" ]; then
  CONFIGURED_DIR=""
  if [ -f "${BASE_DIR}/config.json" ]; then
    CONFIGURED_DIR=$(python3 -c "import json; print(json.load(open('${BASE_DIR}/config.json')).get('projects_dir', ''))" 2>/dev/null || echo "")
  fi
  if [ -n "$CONFIGURED_DIR" ]; then
    PROJECT_DIR="${CONFIGURED_DIR}/${SQUAD_NAME}"
  else
    PROJECT_DIR="${BASE_DIR}/projects/${SQUAD_NAME}"
  fi
fi

TMUX_SESSION="squad-${SQUAD_NAME}"
SQUAD_DIR="${SQUADS_DIR}/${SQUAD_NAME}"

# --- Validate squad name (lowercase alphanumeric + hyphens) ---
if [[ ! "$SQUAD_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: Squad name must be lowercase alphanumeric with hyphens (e.g., 'my-squad')"
  exit 1
fi

# --- Check tmux is available ---
if ! command -v tmux &>/dev/null; then
  echo "ERROR: tmux is not installed. Install it with: brew install tmux (macOS) or apt install tmux (Linux)"
  exit 1
fi

# --- Check openclaw is available (needed for watchdog cron) ---
if ! command -v openclaw &>/dev/null; then
  echo "WARNING: openclaw not found in PATH. Watchdog cron will not be registered."
  echo "         The squad will still run, but won't auto-recover if it crashes."
  OPENCLAW_AVAILABLE=false
else
  OPENCLAW_AVAILABLE=true
fi

# --- Validate / create project directory ---
if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR"
fi
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# --- Resolve engine command ---
get_engine_command() {
  local engine="$1"
  case "$engine" in
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

get_engine_binary() {
  local engine="$1"
  case "$engine" in
    claude)    echo "claude" ;;
    codex)     echo "codex" ;;
    gemini)    echo "gemini" ;;
    opencode)  echo "opencode" ;;
    kimi)      echo "kimi" ;;
    trae)      echo "trae-agent" ;;
    aider)     echo "aider" ;;
    goose)     echo "goose" ;;
    *)         echo "$engine" ;;
  esac
}

ENGINE_CMD=$(get_engine_command "$ENGINE")
ENGINE_BIN=$(get_engine_binary "$ENGINE")

if [ -z "$ENGINE_CMD" ]; then
  echo "ERROR: Unknown engine '$ENGINE'. Supported: claude, codex, gemini, opencode, kimi, trae, aider, goose"
  exit 1
fi

# --- Check engine binary exists ---
if ! command -v "$ENGINE_BIN" &>/dev/null; then
  echo "ERROR: '$ENGINE_BIN' not found in PATH. Please install it first."
  exit 1
fi

# --- Validate --agent-teams flag ---
if [ "$AGENT_TEAMS" = true ] && [ "$ENGINE" != "claude" ]; then
  echo "ERROR: --agent-teams is only supported with the claude engine."
  exit 1
fi

# --- Check for existing squad ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: Squad '$SQUAD_NAME' is already running (tmux session '$TMUX_SESSION' exists)"
  exit 1
fi

if [ -d "$SQUAD_DIR" ]; then
  if [ "$RESTART" = true ]; then
    echo "Restarting squad '$SQUAD_NAME' with existing data."
  else
    echo "ERROR: Squad '$SQUAD_NAME' already exists at $SQUAD_DIR"
    echo ""
    echo "  To restart it with existing data:  add --restart flag"
    echo "  To create a fresh squad:           pick a different name"
    exit 1
  fi
fi

# --- Create directory structure ---
mkdir -p "$SQUAD_DIR"/{tasks/pending,tasks/in-progress,tasks/done,reports,logs}

# --- Write squad.json ---
cat > "$SQUAD_DIR/squad.json" <<EOF
{
  "name": "${SQUAD_NAME}",
  "engine": "${ENGINE}",
  "engine_command": "${ENGINE_CMD}",
  "agent_teams": ${AGENT_TEAMS},
  "project_dir": "${PROJECT_DIR}",
  "tmux_session": "${TMUX_SESSION}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)",
  "squads_dir": "${SQUADS_DIR}"
}
EOF

# --- Render PROTOCOL.md from template ---
if [ ! -f "$SQUAD_DIR/PROTOCOL.md" ]; then
  sed \
    -e "s|{{SQUAD_NAME}}|${SQUAD_NAME}|g" \
    -e "s|{{ENGINE}}|${ENGINE}|g" \
    "$SKILL_DIR/assets/PROTOCOL.md.template" \
    > "$SQUAD_DIR/PROTOCOL.md"
fi

# --- Write CONTEXT.md if provided ---
if [ -n "$CONTEXT" ] && [ ! -f "$SQUAD_DIR/CONTEXT.md" ]; then
  sed \
    -e "s|{{CONTEXT}}|${CONTEXT}|g" \
    "$SKILL_DIR/assets/CONTEXT.md.template" \
    > "$SQUAD_DIR/CONTEXT.md"
fi

# --- Add .gitkeep files ---
for dir in tasks/pending tasks/in-progress tasks/done reports; do
  touch "$SQUAD_DIR/$dir/.gitkeep" 2>/dev/null || true
done

# --- Add logs/.gitignore ---
if [ ! -f "$SQUAD_DIR/logs/.gitignore" ]; then
  cat > "$SQUAD_DIR/logs/.gitignore" <<'GITIGNORE'
*.log
*.jsonl
!.gitkeep
GITIGNORE
fi

# --- Start tmux session (cwd = project dir, SQUAD_DIR env var for coordination) ---
TMUX_ENV="SQUAD_DIR=${SQUAD_DIR}"
if [ "$AGENT_TEAMS" = true ]; then
  TMUX_ENV="$TMUX_ENV CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
fi
tmux new-session -d -s "$TMUX_SESSION" -c "$PROJECT_DIR" "$TMUX_ENV $ENGINE_CMD"

# --- Send initial prompt ---
{
  sleep 5
  INIT_PROMPT="You are ${SQUAD_NAME}, a persistent development coordinator. Your coordination directory is ${SQUAD_DIR} — read ${SQUAD_DIR}/PROTOCOL.md for your full instructions. Check ${SQUAD_DIR}/CONTEXT.md if it exists for project background. Your code goes in the current directory (${PROJECT_DIR}). Check ${SQUAD_DIR}/tasks/pending/ for new tasks and ${SQUAD_DIR}/tasks/in-progress/ for tasks to resume. Write reports to ${SQUAD_DIR}/reports/. Start working."
  tmux send-keys -t "$TMUX_SESSION" "$INIT_PROMPT" Enter
} &

# --- Register watchdog cron ---
if [ "$OPENCLAW_AVAILABLE" = true ]; then
  WATCHDOG_PATH="${SKILL_DIR}/scripts/squad-watchdog.sh"
  CRON_NAME="squad-watchdog-${SQUAD_NAME}"

  # Remove existing cron if any
  openclaw cron remove --name "$CRON_NAME" 2>/dev/null || true

  openclaw cron add \
    --name "$CRON_NAME" \
    --cron "*/10 * * * *" \
    --session isolated \
    --light-context \
    --message "Run this command to check squad health: bash ${WATCHDOG_PATH} ${SQUAD_NAME}. If the script reports the squad restarted, say so. If healthy, do nothing." \
    2>/dev/null || echo "WARNING: Could not register cron watchdog. You may need to monitor the squad manually."
fi

# --- Output ---
echo ""
echo "Squad '${SQUAD_NAME}' started successfully."
echo ""
echo "  Engine:      ${ENGINE}"
if [ "$AGENT_TEAMS" = true ]; then
  echo "  Mode:        agent-teams (multi-agent coordination)"
fi
echo "  Project:     ${PROJECT_DIR}"
echo "  Squad data:  ${SQUAD_DIR}"
echo "  tmux:        tmux attach -t ${TMUX_SESSION}  (Ctrl+B D to detach)"
if [ "$OPENCLAW_AVAILABLE" = true ]; then
  echo "  Watchdog:    openclaw cron (every 10 min)"
else
  echo "  Watchdog:    not registered (openclaw not found)"
fi
echo ""
