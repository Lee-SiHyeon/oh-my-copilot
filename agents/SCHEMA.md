# Agent Frontmatter Schema

Standard schema for oh-my-copilot agent definition files (`*.agent.md`).

## Schema Definition

```yaml
---
name: string          # Required. kebab-case, must match filename
description: string   # Required. One-line description (quoted)
model: string         # Required. Copilot CLI model identifier (quoted)
tools: list           # Optional. Tool access level. Default: ["*"]
version: string       # Optional. SemVer. Default: "1.0.0"
tags: list            # Optional. Category tags from taxonomy below
---
```

## Field Details

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | ✅ | string | kebab-case, must match filename without `.agent.md` |
| `description` | ✅ | string | Double-quoted, one-line, describes purpose and usage |
| `model` | ✅ | string | Double-quoted Copilot CLI model ID |
| `tools` | ❌ | list | JSON-style inline list of tool access permissions |
| `version` | ❌ | string | SemVer string, e.g. `"1.0.0"` |
| `tags` | ❌ | list | JSON-style inline list from tags taxonomy |

## Tags Taxonomy

| Category | Description | Agents |
|----------|-------------|--------|
| `orchestrator` | Coordinates agents, delegates work | atlas, meta-orchestrator, sisyphus, ultrawork |
| `specialist` | Deep expertise in a specific domain | hephaestus, explore, librarian, nlm-researcher |
| `advisory` | Read-only analysis, planning, review | metis, momus, prometheus, oracle |
| `utility` | Lightweight helpers and executors | multimodal-looker, sisyphus-junior, personal-advisor |

**Topic tags**: `delegation`, `parallel`, `persistent`, `fullstack`, `implementation`, `search`, `research`, `analysis`, `review`, `planning`, `debugging`, `readonly`, `visual`, `executor`, `personalization`

## Tool Access Levels

| Level | Value | Use Case | Agents |
|-------|-------|----------|--------|
| Full access | `["*"]` | Orchestrators, implementors | atlas, meta-orchestrator, ultrawork, hephaestus, personal-advisor, sisyphus-junior |
| Read + Execute | `["read", "search", "execute"]` | Command runners | sisyphus, nlm-researcher |
| Read-only | `["read", "search"]` | Advisory/analysis | oracle, metis, momus, explore, librarian, prometheus |
| Minimal | `["read"]` | Passive analysis | multimodal-looker |

## Example

```yaml
---
name: explore
description: "Contextual grep for codebases. Answers 'Where is X?', 'Which file has Y?'."
model: "Claude Haiku 4.5"
tools: ["read", "search"]
version: "1.0.0"
tags: ["specialist", "search"]
---
```

## Validation Rules

1. All required fields (`name`, `description`, `model`) must be present
2. `name` must match filename (e.g., `atlas.agent.md` → `name: atlas`)
3. `description` and `model` must be double-quoted
4. `tools` and `tags` use JSON-style inline list format, not YAML list format
5. No blank lines within the frontmatter block
6. Frontmatter must start at line 1 with `---`
