# oh-my-copilot 🚀

[![GitHub Release](https://img.shields.io/github/v/release/Lee-SiHyeon/oh-my-copilot)](https://github.com/Lee-SiHyeon/oh-my-copilot/releases)
[![GitHub Stars](https://img.shields.io/github/stars/Lee-SiHyeon/oh-my-copilot)](https://github.com/Lee-SiHyeon/oh-my-copilot/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)
[![CI](https://github.com/Lee-SiHyeon/oh-my-copilot/actions/workflows/tdd.yml/badge.svg)](https://github.com/Lee-SiHyeon/oh-my-copilot/actions)

[🇰🇷 한국어](../README.md) | 🇺🇸 **English**

> Production-grade multi-agent orchestration plugin for GitHub Copilot CLI

---

## ✨ Highlights

- **15 specialized agents** — each with a single responsibility, orchestrated by Meta-Orchestrator → Atlas → Specialists
- **Parallel execution** — dispatch multiple agents simultaneously with `/fleet`
- **Safety hooks** — dangerous commands (`rm -rf`, force push, `DROP TABLE`) are intercepted before they run
- **Human-gated self-evolution** — agents propose improvements; you decide what gets applied
- **NLM research brain** — deep synthesis and strategic thinking powered by NotebookLM integration

---

## 🚀 Quick Start

**1. Install**

```bash
copilot plugin install Lee-SiHyeon/oh-my-copilot
```

**2. Enable experimental features**

Restart Copilot CLI, then run:

```
/experimental on
```

**3. Start working**

```bash
copilot --agent oh-my-copilot:meta-orchestrator
```

Then describe your task — Meta-Orchestrator decomposes and delegates:

```
Build a full REST API auth system
```

---

## ⚡ Experimental Features

oh-my-copilot relies on Copilot CLI experimental features for full capability. Run `/experimental on` once, or launch with `copilot --experimental`.

| Feature | What it unlocks |
|---------|-----------------|
| `MULTI_TURN_AGENTS` | Agents keep context across delegation rounds |
| `SUBAGENT_COMPACTION` | Long-running tasks don't lose context mid-flight |
| `SESSION_STORE` | Cross-session memory and learning persistence |
| `ASK_USER_ELICITATION` | Structured interview forms (Prometheus, deep-interview) |
| `STATUS_LINE` | Real-time progress display in terminal |
| `BACKGROUND_SESSIONS` | Persistent ralph-loop and ultrawork workflows that survive restarts |
| `EXTENSIONS` | SDK scaffold available in `extensions/` — opt-in preview |

> 💡 Set specific flags: `export COPILOT_CLI_ENABLED_FEATURE_FLAGS="MULTI_TURN_AGENTS,SESSION_STORE"`

> ⚠️ Without experimental mode, core features like multi-turn delegation and session memory are unavailable. Agents fall back to limited single-turn mode.

---

## 🤖 Agent Team (15 agents)

| Agent | Role | Best For |
|-------|------|----------|
| **Meta-Orchestrator** 🌐 | Top-level Orchestrator | Task decomposition, parallel Atlas session management, session memory, adaptive reassignment |
| **Atlas** 🗺️ | Layer 1 Orchestrator | Delegates to specialists within a single task scope via `/fleet` and `@agent` |
| **Sisyphus** ⚙️ | Complex Multi-Task Orchestrator | Multi-step task decomposition and parallel execution |
| **Sisyphus-Junior** 🔩 | Focused Task Executor | Single atomic tasks, no delegation |
| **Hephaestus** 🔨 | Deep Implementation Specialist | Code implementation, refactoring, bug fixes |
| **Prometheus** 🔥 | Strategic Planner | Requirements interview, task breakdown, execution planning |
| **Oracle** 🔮 | Architecture Advisor (read-only) | Hard debugging, architecture review — advice only |
| **Metis** 🧠 | Pre-Planning Consultant | Identifies hidden intent, ambiguity, and risks |
| **Momus** 🎭 | Plan Reviewer | Reviews plans: outputs OKAY or REJECT + max 3 issues |
| **Explore** 🔍 | Codebase Explorer | Context-aware grep, file structure analysis |
| **Librarian** 📚 | Library Researcher | API documentation, package comparison, usage patterns |
| **NLM-Researcher** 🔬 | NotebookLM Research Agent | Deep research, synthesis, knowledge curation — Atlas's thinking brain |
| **Multimodal-Looker** 👁️ | Image & Document Analyzer | Screenshot analysis, PDF extraction, UI review |
| **Ultrawork** ⚡ | Full Orchestration Mode | Planning + parallel execution + verification in one command |
| **Personal-Advisor** 🧩 | Personalization Advisor | Analyzes session patterns → recommends custom agents |

### Invoking agents

Start with Meta-Orchestrator for complex multi-task work, or Atlas for focused single tasks. Call agents directly for targeted work:

```bash
copilot --agent oh-my-copilot:meta-orchestrator  # Top-level orchestrator (recommended)
copilot --agent oh-my-copilot:atlas              # Single-task orchestration
copilot --agent oh-my-copilot:hephaestus         # Direct implementation
copilot --agent oh-my-copilot:oracle             # Read-only consultation
copilot --agent oh-my-copilot:nlm-researcher     # Deep research & synthesis
copilot --agent oh-my-copilot:personal-advisor   # Personal agent recommendations
```

> 📡 Atlas runs at least one `web_search` before answering — preferring live results over stale training data.

> 🧠 For strategy and synthesis work, Atlas delegates to `@nlm-researcher` as its primary thinking engine.

---

## 🚢 Fleet Patterns & Heavy Mode

### Parallel execution with `/fleet`

Dispatch multiple agents at once to maximize throughput:

```
Run these 3 tasks in parallel:
  1. hephaestus: implement the auth module
  2. hephaestus: database schema migration
  3. prometheus: draft the API documentation plan
```

**Fleet execution flow:**

```
Atlas (orchestrates)
  ├── @hephaestus ──→ auth complete
  ├── @hephaestus ──→ DB migration complete   ← concurrent
  └── @prometheus ──→ API doc plan ready
        ↓
  @momus reviews → OKAY → @oracle final check
```

**Sequential pattern:** `@metis → @prometheus → @momus → @hephaestus → @oracle`

### Heavy Mode

Atlas automatically activates Heavy Mode for complex or exploratory tasks — running a parallel study group before implementation:

```
Atlas (Heavy Mode)
  ├── @explore (codebase search)    ← parallel
  ├── @oracle  (architecture analysis)
  └──→ merge results → @hephaestus or @sisyphus-junior (implement)
```

**Triggers:** multi-file refactoring, large bug hunts, new system design, complex debugging. When brain-work is needed, `@nlm-researcher` joins alongside `@oracle`.

---

## 🧩 Personalization

oh-my-copilot separates shared agents from your personal ones. You never pollute the shared `agents/` directory.

### Where personal agents live

| Location | Purpose |
|----------|---------|
| `~/.copilot/agents/` | **Recommended.** Fully private, machine-local, never pushed to git |
| `local/agents/` | Plugin-internal override zone. Gitignored |
| `agents/` | Plugin-owned, git-tracked. **Do not put personal agents here** |
| `~/.copilot/oh-my-copilot/` | Runtime memory: `omc-memory.db`, `LEARNINGS.md`, `proposals.json` |

### Using `personal-advisor`

The personal-advisor reads your session history, completed todos, agent usage, and MCP signals — then recommends 1–3 custom agents for your workflow.

```bash
copilot --agent oh-my-copilot:personal-advisor
```

**MCP signals drive personalization:**

- GitHub MCP → repository workflow specialist
- Browser/devtools MCP → web QA specialist
- Database MCP → SQL / data pipeline specialist

---

## ⚡ Quick Reference

| Command | Description |
|---------|-------------|
| `/meta-orchestrator` | Top-level orchestrator — task decomposition + parallel Atlas sessions |
| `/atlas` | Layer 1 orchestrator — single task scope |
| `/ultrawork` | Full autonomous workflow |
| `/ralph-loop` | Self-correcting loop until completion |
| `/prometheus` | Strategic planning with interview |
| `/explore` | Codebase search & analysis |
| `/oracle` | Read-only debugging consultation |
| `/hephaestus` | Deep implementation specialist |
| `/fleet` | Parallel agent execution |

---

## 💰 Model Cost Guide

Choose the right model per task to control costs:

| Tier | Model | Multiplier | Recommended Use |
|------|-------|------------|-----------------|
| 🥇 Default | `claude-sonnet-4.6` | 1x | Most implementation tasks |
| 🥈 Budget | `claude-haiku-4.5` | 0.33x | Simple atomic tasks, exploration |
| 🆓 Free | `gpt-5-mini` | 0x | Light tasks, cost-conscious |
| 🆓 Free | `gpt-4.1` | 0x | Free high-quality alternative |
| 🔁 Fallback | `gpt-5.4` | 1x | Auto-retry on Sonnet rate-limit (429) |
| 💡 Code | `gpt-5.3-codex` | 1x | Code generation focus |
| 💎 Premium | `claude-opus-*` | 3–30x | Selective use for high-complexity tasks — architecture, deep debugging, complex orchestration |

> 💡 **Recommended tier path:** `gpt-4.1` (free) for routine → `claude-sonnet-4.6` for standard work → `claude-opus-4.6` for high-complexity tasks (architecture, deep debugging, complex orchestration). Atlas auto-retries with `gpt-5.4` on Sonnet 429 errors.

---

## 🛡️ Safety Hooks

oh-my-copilot uses `hooks.json` lifecycle hooks to enforce safety at every stage.

### 1. Dangerous command interception (`preToolUse`)

The pre-execution hook scans every command before it runs:

| Category | Detected Patterns |
|----------|-------------------|
| **File deletion** | `rm -rf`, `rm -r -force`, `Remove-Item -Recurse -Force` |
| **Force push** | `git push --force`, `git push -f` |
| **DB destruction** | `DROP TABLE`, `DELETE FROM` |
| **System format** | `format` |

Dangerous patterns halt execution with `"permissionDecision": "ask"` — the user must explicitly confirm.

### 2. README sync enforcement

Change a core file (`agents/`, `scripts/`, `plugin.json`, `hooks.json`) without updating `README.md`? The `preToolUse` hook emits a non-blocking warning. But `sessionEnd` performs a final check — and **fails the session** if README is still out of sync. You must update docs before finishing.

### 3. Session logging (`sessionStart`)

Every session start writes a timestamped entry to `~/.copilot/session.log` with the working directory. Full audit trail of what ran where.

### 4. Session end validation (`sessionEnd`)

At session close, the hook:
- Re-checks README sync
- Records learning entries to `~/.copilot/oh-my-copilot/LEARNINGS.md`
- Queues improvement proposals to `~/.copilot/oh-my-copilot/proposals.json`

### 5. Proposal queue — human-gated self-evolution

Agents don't modify shared source directly. They write proposals to `~/.copilot/oh-my-copilot/proposals.json` with type, description, target file, priority, and SHA256 checksum for deduplication. Proposals are user-local (never pushed to git) and applied only when **you** review and approve them. The plugin learns; you stay in control.

---

## 🔄 Agent State Machine

Every agent task follows this lifecycle:

```
pending → in_progress → completed
                     ↘ failed (unrecoverable)
```

- **pending** — queued, awaiting claim | **in_progress** — claimed, executing | **completed** — verified results | **failed** — needs human intervention
- One task, one agent (hash-based dedup). No backward transitions. Atlas monitors and reassigns stalled tasks.

**Session lifecycle:** `sessionStart` loads context → Meta-Orchestrator decomposes request → Atlas coordinates specialists in dependency order → `sessionEnd` consolidates learnings and queues proposals.

---

## 📦 Project Structure

```
oh-my-copilot/
├── plugin.json                      # Metadata & agent registry
├── hooks.json                       # Safety hooks
├── LEARNINGS.md                     # Plugin-level learning log
├── agents/                          # v2.0 primary system
│   ├── atlas.agent.md               # Layer 1 orchestrator
│   ├── sisyphus.agent.md            # Multi-task orchestrator
│   ├── sisyphus-junior.agent.md     # Atomic task executor
│   ├── hephaestus.agent.md          # Implementation specialist
│   ├── prometheus.agent.md          # Strategic planner
│   ├── oracle.agent.md              # Architecture advisor (read-only)
│   ├── metis.agent.md               # Pre-planning consultant
│   ├── momus.agent.md               # Plan reviewer
│   ├── explore.agent.md             # Codebase explorer
│   ├── librarian.agent.md           # Library researcher
│   ├── nlm-researcher.agent.md      # NotebookLM research (primary brain)
│   ├── multimodal-looker.agent.md   # Image & document analyzer
│   ├── ultrawork.agent.md           # Full orchestration mode
│   └── personal-advisor.agent.md    # Personal agent advisor
├── scripts/                         # Automation scripts
├── local/                           # Gitignored personal overrides
│   └── agents/                      # User-only override agents
└── skills/                          # Legacy skills (backward compat)

~/.copilot/
├── session.log                      # Audit log
├── agents/                          # Private personal agents
└── oh-my-copilot/
    ├── omc-memory.db                # Per-user memory DB
    ├── LEARNINGS.md                 # Per-user learnings
    └── proposals.json               # Proposal queue
```

> For architectural details, see [ARCHITECTURE.md](../ARCHITECTURE.md).

---

## 📜 Credits

This project brings the multi-agent philosophy and prompt architecture of [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent) (by [@code-yeongyu](https://github.com/code-yeongyu)) to the GitHub Copilot CLI agent format.

The core principle carries forward: *"Each agent owns a single responsibility. The orchestrator coordinates the whole."*

---

## 📄 License

MIT © [Lee SiHyeon](https://github.com/Lee-SiHyeon)
