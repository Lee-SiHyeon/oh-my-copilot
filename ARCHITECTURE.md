# ARCHITECTURE.md — oh-my-copilot v2.2.0

> Production-grade agentic framework for GitHub Copilot CLI

## 1. Overview

oh-my-copilot extends GitHub Copilot CLI with a multi-agent orchestration layer.
It is a port of oh-my-opencode, adapted for Copilot CLI's hook-based plugin model.

**What it adds to vanilla Copilot CLI:**

- **15 specialized agents** organized in a three-layer delegation hierarchy
- **Lifecycle hooks** (`session-start`, `pre-tool-use`, `session-end`) for safety and intelligence
- **SQLite-backed memory** with priority-decay eviction and Q-Learning agent selection
- **23 skills** for backward compatibility and structured task workflows
- **Extensions SDK scaffold** (preview) for TypeScript-based hook development

**Core design principle — shared code vs. user-local state:**

| Layer | Path | Tracked? |
|-------|------|----------|
| Plugin code | `~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/` | Yes (git) |
| User state  | `~/.copilot/oh-my-copilot/` | No (runtime) |

---

## 2. Hook Lifecycle Flow

Copilot CLI invokes hooks at three session lifecycle points, plus one periodic
consolidation script. Timeouts are enforced by Copilot CLI itself (see `hooks.json`).

```
┌─────────────────────────────────────────────────────────────────┐
│                    COPILOT CLI SESSION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─ SESSION START ──────────────────────────────────────────┐   │
│  │  session-start.sh (176 lines, 15s timeout)               │   │
│  │  1. Dependency check (sqlite3)                           │   │
│  │  2. WSL detection + pwsh check                           │   │
│  │  3. DB bootstrap → init-memory.sh (schema + seeds)       │   │
│  │  4. Experimental mode advisory (one-time)                │   │
│  │  5. Background session recovery (ralph-loop state)       │   │
│  │  6. Log rotation (<1MB threshold)                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─ TOOL USE (per invocation) ──────────────────────────────┐   │
│  │  pre-tool-use.sh (309 lines, 5s timeout)                 │   │
│  │  1. JSON parse (jq → python3 fallback)                   │   │
│  │  2. Permission cache lookup (7-day TTL, MD5 hash)        │   │
│  │  3. Danger pattern detection:                            │   │
│  │     rm -rf, git push --force, DROP TABLE, format-volume  │   │
│  │     → Returns { permissionDecision: "ask" }              │   │
│  │  4. Agent policy check (opus model rejection → Sonnet)   │   │
│  │  5. README sync guard (warning, non-blocking)            │   │
│  │  6. meta_policy_rules lookup by domain                   │   │
│  │  7. Cache store after pass                               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─ SESSION END ────────────────────────────────────────────┐   │
│  │  session-end.sh (580 lines, 45s timeout)                 │   │
│  │  1. Git status parsing (normalize_status_path)           │   │
│  │  2. README sync guard (blocking for shared paths)        │   │
│  │  3. Proposal queue:                                      │   │
│  │     - SQLite proposals table (O(1) dedup via hash)       │   │
│  │     - JSON proposals.json (audit trail)                  │   │
│  │  4. Hash dedup: sha256sum → shasum → md5sum → length     │   │
│  │  5. improvement_candidates aging + cleanup               │   │
│  │  6. Agent usage logging for Q-Learning                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─ CONSOLIDATION (periodic) ───────────────────────────────┐   │
│  │  consolidate.sh (260 lines)                              │   │
│  │  Step 1: Refresh stale access timestamps (>1 day)        │   │
│  │  Step 2: Priority-decay eviction                         │   │
│  │          score = importance × access / (days_old + 1)    │   │
│  │          threshold: 0.01                                 │   │
│  │  Step 3: Ingest learnings (LEARNINGS.md, last 10 lines)  │   │
│  │  Step 4: Report top-3 memories by priority               │   │
│  │  Step 5: GC (candidates >90d, permission_cache expired)  │   │
│  │  Step 6: Q-Learning update (α=0.1, clamp [-1.0, 2.0])   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Agent Hierarchy

15 agents span three layers. The meta-orchestrator decomposes tasks but never
implements directly. Atlas instances run independent sessions. Specialists do
the actual work.

```
                          ┌─────────────────────┐
                          │  meta-orchestrator   │  Layer 0
                          │  (Opus 4.6 Fast)     │  Decomposes, never implements
                          └──────────┬──────────┘
                 ┌───────────────────┼───────────────────┐
                 ▼                   ▼                   ▼
          ┌──────────┐        ┌──────────┐        ┌──────────┐
          │ atlas-a  │        │ atlas-b  │        │ atlas-c  │  Layer 1
          │(Opus 4.6F│        │(Opus 4.6F│        │(Opus 4.6F│  Independent sessions
          └────┬─────┘        └────┬─────┘        └────┬─────┘
               │                   │                   │
    ┌──────────┼──────────┐        │         (same specialist pool)
    ▼          ▼          ▼        ▼
┌────────┐┌────────┐┌─────────┐┌──────────┐
│hephaes-││oracle  ││promethe-││ explore  │  Layer 2
│tus     ││(Opus)  ││us       ││(Haiku)   │  Specialists
│(Opus)  ││READ-   ││(Sonnet) ││          │
│        ││ONLY    ││         ││          │
└────────┘└────────┘└─────────┘└──────────┘
  Also: metis(Opus), momus(Opus), librarian(Sonnet),
        nlm-researcher(Sonnet), multimodal-looker(Sonnet),
        sisyphus-junior(Haiku), personal-advisor(Sonnet)
```

### Agent Models by Tier

| Tier | Model | Agents | Use Case |
|------|-------|--------|----------|
| Orchestrators | claude-opus-4.6-fast | atlas, meta-orchestrator, sisyphus, ultrawork | Coordination, delegation |
| Deep Thinkers | claude-opus-4.6 | hephaestus, oracle, metis, momus | Complex implementation, architecture |
| Standard | claude-sonnet-4.6 | prometheus, librarian, nlm-researcher, multimodal-looker, personal-advisor | Planning, research |
| Fast/Cheap | claude-haiku-4.5 | explore, sisyphus-junior | Quick search, simple tasks |

### Heavy Mode (Planner-Generator-Evaluator)

For complex tasks, three specialists form a closed-loop review cycle:

```
metis (Planner) → hephaestus (Generator) → oracle (Evaluator)
     │                    │                       │
     ▼                    ▼                       ▼
  Directives +     Implementation +        ACCEPT / REJECT
  Acceptance       Verification            (max 2 iterations)
  Criteria
```

---

## 3.1 Routing Decision Table

오케스트레이션 라우팅 결정 표: 작업 특성에 따른 최적 에이전트 선택

| 조건 | 라우팅 대상 | 이유 |
|------|------------|------|
| `task_count >= 3` AND `fully_independent == true` | **meta-orchestrator** (Parallel Mode) | 3개 이상의 완전 독립적 작업 → 병렬 세션 분할 |
| `task_count >= 3` AND `has_sequential_deps == true` | **meta-orchestrator** (Adaptive Mode) | 다단계 파이프라인 → 라운드 기반 적응형 할당 |
| `task_count == 1` AND `complexity == "high"` AND `ambiguity == "high"` AND `risk == "high"` | **atlas** (Heavy Mode: metis→hephaestus→oracle) | 복잡+모호+위험 → 3에이전트 폐쇄 루프 검증 |
| `task_count == 1` AND `complexity == "high"` AND (`ambiguity == "low"` OR `risk == "low"`) | **atlas** (Light Mode → hephaestus) | 단일 복잡 작업 → 전문가 직접 위임 |
| `task_count == 1` AND `complexity == "low"` | **sisyphus-junior** 또는 직접 전문가 | 단순 원자적 작업 → 빠른 처리 |
| `requires_persistence == true` AND `multi_step == true` | **sisyphus** | 체크리스트 기반 지속적 실행 |
| `requires_parallel_fleet == true` AND `NO_meta_orchestration_needed` | **ultrawork** | /fleet 중심 병렬 실행 엔진 |
| `task_count == 2` AND `independent == true` | **atlas** (/fleet 직접 사용) | 2작업 병렬은 meta 오버헤드 불필요 |
| `requires_codebase_search == true` | **explore** (Haiku) | 빠른 코드베이스 검색 |
| `requires_architecture_advice == true` | **oracle** (Opus) | 아키텍처 분석/디버깅 조언 |
| `requires_pre_planning == true` | **metis** (Opus) | 사전 계획 및 지시문 생성 |
| `requires_plan_review == true` | **momus** (Opus) | 계획 검토 및 평가 |
| `requires_library_research == true` | **librarian** (Sonnet) | 라이브러리 문서 조사 |
| `requires_thinking_brain == true` | **nlm-researcher** (Sonnet) | 아이디에이션, 전략, 종합 |
| `requires_web_search == true` (사용자 대면 답변 전) | **atlas** (`web_search` 기본 실행) | 팩트 체크 기본 동작 |

### 라우팅 우선순위 결정 트리

```
1단계: 작업 분해
   │
   ├─ 작업 수 >= 3?
   │   ├─ 예 → 독립성 검사
   │   │   ├─ 완전 독립 → meta-orchestrator (Parallel Mode)
   │   │   └─ 순차 의존 → meta-orchestrator (Adaptive Mode)
   │   │
   │   └─ 아니오 → 2단계
   │
2단계: 단일 작업 복잡도 평가
   │
   ├─ 복잡도 == "high"?
   │   ├─ 예 → 모호성/위험도 검사
   │   │   ├─ 모호 OR 위험 → atlas (Heavy Mode: metis→hephaestus→oracle)
   │   │   └─ 명확 AND 안전 → atlas (Light Mode → hephaestus)
   │   │
   │   └─ 아니오 → 3단계
   │
3단계: 특수 요구사항 검사
   │
   ├─ 지속성 필요? → sisyphus
   ├─ /fleet 병렬 필요? → ultrawork
   ├─ 코드베이스 검색? → explore
   ├─ 아키텍처 조언? → oracle
   ├─ 사전 계획? → metis
   ├─ 계획 검토? → momus
   ├─ 라이브러리 조사? → librarian
   ├─ 사고 브레인? → nlm-researcher
   │
   └─ 해당 없음 → 4단계
   │
4단계: 기본 라우팅
   │
   └─ 단순 작업 → sisyphus-junior 또는 직접 전문가 위임
```

### 비용 고려 사항

| 라우팅 | Opus 호출 수 | 사용 시기 |
|--------|--------------|----------|
| 1-Layer (atlas 직접) | 1-4 | 단일 작업 또는 순차 작업 |
| 2-Layer Parallel (meta + 3 atlas) | 4-5 | 3개 이상 독립 병렬 작업 |
| 2-Layer Adaptive (meta + N 라운드) | 라운드당 3-7 | 다단계 파이프라인 + 예측 |
| Heavy Mode (atlas 내부) | 3 (metis+hephaestus+oracle) | 복잡+모호+위험 작업 |

**규칙**: 병렬 또는 적응형 이득 > 라운드당 +1 Opus 비용일 때만 meta-orchestrator 호출.

---

## 4. Data Flow & Database Schema

### 7 SQLite Tables in `omc-memory.db`

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `semantic_memory` | Priority-scored fact storage | `fact_content`, `base_importance`, `access_count` |
| `meta_policy_rules` | Domain-based safety constraints | `task_domain`, `predicate_condition`, `action_constraint` |
| `agent_q_table` | Q-Learning agent selection | `task_signature`, `agent_id`, `q_value`, `trials` |
| `agent_usage_log` | Session execution tracking | `session_id`, `task_signature`, `agent_id`, `outcome`, `reward` |
| `improvement_candidates` | Git change tracking | `plugin_root`, `changed_paths`, `status_snapshot` |
| `permission_cache` | Allow/deny decisions (7d TTL) | `tool_name`, `pattern_hash`, `decision`, `expires_at` |
| `proposals` | Deduped improvement proposals | `content_hash` (UNIQUE), `type`, `status`, `priority` |

### Data Flow by Hook

```
session-start.sh → init-memory.sh → CREATE TABLE IF NOT EXISTS (7 tables)
                                   → INSERT seed data (5 policies, 7 Q-values)

pre-tool-use.sh → READ permission_cache → CACHE HIT? → allow/deny
                → READ meta_policy_rules → domain match? → enforce
                → WRITE permission_cache (on pass)

session-end.sh → READ git status → is_shared_path()? → WRITE proposals
              → WRITE improvement_candidates
              → WRITE agent_usage_log

consolidate.sh → READ/DELETE semantic_memory (decay eviction)
              → READ LEARNINGS.md → WRITE semantic_memory
              → DELETE old improvement_candidates (>90d)
              → DELETE expired permission_cache
              → READ agent_usage_log → UPDATE agent_q_table (α=0.1)
```

---

## 5. State Locations

```
Plugin Root (Shared Code — version-controlled)
~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/
├── agents/*.agent.md        # 15 agent definitions
├── skills/*/SKILL.md        # 23 skill definitions
├── scripts/*.sh, *.ps1      # Lifecycle hooks + utilities
├── extensions/              # SDK scaffold (preview)
├── tests/                   # BATS test suites
├── plugin.json              # Manifest (name, version, entry points)
├── hooks.json               # Hook registration (timeouts, paths)
└── README.md                # Documentation

User-Local State (Per-user — NOT version-controlled)
~/.copilot/oh-my-copilot/
├── omc-memory.db            # SQLite database (7 tables)
├── LEARNINGS.md             # Runtime-extracted learnings
├── proposals.json           # Audit trail (JSON mirror of proposals table)
├── .experimental-advised    # One-time flag: experimental mode shown
└── .proposals_migrated      # One-time flag: JSON→SQLite migration done
```

This separation lets multiple users share the same plugin install (e.g., via
symlink or git clone) while keeping runtime state isolated per user.

---

## 6. Experimental Features

oh-my-copilot gates advanced capabilities behind `/experimental on`:

| Feature | What It Enables |
|---------|----------------|
| `BACKGROUND_SESSIONS` | Persistent ralph-loop and ultrawork across sessions |
| `CHRONICLE` | Session memory with cross-session recall |
| `EXTENSIONS_SDK` | TypeScript hook scaffold with @github/copilot-sdk |
| `NLM_RESEARCHER` | NotebookLM integration with Playwright stealth login |
| `Q_LEARNING` | Agent performance tracking and adaptive selection |
| `MULTI_TURN_AGENTS` | write_agent protocol with CONTEXT-CARRY blocks |
| `STATUS_LINE` | Custom terminal status display (18ms execution) |
| `PERMISSION_CACHE` | 7-day TTL for tool permission decisions |
| `COMPACTION_SAFE` | 3-layer agent prompts with INVARIANTS markers |

These flags are checked at runtime; no feature code is loaded unless its gate
is enabled. This keeps the default experience stable.

---

## 7. Testing Architecture

All hooks are covered by BATS (Bash Automated Testing System) unit tests:

```
tests/
├── bats/                                    # BATS framework (submodule)
├── test_helper/                             # Shared fixtures and helpers
└── unit/
    ├── init_memory/
    │   └── test_schema_creation.bats        # init-memory.sh: schema bootstrap
    ├── pre_tool_use/
    │   ├── test_danger_patterns.bats        # Dangerous operation detection
    │   └── test_readme_sync.bats            # README sync guard (warning mode)
    ├── session_end/
    │   ├── test_is_shared_path.bats         # Path classification logic
    │   └── test_readme_sync.bats            # README sync guard (blocking mode)
    └── test_add_proposal.bats               # Proposal deduplication
```

### CI/CD Pipeline

Defined in `.github/workflows/tdd.yml`:

- **Platforms:** `ubuntu-latest`, `macos-latest`
- **Dependencies:** `sqlite3`, `jq`, `bats-core`, `bats-support`, `bats-assert`, `bats-file`
- **Execution:** `bats tests/unit/**/*.bats --timing --print-output-on-failure`
- **Trigger:** Push to `main`, pull requests targeting `main`
