#!/bin/bash
# squad-list.sh — List all squads and their status
# Usage: squad-list.sh

set -euo pipefail

SQUADS_DIR="${HOME}/.openclaw/workspace/squads"

# --- Check squads directory ---
if [ ! -d "$SQUADS_DIR" ]; then
  echo "No squads found. Start one with squad-start.sh."
  exit 0
fi

# --- Find all squads ---
SQUAD_COUNT=0
for squad_dir in "$SQUADS_DIR"/*/; do
  [ -d "$squad_dir" ] || continue
  SQUAD_NAME=$(basename "$squad_dir")
  TMUX_SESSION="squad-${SQUAD_NAME}"

  # Skip hidden dirs and .archive
  [[ "$SQUAD_NAME" == .* ]] && continue

  # Read engine
  ENGINE="?"
  if [ -f "$squad_dir/squad.json" ]; then
    ENGINE=$(python3 -c "import json; print(json.load(open('${squad_dir}squad.json')).get('engine', '?'))" 2>/dev/null || echo "?")
  fi

  # tmux status
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    STATUS="running"
  else
    STATUS="stopped"
  fi

  # Count tasks
  PENDING=$(find "$squad_dir/tasks/pending" -name "task-*.md" 2>/dev/null | wc -l | tr -d ' ')
  IN_PROG=$(find "$squad_dir/tasks/in-progress" -name "task-*.md" 2>/dev/null | wc -l | tr -d ' ')
  DONE=$(find "$squad_dir/tasks/done" -name "task-*.md" 2>/dev/null | wc -l | tr -d ' ')

  if [ "$SQUAD_COUNT" -eq 0 ]; then
    printf "%-20s %-12s %-10s %s\n" "SQUAD" "ENGINE" "STATUS" "TASKS (P/A/D)"
    printf "%-20s %-12s %-10s %s\n" "-----" "------" "------" "-------------"
  fi

  printf "%-20s %-12s %-10s %s/%s/%s\n" "$SQUAD_NAME" "$ENGINE" "$STATUS" "$PENDING" "$IN_PROG" "$DONE"
  SQUAD_COUNT=$((SQUAD_COUNT + 1))
done

if [ "$SQUAD_COUNT" -eq 0 ]; then
  echo "No squads found. Start one with squad-start.sh."
fi
