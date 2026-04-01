# oh-my-copilot 🚀

> oh-my-opencode를 GitHub Copilot CLI에 포팅한 프로덕션급 멀티에이전트 오케스트레이션 플러그인

[![GitHub Release](https://img.shields.io/github/v/release/Lee-SiHyeon/oh-my-copilot)](https://github.com/Lee-SiHyeon/oh-my-copilot/releases)
[![GitHub Stars](https://img.shields.io/github/stars/Lee-SiHyeon/oh-my-copilot)](https://github.com/Lee-SiHyeon/oh-my-copilot/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/Lee-SiHyeon/oh-my-copilot/actions/workflows/tdd.yml/badge.svg)](https://github.com/Lee-SiHyeon/oh-my-copilot/actions)

🇰🇷 **한국어** | [🇺🇸 English](docs/README.en.md)

## ✨ 하이라이트

- 🌐 **최상위 오케스트레이터 (Meta-Orchestrator)** — 작업 분해, 병렬 Atlas 세션 관리, 적응적 재배정
- 🗺️ **Layer 1 실행기 (Atlas)** — 단일 작업 내 15개 전문 에이전트에 위임·조율
- ⚡ **Fleet 병렬 실행** — `/fleet` 명령으로 복수 에이전트를 동시 병렬 실행
- 🛡️ **안전 훅 시스템** — 위험 명령 자동 차단, README 동기화 검증, 세션 로깅
- 🧠 **자기개선 프로토콜** — 에이전트가 자신의 역량을 학습·축적하며 진화
- 🧩 **개인화** — `personal-advisor`로 사용 패턴 분석 → 맞춤 에이전트 자동 생성

> ⚠️ v2.0.0부터 `agents/*.agent.md` 기반 에이전트 시스템으로 전면 재설계. `skills/`는 하위 호환 유지.

---

## 🚀 빠른 시작

```bash
# 공식 설치 명령 (모든 플랫폼 공통)
copilot plugin install Lee-SiHyeon/oh-my-copilot
```

설치 후 Copilot CLI를 **재시작**하고 `/experimental on`을 실행하면 15개 에이전트가 즉시 사용 가능합니다. 필요하면 `personal-advisor`로 사용자 전용 개인 에이전트도 바로 설계할 수 있습니다.

### Linux/WSL 의존성

```bash
sudo apt update && sudo apt install -y sqlite3 jq git
```

> `nlm-researcher` 사용 시: `pipx install notebooklm-mcp-cli` → `nlm login`

### 런타임 구조

- **공유 플러그인**: `~/.copilot/installed-plugins/oh-my-copilot/` — 에이전트, 훅, 스크립트 (human-gated)
- **사용자별 상태**: `~/.copilot/oh-my-copilot/` — `omc-memory.db`, `LEARNINGS.md`, `proposals.json`
- **크로스 플랫폼**: Windows/WSL/Linux/macOS 지원. Unix 계열은 `pwsh`와 `sqlite3` 필요.

> 에이전트 개선 제안은 user-local `proposals.json`에만 기록되며, 실제 적용은 사용자가 수동 검토·승인합니다.

### 에이전트로 시작하기

```bash
# 복잡한 작업 (권장 진입점) — Meta-Orchestrator가 작업을 분해하고 병렬 Atlas 세션을 관리
copilot --agent oh-my-copilot:meta-orchestrator

# 단일 작업 — Atlas가 직접 전문 에이전트에 위임
copilot --agent oh-my-copilot:atlas

# 셸 alias 예시 (선택사항):
# mo() { copilot --agent oh-my-copilot:meta-orchestrator --autopilot "$@"; }
# atlas() { copilot --agent oh-my-copilot:atlas --autopilot "$@"; }
```

```
REST API 인증 시스템 전체 구현해줘   ← Meta-Orchestrator가 분해 → Atlas가 하위 에이전트에 위임
```

> 📡 Atlas는 답변 전 `web_search`를 수행하고, brain-work에서 `@nlm-researcher`를 PRIMARY 브레인으로 활용합니다.

### 트러블슈팅

| 증상 | 해결 |
|------|------|
| hooks 실행 안 됨 | 최신 버전으로 업데이트 (bash 스크립트 내장) |
| `sqlite3: command not found` | `sudo apt install sqlite3` |
| `jq: command not found` | `sudo apt install jq` |
| `nlm: command not found` | `pipx install notebooklm-mcp-cli` 후 `nlm login` |
| `nlm login --check` 실패 | Playwright stealth re-auth → `nlm login --relogin` fallback |
| `atlas` agent not found | `ln -s ~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/agents/atlas.agent.md ~/.copilot/agents/atlas.agent.md` |

---

## ⚡ Experimental Features (Required)

oh-my-copilot leverages Copilot CLI's experimental features for maximum capability.
**Run this once after installation:**

```
/experimental on
```

Or launch with: `copilot --experimental`

### What gets unlocked:

| Feature | Benefit for oh-my-copilot |
|---------|--------------------------|
| `MULTI_TURN_AGENTS` | Atlas keeps context across delegation rounds |
| `SUBAGENT_COMPACTION` | Long-running tasks don't lose context mid-flight |
| `SESSION_STORE` | Cross-session memory & learning persistence |
| `ASK_USER_ELICITATION` | Structured interview forms (Prometheus, deep-interview) |
| `STATUS_LINE` | Real-time progress display in terminal |
| `BACKGROUND_SESSIONS` | Persistent ralph-loop and ultrawork workflows that survive session restarts |
| `EXTENSIONS` | SDK scaffold available in `extensions/` — opt-in preview |

> 💡 **Individual features**: Set specific flags via environment variable:
> ```bash
> export COPILOT_CLI_ENABLED_FEATURE_FLAGS="MULTI_TURN_AGENTS,SESSION_STORE"
> ```

> ⚠️ Without experimental mode, core capabilities like multi-turn delegation, session memory, and structured forms will be unavailable. Atlas and other agents will operate in a limited single-turn mode.

---

## 🤖 에이전트 팀 (15개)

| 에이전트 | 역할 | 태그 | Best For |
|---|---|---|---|
| **Meta-Orchestrator** 🌐 | 최상위 오케스트레이터 (Layer 0) | `v2.0+` 오케스트레이션 | 작업 분해, 병렬 Atlas 세션 관리, 세션 메모리, 적응적 재배정 |
| **Atlas** 🗺️ | Layer 1 오케스트레이터 | `v2.0+` 오케스트레이션 | 단일 작업 내 전문가 위임·조율, `/fleet`과 `@에이전트명`으로 실행 |
| **Sisyphus** ⚙️ | 멀티태스크 오케스트레이터 | `v2.0+` 오케스트레이션 | 여러 단계가 얽힌 복잡한 작업 분해·병렬 실행 |
| **Sisyphus-Junior** 🔩 | 원자 태스크 실행기 | `v2.0+` 실행 | 단일 태스크 완수, 위임 없이 직접 실행 |
| **Hephaestus** 🔨 | 딥 구현 전문가 | `v2.0+` 구현 | 코드 구현, 리팩토링, 버그 수정 |
| **Prometheus** 🔥 | 전략 플래너 | `v2.0+` 계획 | 요구사항 인터뷰, 태스크 분해, 실행 계획 |
| **Oracle** 🔮 | 아키텍처 어드바이저 | `v2.0+` 분석 | 하드 디버깅, 설계 검토 (읽기전용) |
| **Metis** 🧠 | 사전 계획 컨설턴트 | `v2.0+` 분석 | 숨겨진 의도·모호함 식별, 리스크 도출 |
| **Momus** 🎭 | 계획 리뷰어 | `v2.0+` 리뷰 | `OKAY` / `REJECT` + 최대 3개 이슈 |
| **Explore** 🔍 | 코드베이스 탐색기 | `v2.0+` 분석 | grep, 파일 구조, 의존성 추적 |
| **Librarian** 📚 | 라이브러리 리서치 | `v2.0+` 리서치 | 문서 조사, API 사용법, 패키지 비교 |
| **NLM-Researcher** 🔬 | NotebookLM 리서치 | `v2.0+` 리서치 | AI/tech 노트북 쿼리, synthesis — Atlas PRIMARY 브레인 |
| **Multimodal-Looker** 👁️ | 이미지·문서 분석 | `v2.0+` 분석 | 스크린샷, PDF/이미지 정보 추출 |
| **Ultrawork** ⚡ | 풀 오케스트레이션 | `v2.0+` 오케스트레이션 | 플래닝 + 병렬 실행 + 검증 원커맨드 |
| **Personal-Advisor** 🧩 | 개인화 어드바이저 | `v2.0+` 개인화 | MCP 신호 기반 개인 에이전트 추천/초안 |

### 에이전트 호출 방법

복잡한 작업은 Meta-Orchestrator부터 시작하세요. 단일 작업은 Atlas로 직접 호출할 수 있습니다.

```bash
copilot --agent oh-my-copilot:meta-orchestrator   # 복잡한 작업의 권장 진입점
copilot --agent oh-my-copilot:atlas               # 단일 작업 직접 위임
copilot --agent oh-my-copilot:hephaestus          # 구현 작업만 있을 때
copilot --agent oh-my-copilot:oracle              # 읽기전용 아키텍처 자문
copilot --agent oh-my-copilot:metis               # 사전 리스크 파악
copilot --agent oh-my-copilot:momus               # 계획서 검토 (OKAY / REJECT)
copilot --agent oh-my-copilot:nlm-researcher      # 심층 리서치·합성·계획
copilot --agent oh-my-copilot:personal-advisor    # 개인 에이전트 추천/초안
```

> 💡 oh-my-claudecode 플러그인의 전문 에이전트(security-reviewer, verifier, code-simplifier, qa-tester, test-engineer, writer)도 함께 사용할 수 있습니다.

---

## 🚢 Fleet 패턴 & Heavy Mode

### Fleet 병렬 실행

`/fleet`으로 여러 에이전트를 **병렬로 동시 실행**해 작업 속도를 극대화합니다.

> `/fleet`은 Atlas 에이전트가 내부 task 도구를 통해 병렬 처리하는 패턴을 부르는 이름입니다.
>
> 🌐 **상위 레이어**: Meta-Orchestrator는 여러 Atlas 인스턴스를 병렬로 실행하며, 각 Atlas가 독립적으로 `/fleet`을 사용합니다.

```
"다음 3개 태스크를 병렬로 실행해줘:
  1. hephaestus로 auth 모듈 구현
  2. hephaestus로 database 스키마 마이그레이션
  3. prometheus로 API 문서 계획 수립"
```

```
Atlas (조율)
  ├── @hephaestus ──→ auth 구현 완료
  ├── @hephaestus ──→ DB 마이그레이션 완료   ← 동시 실행
  └── @prometheus ──→ API 문서 계획 완료
        ▼
  @momus 계획 검토 → @oracle 아키텍처 최종 검증
```

### 직렬 의존 패턴

```
@metis → @prometheus → @momus → @hephaestus → @oracle
(리스크)   (계획)      (검토)    (구현)       (검증)
```

### Heavy Mode

복잡한 작업에서 Atlas가 자동으로 **Heavy Mode**를 활성화합니다. 3개 에이전트를 병렬로 실행해 탐색·합성·구현을 동시에 처리합니다.

```
Atlas (Heavy Mode)
  ├── @explore (코드 탐색)
  ├── @oracle (아키텍처 분석)
  └──→ 결과 수집 → @hephaestus 또는 @sisyphus-junior (구현)
```

**트리거**: 멀티파일 리팩토링, 대규모 버그 수정, 새 시스템 설계, 복잡한 디버깅 시 자동 활성화.

**NLM 연계**: brain-work 필요 시 `@nlm-researcher`가 `@oracle`과 함께 사용됩니다.

> 🌐 **Meta-Orchestrator 연계**: Meta-Orchestrator는 여러 Atlas를 병렬 실행하며, 각 Atlas가 독립적으로 Heavy Mode를 활성화할 수 있습니다. 이를 통해 진정한 대규모 병렬 처리가 가능합니다.

---

## 🧩 개인화 에이전트

개인화는 **공유 에이전트**를 늘리는 대신, 사용자 전용 에이전트를 **개인 저장소**에 두는 방식으로 설계되어 있습니다.

| 위치 | 용도 |
|------|------|
| `~/.copilot/agents/` | **권장** — 완전한 개인 영역, git에 푸시되지 않음 |
| `local/agents/` | 플러그인 내부 override, `.gitignore`로 제외 |
| `agents/` | 공유 영역 (git-tracked) — 개인 파일 금지 |
| `~/.copilot/oh-my-copilot/` | 런타임 메모리 (`omc-memory.db`, `LEARNINGS.md`) |

### personal-advisor

```bash
copilot --agent oh-my-copilot:personal-advisor
```

세션 기록, 완료한 todo, 에이전트 사용 기록, MCP/서버 신호를 분석해 **1~3개의 개인 에이전트**를 추천·초안 생성합니다. 수집 스크립트 `scripts/collect-session-data.ps1`가 신호를 모아 추천 근거로 사용합니다.

> MCP 힌트: GitHub MCP → 저장소 워크플로우, browser MCP → 웹 QA, database MCP → SQL 특화 에이전트
> 원칙: 개인 에이전트는 `~/.copilot/agents/`가 1순위이며, `local/agents/`는 gitignored 보조 override입니다.

---

## ⚡ 빠른 참조 (Quick Reference)

| 명령어 | 설명 |
|--------|------|
| `/meta-orchestrator` | 최상위 오케스트레이터 — 병렬 Atlas 세션 관리 |
| `/atlas` | Layer 1 오케스트레이터 실행 |
| `/ultrawork` | 풀 자동화 워크플로우 |
| `/ralph-loop` | 완료까지 자기교정 루프 |
| `/prometheus` | 인터뷰 기반 전략 플래닝 |
| `/explore` | 코드베이스 검색 및 분석 |
| `/oracle` | 읽기전용 디버깅 자문 |
| `/hephaestus` | 딥 구현 전문가 |
| `/fleet` | 병렬 에이전트 실행 |

---

## 💰 모델 비용 가이드

에이전트별로 적절한 모델을 선택해 **비용을 최적화**하세요.

| 티어 | 모델 | 배율 | 추천 용도 |
|---|---|---|---|
| 🥇 **기본값** | `claude-sonnet-4.6` | 1x | 대부분의 구현 작업, 기본 오케스트레이션 |
| 🥈 **저렴** | `claude-haiku-4.5` | 0.33x | 단순 원자 태스크, Sisyphus-Junior, Explore |
| 🆓 **무료** | `gpt-5-mini` | **0x** | 가볍고 빠른 작업, 비용 절감 최우선 시 |
| 🆓 **무료** | `gpt-4.1` | **0x** | 무료이면서 고품질이 필요할 때 |
| 🔁 **Fallback** | `gpt-5.4` | 1x | Sonnet rate-limit(429) 시 Atlas 자동 재시도 |
| 💡 **코드 전문** | `gpt-5.3-codex` | 1x | 코드 생성 집중 작업 |
| 🏃 **빠른 저렴** | `gpt-5.4-mini` | 0.33x | 빠른 응답이 필요한 저비용 작업 |
| 💎 **프리미엄** | `claude-opus-*` | **3x~30x** | 고난도 작업 시 선택적 사용 — 아키텍처 설계, 심층 디버깅, 복잡한 오케스트레이션 |

> 💡 **권장**: `gpt-4.1` (무료) → 복잡한 구현 `claude-sonnet-4.6` → Sonnet 429 시 `gpt-5.4` 자동 fallback → 고난도 아키텍처·분석 `claude-opus-*` 선택적 사용

---

## 🛡️ 안전 훅

`hooks.json`의 `preToolUse` 훅이 **위험 명령 실행 전 자동으로 개입**합니다. 위험 명령뿐 아니라, `agents/`, `scripts/`, `plugin.json`, `hooks.json` 같은 핵심 파일이 변경됐는데 `README.md`가 갱신되지 않은 상태도 감지합니다.

### 위험 패턴 감지

| 카테고리 | 감지 패턴 |
|---|---|
| **파일 삭제** | `rm -rf`, `Remove-Item -Recurse -Force`, `del /f /s`, `rd /s /q` |
| **강제 푸시** | `git push --force`, `git push -f` |
| **DB 파괴** | `DROP TABLE`, `DELETE FROM` |
| **시스템 포맷** | `format` |

위험 패턴 감지 시 실행이 **자동 중단**되고 사용자 확인을 요청합니다.

```json
{
  "permissionDecision": "ask",
  "permissionDecisionReason": "Dangerous operation detected: rm -rf"
}
```

README 동기화 누락은 `preToolUse`에서 비차단 경고, `sessionEnd`에서 최종 차단합니다.

> 💡 `agents/`, `scripts/`, `plugin.json`, `hooks.json`, `.gitignore` 등 핵심 파일 변경 시 반드시 `README.md`도 함께 수정해야 세션 종료가 성공합니다.

### 세션 로깅 & 메모리

- `sessionStart`: `~/.copilot/session.log`에 타임스탬프·작업 디렉터리 기록
- 메모리 파일: `~/.copilot/oh-my-copilot/omc-memory.db`, `LEARNINGS.md`
- `sessionEnd`: 공유 소스 변경 시 `proposals.json`에 제안 기록 (자동 커밋/푸시 안 함)

### 제안 큐 (Proposal Queue)

`~/.copilot/oh-my-copilot/proposals.json`에 에이전트 개선 제안을 user-local로 축적합니다. SHA256 중복 제거, human-gated 적용 (자동 mutation 없음), < 20ms 오버헤드.

```bash
# proposals.json 목록 보기
cat ~/.copilot/oh-my-copilot/proposals.json | jq '.'
```

> 공유 플러그인 루트는 human-gated 유지. 자동 진화는 사용자 로컬 상태에 제안·학습 형태로만 축적.

---

## 🔄 에이전트 상태 머신

각 에이전트 태스크는 다음 라이프사이클을 따릅니다:

```
pending → in_progress → completed
                     ↘ failed (복구 불가 오류 시)
```

**상태 설명:**
- **pending**: 태스크 대기 중, 에이전트가 클레임하기를 기다림
- **in_progress**: 에이전트가 태스크를 클레임하고 작업 중
- **completed**: 태스크가 검증된 결과와 함께 성공적으로 완료됨
- **failed**: 완료 불가 — 사람의 개입이나 재시도 필요

**전환 규칙:**
- 하나의 태스크는 단일 에이전트만 클레임 (해시 기반 중복 방지)
- 상태는 역방향 전환 불가 (`completed → in_progress` 금지)
- `atlas` 오케스트레이터가 전환을 모니터링하고 멈춘 태스크를 재배정

**세션 라이프사이클:**
1. `sessionStart` 훅이 메모리를 초기화하고 컨텍스트를 로드
2. Atlas가 사용자 요청을 태스크로 분해
3. 전문 에이전트들이 의존성 순서에 따라 태스크를 실행
4. `sessionEnd` 훅이 학습 내용을 통합하고 개선 제안을 큐에 추가

---

## 📦 프로젝트 구조

> 자세한 구조는 [ARCHITECTURE.md](ARCHITECTURE.md) 참조

```
oh-my-copilot/
├── .gitignore                       ← local/ 및 레거시 호환용 개인 데이터 경로 제외
├── plugin.json                      ← 플러그인 메타데이터 및 에이전트 등록
├── hooks.json                       ← 안전 훅 (preToolUse, sessionEnd, sessionStart)
├── LEARNINGS.md                     ← 플러그인 수준 학습 기록
├── agents/                          ← ✨ v2.0 주 시스템
│   ├── meta-orchestrator.agent.md   ← 최상위 오케스트레이터 (Layer 0)
│   ├── atlas.agent.md               ← Layer 1 오케스트레이터
│   ├── sisyphus.agent.md            ← 복잡한 멀티태스크 오케스트레이터
│   ├── sisyphus-junior.agent.md     ← 원자 태스크 실행기
│   ├── hephaestus.agent.md          ← 딥 구현 전문가
│   ├── prometheus.agent.md          ← 전략 플래너
│   ├── oracle.agent.md              ← 아키텍처 어드바이저 (읽기전용)
│   ├── metis.agent.md               ← 사전 계획 컨설턴트
│   ├── momus.agent.md               ← 계획 리뷰어
│   ├── explore.agent.md             ← 코드베이스 탐색기
│   ├── librarian.agent.md           ← 외부 라이브러리 리서치
│   ├── nlm-researcher.agent.md      ← NotebookLM 리서치 에이전트 (PRIMARY 사고 브레인)
│   ├── multimodal-looker.agent.md   ← 이미지·문서 분석
│   ├── ultrawork.agent.md           ← 풀 오케스트레이션 모드
│   └── personal-advisor.agent.md    ← 개인 에이전트 추천/초안 어드바이저
├── scripts/
│   └── collect-session-data.ps1     ← 세션 기록·todo·Q-table·MCP 신호 수집
├── local/                           ← gitignored 개인 override 영역
│   ├── README.md                    ← 개인화 사용 가이드
│   └── agents/                      ← 사용자 전용 override 에이전트
└── skills/                          ← 레거시 스킬 (하위 호환 유지)
    ├── atlas/
    ├── chronicle/
    ├── dev-browser/
    ├── explore/
    ├── frontend-ui-ux/
    ├── git-master/
    ├── github-triage/
    ├── hephaestus/
    ├── init-deep/
    ├── librarian/
    ├── metis/
    ├── momus/
    ├── multimodal-looker/
    ├── oracle/
    ├── playwright/
    ├── prometheus/
    ├── ralph-loop/
    ├── setup/
    ├── sisyphus/
    ├── sisyphus-junior/
    └── ultrawork/

~/.copilot/
├── session.log                      ← 세션 시작/종료 로그 (기존 유지)
├── session-state/                   ← Copilot 세션 DB들 (기존 유지)
├── agents/                          ← 사용자 전용 개인 에이전트 저장소 (기존 유지)
└── oh-my-copilot/
    ├── omc-memory.db                ← 사용자별 메모리 DB (semantic_memory, policy rules, Q-table)
    ├── LEARNINGS.md                 ← 사용자별 런타임 learnings (정식 위치)
    └── proposals.json               ← MVP: user-local 제안 큐 (git-untracked, 자동 진화)
```

---

## 📜 원작 크레딧

이 프로젝트는 [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent) (by [@code-yeongyu](https://github.com/code-yeongyu))의 멀티에이전트 철학과 프롬프트 구조를 GitHub Copilot CLI 에이전트 포맷으로 이식·재설계한 것입니다.

원작의 핵심 사상 — *"에이전트는 단일 책임을 가지며, 오케스트레이터가 전체를 조율한다"* — 을 그대로 계승합니다.

---

## 📄 라이선스

MIT © [Lee SiHyeon](https://github.com/Lee-SiHyeon)
