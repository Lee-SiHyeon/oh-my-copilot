/**
 * oh-my-copilot Extension Scaffold
 *
 * Status: 🚧 PREVIEW — Shell hooks remain primary
 * Enable: /experimental on (requires Copilot CLI v1.0.14+)
 *
 * This extension provides a typed, compiled alternative to the shell-based
 * hooks in scripts/. When the Extensions SDK stabilizes, hooks will migrate
 * here incrementally (shell hooks → extension hooks).
 *
 * Entry point convention: Copilot CLI expects `extension.mjs` in the
 * extension directory. The TypeScript build compiles to dist/extension.mjs.
 *
 * Migration priority:
 *   1. sessionStart  → scripts/session-start.sh equivalent
 *   2. preToolUse    → scripts/pre-tool-use.sh equivalent
 *   3. sessionEnd    → scripts/session-end.sh equivalent
 *   4. Custom tools  → agent workspace queries, Q-table stats
 *
 * @see https://github.com/github/copilot-sdk
 * @see https://docs.github.com/en/copilot/how-tos/copilot-sdk/sdk-getting-started
 */

// ─────────────────────────────────────────────────────────
// SDK Import — uncomment when @github/copilot-sdk is installed
// ─────────────────────────────────────────────────────────
// import { CopilotClient } from '@github/copilot-sdk';

// ─────────────────────────────────────────────────────────
// Extension Scaffold
// ─────────────────────────────────────────────────────────
// When the Extensions SDK stabilizes, this file will implement:
//
// 1. SESSION START HOOK
//    Equivalent to scripts/session-start.sh
//    - Bootstrap SQLite memory DB (~/.copilot/omc/memory.db)
//    - Load Q-table for agent selection optimization
//    - Check experimental feature flags
//    - Inject project memory and notepad context
//
// 2. PRE-TOOL-USE HOOK
//    Equivalent to scripts/pre-tool-use.sh
//    - Permission cache check (allow/deny decisions)
//    - Danger pattern detection (rm -rf, force push, etc.)
//    - Return { permissionDecision: 'allow' | 'deny', reason: string }
//    - Agent-specific tool restrictions
//
// 3. SESSION END HOOK
//    Equivalent to scripts/session-end.sh
//    - Agent usage tracking and duration logging
//    - Q-Learning reward signal update
//    - Improvement proposal queue migration
//    - Consolidation trigger check
//
// 4. CUSTOM TOOLS
//    New capabilities not possible with shell hooks:
//    - omc_agent_stats: Query Q-table and usage statistics
//    - omc_memory_search: Semantic search across project memory
//    - omc_session_timeline: Trace agent flow for current session
//
// ─────────────────────────────────────────────────────────
// Example implementation pattern (for reference):
// ─────────────────────────────────────────────────────────
//
// async function joinAndRegister() {
//   const client = new CopilotClient();
//   await client.start();
//
//   const session = await client.joinSession({
//     hooks: {
//       sessionStart: async (event) => {
//         // Bootstrap memory DB, load Q-table
//         console.log('[omc-ext] Session started');
//       },
//
//       preToolUse: async (event) => {
//         const { tool, args } = event;
//         // Permission check — equivalent to pre-tool-use.sh
//         // Return permissionDecision to allow/deny
//         return { permissionDecision: 'allow' };
//       },
//
//       sessionEnd: async (event) => {
//         // Agent usage tracking, Q-Learning update
//         console.log('[omc-ext] Session ended');
//       },
//     },
//
//     tools: [
//       {
//         name: 'omc_agent_stats',
//         description: 'Query oh-my-copilot agent Q-table and usage statistics',
//         parameters: {
//           type: 'object',
//           properties: {
//             agent: { type: 'string', description: 'Agent name (e.g., atlas, hephaestus)' },
//           },
//         },
//         handler: async ({ agent }) => {
//           // Query SQLite Q-table: ~/.copilot/omc/memory.db
//           return { agent, status: 'scaffold — not yet implemented' };
//         },
//       },
//     ],
//   });
// }
//
// joinAndRegister().catch(console.error);
// ─────────────────────────────────────────────────────────

console.log('[oh-my-copilot] Extension scaffold loaded — shell hooks remain primary');
export {};
