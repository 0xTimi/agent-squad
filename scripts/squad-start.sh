#!/bin/bash
# squad-start.sh — Create and launch a new squad
# Usage: squad-start.sh <squad-name> <engine> [context-text] [--project <dir>] [--restart] [--agent-teams]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="${HOME}/.openclaw/workspace/agent-squad"
SQUADS_DIR="${BASE_DIR}/squads"

# --- Args (python3 not needed yet) ---
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

# --- Validate squad name (lowercase alphanumeric + hyphens) ---
if [[ ! "$SQUAD_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: Squad name must be lowercase alphanumeric with hyphens (e.g., 'my-squad')"
  exit 1
fi

# --- Validate --agent-teams flag ---
if [ "$AGENT_TEAMS" = true ] && [ "$ENGINE" != "claude" ]; then
  echo "ERROR: --agent-teams is only supported with the claude engine."
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

ENGINE_CMD=$(get_engine_command "$ENGINE")
ENGINE_BIN="${ENGINE_CMD%% *}"

if [ -z "$ENGINE_CMD" ]; then
  echo "ERROR: Unknown engine '$ENGINE'. Supported: claude, codex, gemini, opencode, kimi, trae, aider, goose"
  exit 1
fi

# --- Environment check: collect all issues, report together ---
ERRORS=()
WARNINGS=()

if ! command -v python3 &>/dev/null; then
  ERRORS+=("python3 is required but not found. Install: https://www.python.org/downloads/")
fi

if ! command -v tmux &>/dev/null; then
  ERRORS+=("tmux is required but not found. Install: brew install tmux (macOS) or apt install tmux (Linux)")
fi

if ! command -v "$ENGINE_BIN" &>/dev/null; then
  ERRORS+=("'$ENGINE_BIN' (engine: $ENGINE) is not found in PATH. Please install it first.")
fi

if ! command -v git &>/dev/null; then
  WARNINGS+=("git is not installed. Code changes won't be version-controlled — consider installing git for safety backups.")
fi

if ! command -v openclaw &>/dev/null; then
  WARNINGS+=("openclaw not found. Watchdog cron won't be registered — the squad will run but won't auto-recover from crashes.")
fi

# Report warnings first, then errors
if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo ""
  for w in "${WARNINGS[@]}"; do
    echo "WARNING: $w"
  done
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  for e in "${ERRORS[@]}"; do
    echo "ERROR: $e"
  done
  echo ""
  echo "Fix the errors above before starting a squad."
  exit 1
fi

OPENCLAW_AVAILABLE=true
command -v openclaw &>/dev/null || OPENCLAW_AVAILABLE=false

# --- Default project dir (read from config or use built-in default) ---
if [ -z "$PROJECT_DIR" ]; then
  CONFIGURED_DIR=""
  if [ -f "${BASE_DIR}/config.json" ]; then
    CONFIGURED_DIR=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('projects_dir', ''))" "${BASE_DIR}/config.json" 2>/dev/null || echo "")
  fi
  if [ -n "$CONFIGURED_DIR" ]; then
    PROJECT_DIR="${CONFIGURED_DIR}/${SQUAD_NAME}"
  else
    PROJECT_DIR="${BASE_DIR}/projects/${SQUAD_NAME}"
  fi
fi

TMUX_SESSION="squad-${SQUAD_NAME}"
SQUAD_DIR="${SQUADS_DIR}/${SQUAD_NAME}"

# --- Validate / create project directory ---
if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR"
fi
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# --- Initialize git if available ---
if command -v git &>/dev/null; then
  if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "$PROJECT_DIR" init -q
    git -C "$PROJECT_DIR" add -A 2>/dev/null || true
    git -C "$PROJECT_DIR" commit -q -m "initial commit (before squad)" --allow-empty 2>/dev/null || true
    GIT_INITIALIZED=true
  else
    GIT_INITIALIZED=already
  fi
else
  GIT_INITIALIZED=false
fi

# --- Engine-specific validation ---
case "$ENGINE" in
  codex)
    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
      echo "WARNING: codex requires a git repository. '$PROJECT_DIR' is not a git repo."
      echo "         Run 'git init' in the project directory first, or codex may fail."
    fi
    ;;
esac

# --- Check for existing squad ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: Squad '$SQUAD_NAME' is already running (tmux session '$TMUX_SESSION' exists)"
  exit 1
fi

if [ -d "$SQUAD_DIR" ]; then
  if [ "$RESTART" = true ]; then
    if [ ! -f "$SQUAD_DIR/squad.json" ]; then
      echo "ERROR: Squad directory exists but squad.json is missing or corrupted."
      exit 1
    fi
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
mkdir -p "$SQUAD_DIR"/{tasks/pending,tasks/in-progress,tasks/done,tasks/cancelled,reports,logs}

# --- Write squad.json (safe via python3) ---
python3 -c "
import json, sys
data = {
    'name': sys.argv[1],
    'engine': sys.argv[2],
    'engine_command': sys.argv[3],
    'agent_teams': sys.argv[4] == 'true',
    'project_dir': sys.argv[5],
    'tmux_session': sys.argv[6],
    'created_at': sys.argv[7],
    'squads_dir': sys.argv[8]
}
with open(sys.argv[9], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$SQUAD_NAME" "$ENGINE" "$ENGINE_CMD" "$AGENT_TEAMS" "$PROJECT_DIR" "$TMUX_SESSION" \
  "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" "$SQUADS_DIR" "$SQUAD_DIR/squad.json"

# --- Render PROTOCOL.md from template ---
if [ ! -f "$SQUAD_DIR/PROTOCOL.md" ]; then
  TEMPLATE="$SKILL_DIR/assets/PROTOCOL.md.template"
  if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Template not found: $TEMPLATE"
    exit 1
  fi
  # Use python3 for safe template rendering (no sed escaping issues)
  python3 -c "
import sys
with open(sys.argv[1]) as f:
    content = f.read()
content = content.replace('{{SQUAD_NAME}}', sys.argv[2])
content = content.replace('{{ENGINE}}', sys.argv[3])
with open(sys.argv[4], 'w') as f:
    f.write(content)
" "$TEMPLATE" "$SQUAD_NAME" "$ENGINE" "$SQUAD_DIR/PROTOCOL.md"
fi

# --- Write CONTEXT.md if provided ---
if [ -n "$CONTEXT" ] && [ ! -f "$SQUAD_DIR/CONTEXT.md" ]; then
  CONTEXT_TEMPLATE="$SKILL_DIR/assets/CONTEXT.md.template"
  if [ -f "$CONTEXT_TEMPLATE" ]; then
    python3 -c "
import sys
with open(sys.argv[1]) as f:
    content = f.read()
content = content.replace('{{CONTEXT}}', sys.argv[2])
with open(sys.argv[3], 'w') as f:
    f.write(content)
" "$CONTEXT_TEMPLATE" "$CONTEXT" "$SQUAD_DIR/CONTEXT.md"
  fi
fi

# --- Add .gitkeep files ---
for dir in tasks/pending tasks/in-progress tasks/done tasks/cancelled reports; do
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

# --- Start tmux session (cwd = project dir, env vars for coordination) ---
TMUX_CMD="env SQUAD_DIR='${SQUAD_DIR}'"
if [ "$AGENT_TEAMS" = true ]; then
  TMUX_CMD="$TMUX_CMD CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
fi
TMUX_CMD="$TMUX_CMD $ENGINE_CMD"
tmux new-session -d -s "$TMUX_SESSION" -c "$PROJECT_DIR" "$TMUX_CMD"

# --- Send initial prompt ---
{
  sleep 5
  INIT_PROMPT="You are ${SQUAD_NAME}, a persistent AI development coordinator. Your coordination directory is ${SQUAD_DIR} — read ${SQUAD_DIR}/PROTOCOL.md immediately, it contains your complete instructions. Check ${SQUAD_DIR}/CONTEXT.md if it exists for project background. Your code goes in the current directory (${PROJECT_DIR}). Check ${SQUAD_DIR}/tasks/pending/ for new tasks and ${SQUAD_DIR}/tasks/in-progress/ for tasks to resume. Write reports to ${SQUAD_DIR}/reports/. Begin."
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
    --cron "*/5 * * * *" \
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
if [ "$GIT_INITIALIZED" = true ]; then
  echo "  Git:         initialized (safety backup enabled)"
elif [ "$GIT_INITIALIZED" = already ]; then
  echo "  Git:         already initialized"
else
  echo "  Git:         not installed (no automatic backup — consider installing git)"
fi
echo "  Squad data:  ${SQUAD_DIR}"
echo "  tmux:        tmux attach -t ${TMUX_SESSION}  (Ctrl+B D to detach)"
if [ "$OPENCLAW_AVAILABLE" = true ]; then
  echo "  Watchdog:    openclaw cron (every 5 min)"
else
  echo "  Watchdog:    not registered (openclaw not found)"
fi
echo ""
