---
name: agent-squad
description: "Manage persistent AI coding squads that run in tmux sessions with task queues, progress reports, and automatic health monitoring. Use when the user wants to: (1) start/launch/create a squad or team of AI agents, (2) assign/give tasks to a squad, (3) check squad status or ask what a squad is doing, (4) ping/nudge a squad to report progress, (5) stop a squad, (6) list all active squads. Supports Claude Code, Codex, Gemini CLI, OpenCode, Kimi, Trae, Aider, and Goose as AI engines."
metadata:
  { "openclaw": { "requires": { "anyBins": ["tmux"] } } }
---

# Agent Squad

Run persistent AI development squads in tmux sessions. Each squad has a coordinator AI that picks up tasks, executes them, and reports progress — all while running unattended in the background.

## Prerequisites

- **tmux** must be installed (`brew install tmux` on macOS, `apt install tmux` on Linux)
- At least one AI engine CLI installed (claude, codex, gemini, opencode, etc.)
- AI engines run in **full-auto mode** (no permission prompts) since squads are unattended. See `references/engines.md` for details.

## Operations

### 1. Start a Squad

When the user asks to start/create/launch a squad, collect:
- **Squad name** (required): lowercase alphanumeric with hyphens
- **Engine** (required): which AI to use (claude, codex, gemini, opencode, kimi, trae, aider, goose)
- **Context** (optional): brief project background

Then run:

```bash
bash scripts/squad-start.sh "<squad-name>" "<engine>" "<optional-context>"
```

After success, respond with:

```
Squad "<name>" started (<engine>).

Coordination directory: ~/.openclaw/workspace/squads/<name>/
Live view: tmux attach -t squad-<name>  (Ctrl+B D to detach)

You can now:
- Assign tasks: "Give <name> a task: <describe what to do>"
- Check status: "What is <name> doing?" or "Is <name> working?"
- Ping for update: "Ask <name> to report"
- Stop: "Stop <name>"
```

### 2. Assign a Task

When the user wants to give a squad a task, collect:
- **Squad name**: which squad
- **Task title**: short name
- **Objective**: what to do (be specific)
- **Target path** (optional): project directory
- **Priority** (optional): critical, high, normal (default), low

Write the task file and notify the squad:

```bash
bash scripts/squad-assign.sh "<squad-name>" "<title>" "<objective>" "<target-path>" "<priority>"
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

Also read the latest report file in `~/.openclaw/workspace/squads/<squad-name>/reports/` for detailed progress. Look at the `## Current` section for real-time status.

Report the findings conversationally, e.g.:
- "xiaopang is running on Claude Code. It has 1 task in progress: building the login module. Currently at ~60%, working on OAuth integration."
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

Reassure the user: all task files, reports, and logs are preserved. The squad can be restarted later.

### 6. List All Squads

When the user asks to see all squads, or asks "what squads do I have":

```bash
bash scripts/squad-list.sh
```

Present the output as a clean summary.

## Guardrails

- **Never delete** squad data. Stop preserves everything.
- **Validate squad names**: lowercase alphanumeric + hyphens only.
- **One engine per squad**. Users who want multiple engines should create multiple squads.
- **Don't start duplicate squads**. Check if a tmux session already exists.
- **Don't modify** task or report files — that's the coordinator's job. Only write to `tasks/pending/` when assigning.
- If a squad is stopped and the user assigns a task, write the file anyway — it will be picked up on restart.

## Engine Reference

For supported engines and their configurations, see `references/engines.md`.

## Security

- Squads run AI engines in full-auto mode (e.g., `claude --dangerously-skip-permissions`). This is required for unattended operation.
- Warn users to keep sensitive files (credentials, API keys, .env) out of project directories that squads work on.
- Coordination directory logs are gitignored by default.
- Each squad runs in its own isolated tmux session.
