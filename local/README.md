# local/ — Personal Customizations (gitignored)

This directory is gitignored. Put your personal omc customizations here.

## Structure
- `agents/` — Personal agent overrides. Files here override same-named agents in `agents/`
- `config.json` — Copy from `config.json.template` and customize

## How to create personal agents
Run: `scripts\new-personal-agent.ps1 <name>`
Or use the personal-advisor agent: `/agent oh-my-copilot:personal-advisor`

## Storage locations
- `~/.copilot/agents/` — Fully personal (machine-local, outside any git repo) ← RECOMMENDED
- `local/agents/` — Personal override within omc plugin (gitignored)
