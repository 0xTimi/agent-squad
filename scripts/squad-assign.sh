#!/bin/bash
# squad-assign.sh — Assign a task to a squad
# Usage: squad-assign.sh <squad-name> <task-title> <objective> [target-path] [priority]

set -euo pipefail

SQUAD_NAME="${1:?Usage: squad-assign.sh <squad-name> <task-title> <objective> [target-path] [priority]}"
TASK_TITLE="${2:?Usage: squad-assign.sh <squad-name> <task-title> <objective> [target-path] [priority]}"
OBJECTIVE="${3:?Usage: squad-assign.sh <squad-name> <task-title> <objective> [target-path] [priority]}"
TARGET="${4:-}"
PRIORITY="${5:-normal}"

SQUAD_DIR="${HOME}/.openclaw/workspace/squads/${SQUAD_NAME}"
TMUX_SESSION="squad-${SQUAD_NAME}"

# --- Check squad exists ---
if [ ! -d "$SQUAD_DIR" ]; then
  echo "ERROR: Squad '$SQUAD_NAME' not found. Start it first with squad-start.sh."
  exit 1
fi

# --- Generate filename ---
DATE=$(date +%Y%m%d)
KEBAB_TITLE=$(echo "$TASK_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
TASK_FILE="task-${DATE}-${KEBAB_TITLE}.md"
TASK_PATH="${SQUAD_DIR}/tasks/pending/${TASK_FILE}"

# --- Avoid overwrite ---
if [ -f "$TASK_PATH" ]; then
  TASK_FILE="task-${DATE}-${KEBAB_TITLE}-$(date +%H%M%S).md"
  TASK_PATH="${SQUAD_DIR}/tasks/pending/${TASK_FILE}"
fi

# --- Write task file (atomic) ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S+00:00)
TMP_PATH="${TASK_PATH}.tmp"

cat > "$TMP_PATH" <<EOF
# Task: ${TASK_TITLE}

## Created
${TIMESTAMP}

## Context
Assigned by user via agent-squad.

## Objective
${OBJECTIVE}

## Target
${TARGET:-Not specified}

## Acceptance Criteria
- [ ] Objective completed as described
- [ ] All changes committed and pushed
- [ ] Report updated with results

## Priority
${PRIORITY}
EOF

mv "$TMP_PATH" "$TASK_PATH"

# --- Notify squad via tmux if running ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  tmux send-keys -t "$TMUX_SESSION" Escape 2>/dev/null || true
  sleep 1
  tmux send-keys -t "$TMUX_SESSION" "New task assigned: check tasks/pending/${TASK_FILE} and start working on it." Enter
  echo "Task assigned and squad notified."
else
  echo "Task assigned. Squad is not currently running — it will pick up the task when restarted."
fi

echo ""
echo "  Squad:    ${SQUAD_NAME}"
echo "  Task:     ${TASK_TITLE}"
echo "  File:     ${TASK_PATH}"
echo "  Priority: ${PRIORITY}"
