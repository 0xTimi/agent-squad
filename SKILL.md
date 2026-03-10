---
name: agent-squad
version: 0.9.0
description: "Manage persistent AI coding squads that run in tmux sessions with task queues, progress reports, and automatic health monitoring. Use when the user wants to: (1) start/launch/create/restart a squad or team of AI agents, (2) assign/give tasks to a squad, (3) check squad status or ask what a squad is doing, (4) ping/nudge a squad to report progress, (5) stop a squad, (6) list all active squads, (7) configure squad settings like default project directory, (8) delete/archive a squad. Supports Claude Code, Codex, Gemini CLI, OpenCode, Kimi, Trae, Aider, and Goose as AI engines."
metadata:
  { "openclaw": { "requires": { "anyBins": ["tmux"], "bins": ["python3"] } } }
---

# Agent Squad

Run persistent AI development squads in tmux sessions. Each squad has a coordinator AI that picks up tasks, executes them, and reports progress — all while running unattended in the background.

## Prerequisites

- **tmux** must be installed (`brew install tmux` on macOS, `apt install tmux` on Linux)
- **python3** must be available (used for JSON handling)
- At least one AI engine CLI installed (claude, codex, gemini, opencode, etc.)
- AI engines run in **full-auto mode** (no permission prompts) since squads are unattended. This means the AI can read, write, and execute any code in the project directory without asking. **Only run squads on projects you trust.** See `references/engines.md` for details.

## Directory Layout

Squads store data separately from project code:

```
~/.openclaw/workspace/agent-squad/
├── squads/<name>/          ← Coordination (tasks, reports, logs)
├── projects/<name>/        ← Code output (default, configurable)
├── config.json             ← Global settings
└── .archive/               ← Archived (deleted) squads
```

## Operations

### 1. Start a Squad

When the user asks to start/create/launch/restart a squad, collect:
- **Squad name** (required): lowercase alphanumeric with hyphens. Cannot be a reserved name (engine names, operation verbs, etc.). Good names combine project + role, e.g.: myapp-backend, acme-billing, dario-team, sam-frontend
- **Engine** (required): which AI to use (claude, codex, gemini, opencode, kimi, trae, aider, goose)
- **Project directory** (optional): where the squad writes code. Defaults to `~/.openclaw/workspace/agent-squad/projects/<name>/`, or the path set in config.json. Use `--project <dir>` to specify a custom path.
- **Context** (optional): brief project background
- **Agent Teams mode** (optional, claude only): enables Claude Code Agent Teams for multi-agent coordination. The coordinator can spawn sub-agents to work in parallel. Add `--agent-teams` flag.

Then run:

```bash
bash scripts/squad-start.sh "<squad-name>" "<engine>" ["<optional-context>"] [--project <dir>] [--restart] [--agent-teams]
```

**Flags:**
- `--project <dir>`: project directory where the squad writes code.
- `--restart`: reuse an existing squad's data (tasks, reports). Required if the squad name was used before.
- `--agent-teams`: enable Claude Code Agent Teams mode (claude engine only).

If the squad name already exists (from a previous run), the script will error and ask the user to either:
- **Restart** the existing squad: add `--restart` flag
- **Choose a new name**: pick a different squad name

**Environment checks** (automatic):
- tmux and python3 must be installed
- The chosen AI engine binary must be in PATH
- Engine-specific checks: codex warns if project is not a git repo, gemini uses Google OAuth (run `gemini` once to login)
- openclaw is checked for watchdog cron registration (optional — squad works without it but won't auto-recover)

After success, respond with the squad name, engine, project directory, and coordination directory. Include how to assign tasks, check status, and stop.

### 2. Assign a Task

When the user wants to give a squad a task, collect:
- **Squad name**: which squad
- **Task title**: short name
- **Objective**: what to do (be specific)
- **Priority** (optional): critical, high, normal (default), low

Write the task file and notify the squad:

```bash
bash scripts/squad-assign.sh "<squad-name>" "<title>" "<objective>" "<priority>"
```

If the user's description is vague, ask for clarification. Good tasks have:
- Clear, specific objectives
- A defined scope
- Measurable acceptance criteria

### 3. Check Status

When the user asks about a squad's status, progress, or what it's doing:

```bash
bash scripts/squad-status.sh "<squad-name>"
```

Also read the latest report file in `~/.openclaw/workspace/agent-squad/squads/<squad-name>/reports/` for detailed progress. Look at the `## Current` section for real-time status.

Report the findings conversationally, e.g.:
- "my-squad is running on Claude Code. It has 1 task in progress: building the login module. Currently at ~60%, working on OAuth integration."
- "backend-team is stopped. It has 2 completed tasks and 1 pending."

### 4. Ping for Update

When the user wants a squad to update its report immediately:

```bash
bash scripts/squad-ping.sh "<squad-name>"
```

Tell the user: "I've asked <name> to update its report. Check back in a minute."

### 5. Stop a Squad

When the user wants to stop a squad:

```bash
bash scripts/squad-stop.sh "<squad-name>"
```

Reassure the user: all task files, reports, and logs are preserved. The squad can be restarted later with `--restart`.

### 6. Delete (Archive) a Squad

When the user wants to delete/remove a squad that is already stopped:

```bash
bash scripts/squad-delete.sh "<squad-name>"
```

This shows a summary first. To proceed:

```bash
bash scripts/squad-delete.sh "<squad-name>" --confirm
```

This moves the squad's coordination data to `.archive/` — nothing is permanently deleted. The project code directory is **never touched**.

### 7. Configure Settings

When the user wants to change the default project directory (e.g., "put all squad projects under ~/code", "change default project directory to ~/dev"):

```bash
bash scripts/squad-config.sh set projects_dir "<path>"
```

To view current settings:

```bash
bash scripts/squad-config.sh show
```

Config is stored at `~/.openclaw/workspace/agent-squad/config.json`.

### 8. List All Squads

When the user asks to see all squads, or asks "what squads do I have":

```bash
bash scripts/squad-list.sh
```

Present the output as a clean summary.

## Guardrails

- **Delete is archive**: `squad-delete.sh` moves data to `.archive/`, never permanently deletes. Project code is never touched.
- **Validate squad names**: lowercase alphanumeric + hyphens only.
- **One engine per squad**. Users who want multiple engines should create multiple squads.
- **Don't start duplicate squads**. Check if a tmux session already exists.
- **Don't modify** task or report files — that's the coordinator's job. Only write to `tasks/pending/` when assigning.
- If a squad is stopped and the user assigns a task, write the file anyway — it will be picked up on restart.

## Engine Reference

For supported engines and their configurations, see `references/engines.md`.

## Security

- Squads run AI engines in **full-auto mode** — this means the AI operates without any permission prompts and can freely read, write, delete files, and execute commands within the project directory. This is required for unattended background operation. Users should understand this grants the AI full autonomy over the project.
- **Keep sensitive files out**: credentials, API keys, `.env` files, and private keys should not be in project directories that squads work on.
- Coordination directory logs are gitignored by default.
- Each squad runs in its own isolated tmux session.
- The `--agent-teams` flag (Claude only) allows the coordinator to spawn additional AI sub-agents, increasing the scope of autonomous operations.
