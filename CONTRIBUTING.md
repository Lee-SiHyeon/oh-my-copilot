# Contributing to oh-my-copilot

Thank you for your interest in contributing to **oh-my-copilot**! 🎉
This document explains how to get started, add new agents/skills/hooks, run tests, and submit changes.

> Please also follow our [Code of Conduct](#code-of-conduct) in all interactions.

---

## Code of Conduct

- **Be constructive** — focus on the idea, not the person.
- **Be inclusive** — welcome newcomers and explain context.
- **Be respectful** — disagree politely; assume good intent.
- **Give credit** — acknowledge contributions from humans and AI alike.

Violations may result in comments being hidden or contributors being blocked at the maintainer's discretion.

---

## Getting Started

1. **Fork & clone** the repository:

   ```bash
   git clone https://github.com/<YourUsername>/oh-my-copilot.git
   ```

2. **Install** into the Copilot CLI `_direct/` path for local testing:

   ```bash
   # Symlink (recommended) or copy
   ln -s "$(pwd)/oh-my-copilot" \
     "$HOME/.copilot/installed-plugins/_direct/<YourUsername>--oh-my-copilot"
   ```

3. **Enable experimental features** in Copilot CLI:

   ```
   /experimental on
   ```

4. Verify hooks load correctly — you should see the session-start banner when a new Copilot session begins.

---

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| GitHub Copilot CLI | 1.0.14+ | Plugin host |
| bash | 5.0+ | Hook scripts |
| sqlite3 | 3.x | Session memory & proposals |
| jq | 1.6+ | JSON processing in hooks |
| git | 2.x | Version control |
| bats-core | 1.x | Unit testing |

---

## Project Structure

```
oh-my-copilot/
├── agents/           # 15 .agent.md files — the core agent system
├── skills/           # 25 skill directories (legacy SKILL.md format)
├── scripts/          # Lifecycle hooks (Bash + PowerShell)
├── extensions/       # TypeScript SDK scaffold (preview)
├── tests/unit/       # BATS unit tests
├── local/            # User-local override patterns (gitignored)
├── plugin.json       # Plugin manifest
├── hooks.json        # Lifecycle hook registry (3 hooks)
├── README.md         # Bilingual documentation (한국어 primary)
├── SKILL.md          # Skill index
└── LICENSE           # MIT
```

---

## How to Add an Agent

1. Create a new file: `agents/<agent-name>.agent.md`
   - Use **kebab-case** for the filename (e.g., `my-analyzer.agent.md`).

2. Start with the required YAML frontmatter:

   ```yaml
   ---
   name: agent-name
   description: One-line description of what this agent does
   model: claude-sonnet-4.6
   tools: ["read", "edit", "search", "execute"]
   ---
   ```

3. **Model selection guide**:
   - `claude-haiku-4.5` — Fast, low-cost tasks (status checks, simple lookups)
   - `claude-sonnet-4.6` — Standard work (coding, analysis, most agents)
   - `claude-opus-4.6` / `claude-opus-4.6-fast` — Complex orchestration, deep reasoning

4. Write the agent prompt body below the frontmatter. Follow the **3-layer compaction-safe pattern**:
   - `## INVARIANTS` — Rules that must survive context compaction
   - `## Core Identity` — Main instructions and behavior
   - `<!-- LOW-PRIORITY -->` — Examples and optional details (may be trimmed)

5. Update `README.md` to include the new agent in the agent table.

---

## How to Add a Skill

> **Note**: Skills use the legacy `SKILL.md` format. New functionality should prefer agents when possible.

1. Create a directory: `skills/<skill-name>/`

2. Add a `SKILL.md` file with YAML frontmatter:

   ```markdown
   ---
   name: skill-name
   description: What it does
   location: project
   ---
   Trigger: "keyword1", "keyword2"

   Instructions for the skill...
   ```

3. The `location` field is typically `project` (applies to project context).

4. Add descriptive trigger keywords so the skill activates at the right time.

---

## How to Add a Hook Script

Hooks execute at specific lifecycle points. Each hook must have **both** Bash and PowerShell implementations.

1. **Create the scripts**:
   - `scripts/<hookname>.sh` — Bash implementation
   - `scripts/<hookname>.ps1` — PowerShell implementation

2. **I/O contract**: Hooks receive JSON on **stdin** and must output JSON on **stdout**.
   - Any non-JSON output (logs, debug) should go to **stderr**.

3. **Register** the hook in `hooks.json`:

   ```json
   {
     "type": "command",
     "bash": "bash \"$d/scripts/<hookname>.sh\"",
     "powershell": "& (Join-Path $HOME '.copilot\\installed-plugins\\oh-my-copilot\\scripts\\<hookname>.ps1')",
     "timeoutSec": 10
   }
   ```

4. Supported hook types: `sessionStart`, `sessionEnd`, `preToolUse`.

5. Keep execution time within the `timeoutSec` budget — `preToolUse` has only **5 seconds**.

---

## Testing

We use [bats-core](https://github.com/bats-core/bats-core) for unit tests.

### Run all tests

```bash
bats tests/unit/**/*.bats --timing --print-output-on-failure
```

### Existing test files

| File | What it tests |
|------|---------------|
| `test_schema_creation.bats` | SQLite schema bootstrap (`init-memory.sh`) |
| `test_is_shared_path.bats` | Shared-path detection logic |
| `test_readme_sync.bats` | README sync guard in pre-tool-use hook |
| `test_danger_patterns.bats` | Danger pattern matching (destructive commands) |
| `test_add_proposal.bats` | Proposal queue insertion & deduplication |

### Adding a new test

1. Create `tests/unit/test_<feature>.bats`.
2. Use `bats-support` and `bats-assert` helpers (installed by CI).
3. Keep tests fast — mock external dependencies where possible.

### CI/CD

Tests run automatically via GitHub Actions (`.github/workflows/tdd.yml`) on every push and PR:
- **Platforms**: `ubuntu-latest`, `macos-latest`
- **Dependencies installed by CI**: `sqlite3`, `jq`, `bats-core`, `bats-support`, `bats-assert`

All tests must pass before a PR can be merged.

---

## Commit Convention

Use conventional commit prefixes:

| Prefix | Usage |
|--------|-------|
| `feat:` | New feature or agent |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `test:` | Adding or updating tests |
| `refactor:` | Code restructuring (no behavior change) |
| `chore:` | Maintenance, CI, dependencies |

### AI Co-authorship

If AI assisted your work, add the appropriate trailer:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Pull Request Process

1. **Branch** from `main` — use a descriptive branch name (e.g., `feat/add-reviewer-agent`).
2. **Keep changes focused** — one feature or fix per PR.
3. **Tests must pass** — CI will run automatically on ubuntu and macOS.
4. **Update documentation** — if you change agents, skills, or hooks, update `README.md` accordingly.
5. **Describe your changes** — explain *what* changed and *why* in the PR description.
6. A maintainer will review and may request changes before merging.

---

## Questions?

- **Bug reports & feature requests**: [Open an issue](https://github.com/Lee-SiHyeon/oh-my-copilot/issues)
- **General discussion**: [Start a discussion](https://github.com/Lee-SiHyeon/oh-my-copilot/discussions)

Thank you for helping make oh-my-copilot better! 🛠️
