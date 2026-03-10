---
name: agent-squad
version: 0.9.2
license: MIT-0
description: "Manage persistent AI coding squads that run in tmux sessions with task queues, progress reports, and automatic health monitoring. Use when the user wants to: (1) start/launch/create/restart a squad or team of AI agents, (2) assign/give tasks to a squad, (3) check squad status or ask what a squad is doing, (4) ping/nudge a squad to report progress, (5) stop a squad, (6) list all active squads, (7) configure squad settings like default project directory, (8) delete/archive a squad. Supports Claude Code, Codex, Gemini CLI, OpenCode, Kimi, Trae, Aider, and Goose as AI engines."
metadata:
  { "openclaw": { "requires": { "anyBins": ["tmux"], "bins": ["python3"] } } }
---

# Agent Squad

GitHub: https://github.com/0xTimi/agent-squad

Run persistent AI coding squads in tmux. Squads pick up tasks, write code, and report progress — 24/7 in the background.

## Slash Command Usage

Users can invoke `/agent-squad` directly with optional arguments:

| Command | Action |
|---|---|
| `/agent-squad` | Show squad dashboard (or Getting Started if none exist) |
| `/agent-squad list` | List all squads |
| `/agent-squad start backend claude` | Start a squad |
| `/agent-squad status backend` | Check a squad's status |
| `/agent-squad stop backend` | Stop a squad |
| `/agent-squad assign backend "做登录"` | Assign a task |
| `/agent-squad ping backend` | Nudge a squad to report |
| `/agent-squad delete backend` | Archive a squad |

No arguments or `list` → run `bash {baseDir}/scripts/squad-list.sh`:
- **If squads exist**: show a clean status dashboard
- **If no squads**: show the Getting Started intro below

## Getting Started

When users ask "what is this", "怎么用", "how do I use this", or invoke `/agent-squad` with no squads, give a friendly intro with examples. Match user's language.

Chinese:

> Agent Squad 可以帮你在后台跑 AI 编程团队，7×24 小时自动写代码。你直接跟我说就行，比如：
>
> - "用 claude 起一个叫 backend 的 squad，项目在 ~/projects/api"
> - "给 backend 一个任务：实现用户登录"
> - "backend 进度怎么样了？"
> - "停掉 backend"
> - "我有哪些 squad 在跑？"
>
> 支持的引擎：Claude Code、Codex、Gemini CLI、OpenCode、Kimi、Trae、Aider、Goose
>
> 要不要现在就起一个试试？

English:

> Agent Squad runs AI coding agents in the background 24/7. Just tell me what you need:
>
> - "Start a squad called backend using claude for ~/projects/api"
> - "Give backend a task: implement user login"
> - "How's backend doing?"
> - "Stop backend"
> - "What squads do I have?"
>
> Engines: Claude Code, Codex, Gemini CLI, OpenCode, Kimi, Trae, Aider, Goose
>
> Want to start one now?

## What Users Can Do

Users just talk. Here's what they might say and how to respond:

### Start a squad

User: "用 codex 起一个叫 backend 的 squad" / "start a squad called api with claude for ~/projects/api"

Ask if missing: squad name, engine. Project dir and context are optional.

First-time users: briefly mention squads run in full-auto mode, AI has full access to the project directory.

Response: "Squad 'backend' 已经跑起来了，用的是 Codex！随时可以给它派任务。"

### Assign a task

User: "给 backend 一个任务：做用户登录" / "let backend work on JWT auth"

If only one squad exists, use it automatically. If the request is vague, ask for specifics.

Response: "任务已派！backend 马上会开始做 'User Login'。"

### Check status

User: "backend 在干嘛？" / "进度如何" / "how's my squad doing?"

Response: "backend 正在用 Claude Code 跑，当前在做 'User Login'——正在写表单校验，大概 60%。已完成 2 个任务，1 个进行中。"

### Ping for update

User: "催一下 backend" / "let it report progress"

Response: "已经催了 backend 更新进度，稍等一两分钟再看。"

### Stop a squad

User: "停掉 backend" / "stop the squad"

Always confirm before stopping.

Response: "backend 已停止。所有工作都保存了，随时可以重启。"

### List squads

User: "我有哪些 squad？" / "list my squads"

Response: present a clean readable summary of all squads.

### Delete a squad

User: "删掉 backend" / "archive the old squad"

Always ask for confirmation first. Reassure: data is archived, project code never touched.

### Configure

User: "把默认项目目录改成 ~/code" / "show squad settings"

---

## Script Reference

All scripts at `{baseDir}/scripts/`. Execute scripts based on user intent above and present results conversationally.

### squad-start.sh

```bash
bash {baseDir}/scripts/squad-start.sh "<name>" "<engine>" "<context>" [--project <dir>] [--restart] [--agent-teams] [--no-watchdog]
```

Parameters:
- name: lowercase alphanumeric + hyphens
- engine: claude, codex, gemini, opencode, kimi, trae, aider, goose
- context: optional project background
- `--project <dir>`: custom code output directory
- `--restart`: required if squad name already exists
- `--agent-teams`: claude only, multi-agent mode
- `--no-watchdog`: skip auto-restart cron

### squad-assign.sh

```bash
bash {baseDir}/scripts/squad-assign.sh "<name>" "<title>" "<objective>" "<priority>"
```

Priority: critical / high / normal (default) / low

### squad-status.sh

```bash
bash {baseDir}/scripts/squad-status.sh "<name>"
```

Also read latest report in `~/.openclaw/workspace/agent-squad/squads/<name>/reports/` — check `## Current` section for real-time progress.

### squad-ping.sh

```bash
bash {baseDir}/scripts/squad-ping.sh "<name>"
```

### squad-stop.sh

```bash
bash {baseDir}/scripts/squad-stop.sh "<name>"
```

### squad-list.sh

```bash
bash {baseDir}/scripts/squad-list.sh
```

### squad-delete.sh

```bash
bash {baseDir}/scripts/squad-delete.sh "<name>"          # show summary
bash {baseDir}/scripts/squad-delete.sh "<name>" --confirm # confirm delete
```

### squad-config.sh

```bash
bash {baseDir}/scripts/squad-config.sh show
bash {baseDir}/scripts/squad-config.sh set projects_dir "<path>"
```

## Guidelines

- If only one squad exists, use it automatically
- One engine per squad — suggest multiple squads for multiple engines
- Don't modify task/report files directly — only via assign script
- If squad is stopped and user assigns a task, write it anyway — picked up on restart
- Squads auto-init git repos; for existing projects suggest a separate branch
- Watchdog auto-restarts crashed squads by default

## Engine Reference

Details: `{baseDir}/references/engines.md`
