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
- **12개 전문 에이전트**: 역할별로 분리된 단일 책임 에이전트 팀
- **Fleet 패턴**: `/fleet` 명령으로 복수 에이전트를 병렬 실행
- **안전 훅**: `preToolUse` 훅으로 위험 명령 실행 전 자동 확인 요청
- **자기개선 프로토콜**: 에이전트가 직접 자신의 `.agent.md`를 수정해 역량을 축적

> ⚠️ `skills/` 디렉터리의 레거시 스킬들은 하위 호환을 위해 유지되지만, 주 시스템은 `agents/`입니다.

---

## 🚀 빠른 시작

```bash
# 공식 설치 명령 (모든 플랫폼 공통)
copilot plugin install Lee-SiHyeon/oh-my-copilot
```

설치 후 Copilot CLI를 **재시작**하면 12개 에이전트가 즉시 사용 가능합니다.

#### Atlas 에이전트로 시작하기

```bash
# --agent 플래그로 Atlas를 기본 에이전트로 지정
copilot --agent oh-my-copilot:atlas

# 또는 PowerShell 프로필에 alias 추가 (권장)
# function atlas { & "copilot.cmd" --agent oh-my-copilot:atlas --autopilot @args }
```

```
REST API 인증 시스템 전체 구현해줘   ← Atlas가 하위 에이전트에 위임
```

---

## 🤖 에이전트 팀 (12개)

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

### 에이전트 호출 방법

Atlas를 기본 에이전트로 시작한 후, Atlas가 내부적으로 하위 에이전트에 위임합니다.

```bash
# --agent 플래그로 특정 에이전트 직접 시작
copilot --agent oh-my-copilot:atlas       ← 항상 Atlas부터 시작 (권장)
copilot --agent oh-my-copilot:hephaestus  ← 구현 작업만 있을 때 직접 호출
copilot --agent oh-my-copilot:oracle      ← 읽기전용 아키텍처 자문
copilot --agent oh-my-copilot:metis       ← 사전 리스크 파악
copilot --agent oh-my-copilot:momus       ← 계획서 검토 (OKAY / REJECT)
```

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

---

## 🔧 구조

```
oh-my-copilot/
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
│   └── ultrawork.agent.md          ← 풀 오케스트레이션 모드
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
```

---

## 📜 원작 크레딧

이 프로젝트는 [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent) (by [@code-yeongyu](https://github.com/code-yeongyu))의 멀티에이전트 철학과 프롬프트 구조를 GitHub Copilot CLI 에이전트 포맷으로 이식·재설계한 것입니다.

원작의 핵심 사상 — *"에이전트는 단일 책임을 가지며, 오케스트레이터가 전체를 조율한다"* — 을 그대로 계승합니다.

---

## 📄 License

MIT © [Lee SiHyeon](https://github.com/Lee-SiHyeon)
