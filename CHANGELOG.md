# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-03-31

### Added
- Experimental features integration (9 features across 3 phases)
- Permission cache with MD5 hash + 7-day TTL in `pre-tool-use.sh`
- Q-Learning agent performance tracking (α=0.1) in `consolidate.sh`
- Session cleanup & garbage collection (proposals 30d, candidates 90d)
- Custom status line for terminal (`status-line.sh`, 18ms execution)
- Multi-turn agent protocol (write_agent, CONTEXT-CARRY blocks)
- Extensions SDK scaffold with `@github/copilot-sdk` (preview)
- Background session persistence for ralph-loop and ultrawork
- Structured elicitation for prometheus/metis agents
- Compaction-safe 3-layer agent prompts (INVARIANTS/Core/LOW-PRIORITY)
- NLM (NotebookLM) researcher agent with Playwright stealth login
- Personal-advisor agent for user-specific agent recommendations
- Multimodal-looker agent for visual content analysis

### Changed
- Orchestrator models upgraded to `claude-opus-4.6-fast` (atlas, meta-orchestrator, sisyphus, ultrawork)
- proposals.json → SQLite primary storage (JSON kept as audit trail)
- consolidate.sh steps renumbered 1-6 (added GC + Q-Learning steps)
- Agent prompts restructured with compaction-safe markers

### Fixed
- Hash-based deduplication fallback chain (sha256sum → shasum → md5sum → length)
- README sync guard false positives in pre-tool-use hook

## [2.1.0] - 2026-03-XX

### Added
- Meta-orchestrator agent for parallel atlas dispatch (3 independent sessions)
- Session memory with contextual task prediction
- Atlas Heavy Mode — Planner-Generator-Evaluator pattern (metis → hephaestus → oracle)
- Momus agent for plan review (OKAY/REJECT with max 3 blocking issues)
- Metis agent for pre-planning analysis (intent classification, hidden intentions)
- Oracle agent for read-only consultation (hard debugging, architecture review)
- Commit trailer protocol (Constraint, Rejected, Directive, Confidence, Scope-risk)

### Changed
- Atlas upgraded from basic delegator to full orchestrator with web_search default
- Agent hierarchy formalized: meta-orchestrator → atlas → specialists → tools

## [2.0.0] - 2026-03-XX

### Changed
- **BREAKING**: Architecture migration from SKILL.md-only to agents/*.agent.md
- 14-agent system replaces legacy skills-only model
- Hook scripts rewritten with SQLite integration
- Plugin manifest (plugin.json) restructured with agents/skills/hooks separation

### Added
- 14 specialized agents: atlas, hephaestus, sisyphus, sisyphus-junior, prometheus, explore, librarian, oracle, metis, momus, ultrawork, nlm-researcher, multimodal-looker, personal-advisor
- BATS test suite (6 test files) with CI/CD pipeline
- init-memory.sh for SQLite schema bootstrap (7 tables)
- Danger pattern detection in pre-tool-use hook
- Proposal queue with content-hash deduplication

## [1.0.0] - 2026-02-XX

### Added
- Initial release: oh-my-opencode philosophy ported to Copilot CLI
- Skills-based architecture with SKILL.md format
- Basic session hooks (start/end)
- Core skills: atlas, explore, git-master, setup

[2.2.0]: https://github.com/Lee-SiHyeon/oh-my-copilot/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/Lee-SiHyeon/oh-my-copilot/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Lee-SiHyeon/oh-my-copilot/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/Lee-SiHyeon/oh-my-copilot/releases/tag/v1.0.0
