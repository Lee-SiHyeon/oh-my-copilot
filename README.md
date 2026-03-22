# oh-my-copilot

> oh-my-opencode를 GitHub Copilot CLI에 포팅한 프로덕션급 멀티에이전트 오케스트레이션 플러그인

[![GitHub stars](https://img.shields.io/github/stars/Lee-SiHyeon/oh-my-copilot?style=flat-square)](https://github.com/Lee-SiHyeon/oh-my-copilot/stargazers)
[![Version](https://img.shields.io/badge/version-2.0.0-blue?style=flat-square)](https://github.com/Lee-SiHyeon/oh-my-copilot)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📖 개요

**oh-my-copilot**은 [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent)의 멀티에이전트 철학을 GitHub Copilot CLI 환경으로 완전히 이식한 플러그인입니다.

**v2.0.0**부터는 SKILL.md 기반의 레거시 아키텍처에서 **`agents/*.agent.md` 기반의 에이전트 시스템**으로 전면 재설계되었습니다.

- **마스터 오케스트레이터**: `@atlas` — 모든 작업을 하위 에이전트에 위임합니다
- **총 13개 에이전트**: 공유 팀 에이전트 12개 + 개인화용 `personal-advisor`
- **Fleet 패턴**: `/fleet` 명령으로 복수 에이전트를 병렬 실행
- **안전 훅**: `preToolUse` 훅으로 위험 명령 실행 전 자동 확인 요청
- **자기개선 프로토콜**: 에이전트가 직접 자신의 `.agent.md`를 수정해 역량을 축적
- **개인 에이전트 지원**: `~/.copilot/agents/` 또는 `local/agents/`에 비공개 개인 에이전트 생성 가능

> ⚠️ `skills/` 디렉터리의 레거시 스킬들은 하위 호환을 위해 유지되지만, 주 시스템은 `agents/`입니다.

---

## 🚀 빠른 시작

```bash
# 공식 설치 명령 (모든 플랫폼 공통)
copilot plugin install Lee-SiHyeon/oh-my-copilot
```

설치 후 Copilot CLI를 **재시작**하면 13개 에이전트가 즉시 사용 가능합니다. 필요하면 `personal-advisor`로 사용자 전용 개인 에이전트도 바로 설계할 수 있습니다.

### 공유 플러그인 코드 vs 사용자별 런타임 상태

`oh-my-copilot`은 이제 **공유 코드**와 **사용자별로 진화하는 메모리 상태**를 분리합니다.

- **공유 플러그인 루트**: `~/.copilot/installed-plugins/oh-my-copilot/`
  → 에이전트, 훅, 스크립트, 문서 같은 **공유 소스 코드만** 둡니다.
- **사용자별 상태 루트**: `~/.copilot/oh-my-copilot/`
  → `omc-memory.db`, 런타임 `LEARNINGS.md` 같은 **개인 진화 상태**를 둡니다.
- **그대로 유지되는 공용 Copilot 경로**:
  - `~/.copilot/session.log`
  - `~/.copilot/session-state/`
  - `~/.copilot/agents/`

업그레이드 시 사용자 로컬 상태가 아직 없고 예전 플러그인 루트에 `omc-memory.db` / 런타임 `LEARNINGS.md`가 남아 있으면, 훅이 **한 번만 user-local 위치로 복사 마이그레이션**합니다. 그 이후에는 항상 user-local 파일이 우선합니다.

### 플랫폼 지원 및 실행 전략

oh-my-copilot은 **Windows / WSL / Ubuntu·Linux / macOS**를 실용적으로 지원하는 방향으로 문서화되어 있습니다.

- **공통 전략**: 공유 로직은 PowerShell 스크립트로 유지하고, 플랫폼별 런타임 진입점만 다르게 둡니다.
- **Windows**: Copilot 훅과 스크립트는 일반적인 PowerShell 실행 흐름을 사용합니다.
- **Unix-like (WSL / Linux / macOS)**: 훅은 `bash` 엔트리에서 시작하고, 내부에서 `pwsh`를 호출해 동일한 PowerShell 로직을 실행하는 전략을 사용합니다.
- **Unix-like 필수 도구**: `pwsh`와 `sqlite3`가 필요합니다.
- **문서 예시 원칙**: 경로는 가능한 한 `~/.copilot/...`, `local/...`, `scripts/...`처럼 이식 가능한 형태를 우선 사용하고, Windows 전용 예시는 별도로 라벨링합니다.
- **CLI 예시 원칙**: Windows에서는 `copilot.cmd`를 쓸 수 있지만, 문서에서는 플랫폼 공통인 `copilot`을 기본 예시로 사용합니다.

#### Atlas 에이전트로 시작하기

```bash
# --agent 플래그로 Atlas를 기본 에이전트로 지정
copilot --agent oh-my-copilot:atlas
 
# 또는 셸 alias / 함수 추가
# bash/zsh/pwsh 공통 개념 예시:
# atlas() { copilot --agent oh-my-copilot:atlas --autopilot "$@"; }
# Windows PowerShell 전용 예시:
# function atlas { & "copilot.cmd" --agent oh-my-copilot:atlas --autopilot @args }
```

```
REST API 인증 시스템 전체 구현해줘   ← Atlas가 하위 에이전트에 위임
```

> 참고: Atlas는 이제 연구·전략·기획·아키텍처 같은 brain-work를 시작할 때 `@nlm-researcher`를 기본 브레인으로 먼저 사용하고, `/research` 또는 `@research`는 저장형 웹 리포트가 필요할 때 우선 사용합니다.

개인화가 필요할 때는 세션 안에서 `/agent oh-my-copilot:personal-advisor`를 호출하거나, CLI에서 아래처럼 직접 시작할 수 있습니다.

```bash
copilot --agent oh-my-copilot:personal-advisor
```

---

## 🤖 에이전트 팀 (13개)

| 에이전트 | 역할 | Best For |
|---|---|---|
| **Atlas** 🗺️ | 마스터 오케스트레이터 | 모든 작업의 진입점. `/fleet`과 `@에이전트명`으로 하위 에이전트에 위임 |
| **Sisyphus** ⚙️ | 복잡한 멀티태스크 오케스트레이터 | 여러 단계가 얽힌 복잡한 작업 분해 및 병렬 실행 |
| **Sisyphus-Junior** 🔩 | 집중형 원자 태스크 실행기 | 단일 명확한 태스크 완수, 위임 없이 직접 실행 |
| **Hephaestus** 🔨 | 딥 구현 전문가 | 코드 구현, 리팩토링, 버그 수정 — 탐색→구현→검증 전체 루프 |
| **Prometheus** 🔥 | 전략 플래너 | 요구사항 인터뷰, 태스크 분해, 실행 계획 수립 |
| **Oracle** 🔮 | 아키텍처 어드바이저 (읽기전용) | 하드 디버깅, 아키텍처 설계 검토 — 코드 수정 없이 조언만 |
| **Metis** 🧠 | 사전 계획 컨설턴트 | 숨겨진 의도와 모호함 식별, 실행 전 리스크 도출 |
| **Momus** 🎭 | 계획 리뷰어 | 계획서를 받아 `OKAY` 또는 `REJECT` + 최대 3개 이슈 출력 |
| **Explore** 🔍 | 코드베이스 탐색기 | 컨텍스트 기반 grep, 파일 구조 파악, 의존성 추적 |
| **Librarian** 📚 | 외부 라이브러리 리서치 | 라이브러리 문서 조사, API 사용법, 패키지 비교 |
| **Multimodal-Looker** 👁️ | 이미지·문서 분석 에이전트 | 스크린샷 분석, PDF/이미지에서 정보 추출, UI 리뷰 |
| **Ultrawork** ⚡ | 풀 오케스트레이션 모드 | 플래닝 + 병렬 실행 + 검증을 한 번에 — 원커맨드 완전 자동화 |
| **Personal-Advisor** 🧩 | 개인화 어드바이저 | 세션 기록, 완료한 todo, 에이전트 사용 패턴, MCP 신호를 바탕으로 개인 에이전트 추천/초안 생성 |

### 에이전트 호출 방법

Atlas를 기본 에이전트로 시작한 후, Atlas가 내부적으로 하위 에이전트에 위임합니다.

```bash
# --agent 플래그로 특정 에이전트 직접 시작
copilot --agent oh-my-copilot:atlas       ← 항상 Atlas부터 시작 (권장)
copilot --agent oh-my-copilot:hephaestus  ← 구현 작업만 있을 때 직접 호출
copilot --agent oh-my-copilot:oracle      ← 읽기전용 아키텍처 자문
copilot --agent oh-my-copilot:metis       ← 사전 리스크 파악
copilot --agent oh-my-copilot:momus       ← 계획서 검토 (OKAY / REJECT)
copilot --agent oh-my-copilot:personal-advisor  ← 개인 에이전트 추천/초안
```

---

## 🧩 개인화 에이전트

개인화는 **공유 에이전트**를 늘리는 대신, 사용자 전용 에이전트를 **개인 저장소**에 두는 방식으로 설계되어 있습니다.

### 저장 위치

- **권장: `~/.copilot/agents/`** — 완전한 개인 영역. 머신 로컬이며 git에 푸시되지 않습니다.
- **보조: `local/agents/`** — 플러그인 내부의 개인 override 영역. `.gitignore`로 제외됩니다.
- **공유: `agents/`** — 플러그인 소유 영역. git-tracked이므로 개인 에이전트를 두면 안 됩니다.
- **런타임 메모리: `~/.copilot/oh-my-copilot/`** — 사용자별 `omc-memory.db`와 런타임 `LEARNINGS.md`가 저장됩니다.

### `personal-advisor` 사용

`personal-advisor`는 사용자 패턴을 읽어 **1~3개의 개인 에이전트**를 추천하고, 원하면 초안까지 잡아주는 어드바이저입니다.

```bash
/agent oh-my-copilot:personal-advisor
copilot --agent oh-my-copilot:personal-advisor
```

분석 신호는 다음을 함께 봅니다.

- 세션 기록과 최근 작업 디렉터리
- 완료한 todo
- 에이전트 사용 기록 / Q-table
- MCP / 서버 / 설정(config) 신호

특히 MCP 신호는 개인화의 핵심 힌트입니다.

- GitHub MCP → 저장소 워크플로우 특화 에이전트
- browser/devtools MCP → 웹 QA 특화 에이전트
- database MCP → SQL / 데이터 작업 특화 에이전트

수집 스크립트 `scripts/collect-session-data.ps1`는 이런 신호를 모아 `personal-advisor`가 추천 근거로 사용합니다.

> 원칙: 개인 에이전트는 `~/.copilot/agents/`가 1순위이며, `local/agents/`는 gitignored 보조 override입니다. 공유 `agents/`에는 개인 파일을 두지 마세요.

---

## 💰 모델 비용 가이드

에이전트별로 적절한 모델을 선택해 **비용을 최적화**하세요.

| 티어 | 모델 | 배율 | 추천 용도 |
|---|---|---|---|
| 🥇 **기본값** | `claude-sonnet-4.6` | 1x | 대부분의 구현 작업, 기본 오케스트레이션 |
| 🥈 **저렴** | `claude-haiku-4.5` | 0.33x | 단순 원자 태스크, Sisyphus-Junior, Explore |
| 🆓 **무료** | `gpt-5-mini` | **0x** | 가볍고 빠른 작업, 비용 절감 최우선 시 |
| 🆓 **무료** | `gpt-4.1` | **0x** | 무료이면서 고품질이 필요할 때 |
| ❌ **절대 금지** | `claude-opus-4.5` | **3x** | **사용 금지** — 비용 대비 효율 없음 |
| ❌ **절대 금지** | `claude-opus-4.6` | **3x** | **사용 금지** — 과금 폭탄 |
| ☢️ **즉시 취소** | `claude-opus-4.6 (fast mode)` | **30x** | **절대 절대 금지** — 요청 1회에 프리미엄 30배 소진 |

> 🚨 **Opus 계열 전체 금지**: `claude-opus-4.5` / `claude-opus-4.6` / `claude-opus-4.6-fast` — 어떤 이유로도 사용 불가  
> 💡 **권장 전략**: 일반 작업 `gpt-4.1` (무료) → 복잡한 구현 `claude-sonnet-4.6` → 그 이상은 없음
> 🔁 **Atlas 기본 fallback**: Sonnet 기반 기본 흐름이 실제 `429` rate-limit에 걸리면 한 번 `gpt-5.4`로 재시도합니다.

---

## 🚢 Fleet 패턴

`/fleet`으로 여러 에이전트를 **병렬로 동시 실행**해 작업 속도를 극대화합니다.

```
"다음 3개 태스크를 병렬로 실행해줘:
  1. hephaestus로 auth 모듈 구현
  2. hephaestus로 database 스키마 마이그레이션
  3. prometheus로 API 문서 계획 수립"
```

> `/fleet`은 Atlas 에이전트가 내부 task 도구를 통해 병렬 처리하는 패턴을 부르는 이름입니다.

### Fleet 실행 흐름

```
Atlas (조율)
  ├── @hephaestus ──→ auth 구현 완료
  ├── @hephaestus ──→ DB 마이그레이션 완료   ← 동시 실행
  └── @prometheus ──→ API 문서 계획 완료
        │
        ▼
  @momus 계획 검토 → OKAY
        │
        ▼
  @oracle 아키텍처 최종 검증
```

### 직렬 의존 패턴

```
@metis → @prometheus → @momus → @hephaestus → @oracle
(리스크 파악) → (계획) → (검토) → (구현) → (최종 검증)
```

---

## 🛡️ 안전 훅

`hooks.json`의 `preToolUse` 훅이 **위험 명령 실행 전 자동으로 개입**합니다.

### 감지하는 위험 패턴

| 카테고리 | 감지 패턴 |
|---|---|
| **파일 삭제** | `rm -rf`, `rm -r -force`, `Remove-Item -Recurse -Force`, `del /f /s`, `rd /s /q` |
| **강제 푸시** | `git push --force`, `git push -f` |
| **DB 파괴** | `DROP TABLE`, `DELETE FROM` |
| **시스템 포맷** | `format` |

위험 패턴이 감지되면 에이전트 실행이 **자동으로 중단**되고 사용자에게 확인을 요청합니다.

```json
{
  "permissionDecision": "ask",
  "permissionDecisionReason": "Dangerous operation detected: rm -rf"
}
```

### 세션 로깅

`sessionStart` 훅이 매 세션 시작 시 `~/.copilot/session.log`에 타임스탬프와 작업 디렉터리를 기록합니다. 에이전트가 어디서 무엇을 했는지 추적 가능합니다.

또한 omc의 가변 메모리 파일은 플러그인 루트가 아니라 `~/.copilot/oh-my-copilot/` 아래에서 관리됩니다.
- `~/.copilot/oh-my-copilot/omc-memory.db`
- `~/.copilot/oh-my-copilot/LEARNINGS.md`

`sessionEnd`의 auto-commit은 이제 이 개인 런타임 상태를 커밋하지 않고, 공유 소스 변경만 대상으로 삼습니다.

---

## 🔧 구조

```
oh-my-copilot/
├── .gitignore                       ← local/ 및 레거시 호환용 개인 데이터 경로 제외
├── plugin.json                     ← 플러그인 메타데이터 및 에이전트 등록
├── hooks.json                      ← 안전 훅 (preToolUse, sessionStart)
├── agents/                         ← ✨ v2.0 주 시스템
│   ├── atlas.agent.md              ← 마스터 오케스트레이터
│   ├── sisyphus.agent.md           ← 복잡한 멀티태스크 오케스트레이터
│   ├── sisyphus-junior.agent.md    ← 원자 태스크 실행기
│   ├── hephaestus.agent.md         ← 딥 구현 전문가
│   ├── prometheus.agent.md         ← 전략 플래너
│   ├── oracle.agent.md             ← 아키텍처 어드바이저 (읽기전용)
│   ├── metis.agent.md              ← 사전 계획 컨설턴트
│   ├── momus.agent.md              ← 계획 리뷰어
│   ├── explore.agent.md            ← 코드베이스 탐색기
│   ├── librarian.agent.md          ← 외부 라이브러리 리서치
│   ├── multimodal-looker.agent.md  ← 이미지·문서 분석
│   ├── ultrawork.agent.md          ← 풀 오케스트레이션 모드
│   └── personal-advisor.agent.md   ← 개인 에이전트 추천/초안 어드바이저
├── scripts/
│   └── collect-session-data.ps1    ← 세션 기록·todo·Q-table·MCP 신호 수집
├── local/                          ← gitignored 개인 override 영역
│   ├── README.md                   ← 개인화 사용 가이드
│   └── agents/                     ← 사용자 전용 override 에이전트
└── skills/                         ← 레거시 스킬 (하위 호환 유지)
    ├── atlas/
    ├── sisyphus/
    ├── sisyphus-junior/
    ├── hephaestus/
    ├── prometheus/
    ├── oracle/
    ├── metis/
    ├── momus/
    ├── explore/
    ├── librarian/
    ├── multimodal-looker/
    └── ultrawork/

~/.copilot/
├── session.log                     ← 세션 시작/종료 로그 (기존 유지)
├── session-state/                  ← Copilot 세션 DB들 (기존 유지)
├── agents/                         ← 사용자 전용 개인 에이전트 저장소 (기존 유지)
└── oh-my-copilot/
    ├── omc-memory.db               ← 사용자별 메모리 DB (정식 런타임 위치)
    └── LEARNINGS.md                ← 사용자별 런타임 learnings (정식 위치)
```

---

## 📜 원작 크레딧

이 프로젝트는 [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent) (by [@code-yeongyu](https://github.com/code-yeongyu))의 멀티에이전트 철학과 프롬프트 구조를 GitHub Copilot CLI 에이전트 포맷으로 이식·재설계한 것입니다.

원작의 핵심 사상 — *"에이전트는 단일 책임을 가지며, 오케스트레이터가 전체를 조율한다"* — 을 그대로 계승합니다.

---

## 📄 License

MIT © [Lee SiHyeon](https://github.com/Lee-SiHyeon)
