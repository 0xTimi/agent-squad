#!/bin/bash
# squad-start.sh — Create and launch a new squad
# Usage: squad-start.sh <squad-name> <engine> [context-text]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
SQUADS_DIR="${HOME}/.openclaw/workspace/squads"

# --- Args ---
SQUAD_NAME="${1:?Usage: squad-start.sh <squad-name> <engine> [context-text]}"
ENGINE="${2:?Usage: squad-start.sh <squad-name> <engine> [context-text]}"
CONTEXT="${3:-}"

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

# --- Check for existing squad ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: Squad '$SQUAD_NAME' is already running (tmux session '$TMUX_SESSION' exists)"
  exit 1
fi

if [ -d "$SQUAD_DIR" ]; then
  echo "INFO: Squad directory already exists. Restarting squad with existing data."
fi

# --- Create directory structure ---
mkdir -p "$SQUAD_DIR"/{tasks/pending,tasks/in-progress,tasks/done,reports,logs}

# --- Write squad.json ---
cat > "$SQUAD_DIR/squad.json" <<EOF
{
  "name": "${SQUAD_NAME}",
  "engine": "${ENGINE}",
  "engine_command": "${ENGINE_CMD}",
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

# --- Start tmux session ---
tmux new-session -d -s "$TMUX_SESSION" -c "$SQUAD_DIR" "$ENGINE_CMD"

# --- Send initial prompt ---
{
  sleep 5
  INIT_PROMPT="You are ${SQUAD_NAME}, a persistent development coordinator. Read PROTOCOL.md for your full instructions. Then check CONTEXT.md if it exists for project background. Then check tasks/pending/ for new tasks and tasks/in-progress/ for tasks to resume. Start working."
  tmux send-keys -t "$TMUX_SESSION" "$INIT_PROMPT" Enter
} &

# --- Register watchdog cron ---
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

# --- Output ---
echo ""
echo "Squad '${SQUAD_NAME}' started successfully."
echo ""
echo "  Engine:      ${ENGINE}"
echo "  Directory:   ${SQUAD_DIR}"
echo "  tmux:        tmux attach -t ${TMUX_SESSION}  (Ctrl+B D to detach)"
echo "  Watchdog:    openclaw cron (every 10 min)"
echo ""
