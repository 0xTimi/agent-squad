#!/bin/bash
# squad-config.sh — View or update agent-squad settings
# Usage: squad-config.sh show
#        squad-config.sh set <key> <value>

set -euo pipefail

BASE_DIR="${HOME}/.openclaw/workspace/agent-squad"
CONFIG_FILE="${BASE_DIR}/config.json"

ACTION="${1:?Usage: squad-config.sh show | set <key> <value>}"

case "$ACTION" in
  show)
    if [ -f "$CONFIG_FILE" ]; then
      echo "Config: $CONFIG_FILE"
      echo ""
      cat "$CONFIG_FILE"
    else
      echo "No config file found. Using defaults."
      echo ""
      echo "  projects_dir: ${BASE_DIR}/projects"
    fi
    ;;

  set)
    KEY="${2:?Usage: squad-config.sh set <key> <value>}"
    VALUE="${3:?Usage: squad-config.sh set <key> <value>}"

    # Validate key
    case "$KEY" in
      projects_dir)
        # Resolve to absolute path
        VALUE=$(cd "$VALUE" 2>/dev/null && pwd || echo "$VALUE")
        if [ ! -d "$VALUE" ]; then
          mkdir -p "$VALUE"
          echo "Created directory: $VALUE"
        fi
        ;;
      *)
        echo "ERROR: Unknown config key '$KEY'. Supported keys: projects_dir"
        exit 1
        ;;
    esac

    # Write config
    mkdir -p "$BASE_DIR"
    if [ -f "$CONFIG_FILE" ]; then
      # Update existing config
      python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
config['$KEY'] = '$VALUE'
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
    else
      # Create new config
      python3 -c "
import json
with open('$CONFIG_FILE', 'w') as f:
    json.dump({'$KEY': '$VALUE'}, f, indent=2)
"
    fi

    echo "Set $KEY = $VALUE"
    echo "New squads will use this setting. Existing squads are not affected."
    ;;

  *)
    echo "Usage: squad-config.sh show | set <key> <value>"
    exit 1
    ;;
esac
