# oh-my-copilot Extensions SDK Integration

> 🚧 **SCAFFOLD / PREVIEW** — Shell hooks remain primary.
> This directory contains an opt-in scaffold for the Copilot CLI Extensions SDK.
> No functionality has migrated from shell hooks yet.

## What Is This?

Copilot CLI supports **typed, compiled extensions** via the [`@github/copilot-sdk`](https://www.npmjs.com/package/@github/copilot-sdk) package.
Extensions communicate with the CLI over JSON-RPC (stdio), providing:

- **Lifecycle hooks** — `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, etc.
- **Custom tools** — register tools that Copilot agents can invoke directly
- **Native event handling** — typed events instead of shell script parsing

### How It Relates to oh-my-copilot

Currently, all hooks run as **shell scripts** (see `scripts/` and `hooks.json`):

| Shell Hook | Purpose |
|------------|---------|
| `scripts/session-start.sh` | Bootstrap memory DB, load Q-table, inject context |
| `scripts/pre-tool-use.sh` | Permission cache, danger pattern detection |
| `scripts/session-end.sh` | Usage tracking, Q-Learning update, consolidation |

This extensions scaffold provides a **typed alternative** that will eventually
replace the shell hooks incrementally — once the SDK stabilizes.

## Prerequisites

- **`/experimental on`** — required for extensions support
- **Copilot CLI v1.0.14+** — minimum version with extensions support
- **Node.js 20+** — required by `@github/copilot-sdk`

## Extension Placement

Copilot CLI discovers extensions from `~/.copilot/extensions/`.
Create a symlink from the discovery path to this plugin's extension directory:

```bash
ln -sfn ~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/extensions/oh-my-copilot \
        ~/.copilot/extensions/oh-my-copilot
```

## Migration Roadmap

| Priority | Shell Hook | Extension Hook | Status |
|----------|-----------|----------------|--------|
| 1 | session-start.sh | `sessionStart` | Scaffold |
| 2 | pre-tool-use.sh | `preToolUse` | Scaffold |
| 3 | session-end.sh | `sessionEnd` | Scaffold |
| 4 | — | Custom tools (agent stats, Q-table) | Planned |

## Development Workflow

```bash
cd extensions/oh-my-copilot
npm install        # Install @github/copilot-sdk + TypeScript
npm run build      # Compile src/index.ts → dist/extension.mjs
npm run dev        # Watch mode for development
```

### Entry Point Convention

Copilot CLI expects **`extension.mjs`** as the compiled entry point in the
extension directory. The TypeScript build produces `dist/extension.mjs`
(configured in `package.json` → `"main": "dist/extension.mjs"`).

### Hot Reload

After building, run `/clear` in Copilot CLI (or use `extensions_reload`)
to reload extensions — no CLI restart needed.

## File Structure

```
extensions/
├── README.md                          ← This file
└── oh-my-copilot/
    ├── package.json                   ← Dependencies & build scripts
    ├── tsconfig.json                  ← TypeScript configuration
    └── src/
        └── index.ts                   ← Extension scaffold (entry point source)
```
