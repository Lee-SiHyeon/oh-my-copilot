# local/ — Personal Customizations (gitignored)

This directory is gitignored. Put your personal omc customizations here.

## Structure
- `agents/` — Personal agent overrides. Files here override same-named agents in `agents/`
- `config.json` — Copy from `config.json.template` and customize
- Runtime memory is **not** stored here. Mutable session state now lives in `~/.copilot/oh-my-copilot/`.

## How to create personal agents
Run the helper in a platform-appropriate shell:
- Windows: `powershell -File scripts/new-personal-agent.ps1 <name>` (or just use Copilot normally)
- Unix-like: `pwsh -File scripts/new-personal-agent.ps1 <name>`
Or use the personal-advisor agent: `/agent oh-my-copilot:personal-advisor`

## Storage locations
- `~/.copilot/agents/` — Fully personal (machine-local, outside any git repo) ← RECOMMENDED
- `local/agents/` — Personal override within omc plugin (gitignored)
- `~/.copilot/oh-my-copilot/LEARNINGS.md` — Private evolving learnings written by session hooks
- `~/.copilot/oh-my-copilot/omc-memory.db` — Private SQLite memory DB / Q-table

Keep `local/` for overrides and templates only; keep evolving runtime state in `~/.copilot/oh-my-copilot/`.
