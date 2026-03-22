# oh-my-copilot

> oh-my-opencode를 GitHub Copilot CLI에 포팅한 멀티에이전트 오케스트레이션 플러그인

[![GitHub stars](https://img.shields.io/github/stars/Lee-SiHyeon/oh-my-copilot?style=flat-square)](https://github.com/Lee-SiHyeon/oh-my-copilot/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent)의 핵심 철학을 GitHub Copilot CLI SKILL.md 포맷으로 이식했습니다.

---

## 🚀 빠른 시작

```bash
# 플러그인 디렉토리에 클론
git clone https://github.com/Lee-SiHyeon/oh-my-copilot ~/.copilot/installed-plugins/oh-my-copilot
```

Copilot CLI를 재시작하면 바로 사용 가능합니다.

---

## ✨ 스킬

| 스킬 | 트리거 | 설명 |
|------|--------|------|
| `/ultrawork` | `ultrawork`, `ulw`, `다 해줘` | 원커맨드 풀 오케스트레이션 |
| `/prometheus` | `계획 세워줘`, `플래닝`, `인터뷰` | 전략 플래닝 + 인터뷰 모드 |
| `/sisyphus` | `오케스트레이션`, `태스크 분해` | 메인 오케스트레이터 |
| `/hephaestus` | `딥워크`, `알아서 해줘` | 자율 딥워커 (허락 구하기 금지) |
| `/ralph-loop` | `완료까지`, `루프`, `계속 해줘` | 자기교정 반복 루프 |
| `/init-deep` | `AGENTS.md 만들어`, `init-deep` | 계층형 AGENTS.md 생성 |
| `/github-triage` | `triage`, `이슈 분석` | GitHub read-only 트리아지 |

---

## 📦 설치

### 자동 설치

```bash
git clone https://github.com/Lee-SiHyeon/oh-my-copilot ~/.copilot/installed-plugins/oh-my-copilot
```

### 수동 설치 (Windows)

```powershell
git clone https://github.com/Lee-SiHyeon/oh-my-copilot "$env:USERPROFILE\.copilot\installed-plugins\oh-my-copilot"
```

---

## 🤖 에이전트 팀

### Sisyphus (오케스트레이터)
복잡한 태스크를 원자적 서브태스크로 분해하고 병렬로 실행합니다.
- TodoWrite 강제 적용 — 모든 비-trivial 태스크에서
- 실시간 진행 추적
- 독립 태스크는 병렬 실행

### Hephaestus (딥워커)
목표만 주면 스스로 탐색하고 완료까지 실행하는 자율 딥워커.
- 허락 구하기 금지 — Just Do It
- Senior Staff Engineer 수준의 자율성
- 탐색 → 구현 → 검증 전체 루프

### Prometheus (플래닝)
코드 짜기 전에 인터뷰로 요구사항을 명확히 하는 전략 플래너.
- Intent classification (trivial → architecture)
- 코드베이스 탐색 먼저, 질문 나중
- `.sisyphus/plans/`에 계획 파일 생성

### Ralph Loop (자기교정)
완료될 때까지 자동으로 반복 실행하는 루프.
- `<promise>DONE</promise>` 태그로만 종료
- TypeScript 에러, 테스트 실패 등 반복 수정에 최적
- ULW Loop 모드: Oracle 검증 추가

---

## 📖 사용 예시

```
/ultrawork "REST API 인증 시스템 구현해줘"
```
→ Prometheus 인터뷰 → 태스크 분해 → 병렬 구현 → 검증

```
/prometheus "새 기능 추가 계획 세워줘"
```
→ 코드베이스 탐색 → 인터뷰 → `.sisyphus/plans/`에 계획 저장

```
/ralph-loop "모든 TypeScript 에러 수정"
```
→ `tsc --noEmit` → 에러 수정 → 반복 → 에러 0개 되면 완료

```
/init-deep
```
→ 프로젝트 전체 분석 → 복잡도 점수화 → 계층형 AGENTS.md 생성

```
/github-triage
```
→ 오픈 이슈/PR 분석 → 병렬 에이전트로 분류 → `/tmp/`에 보고서 저장

---

## 🔧 구조

```
oh-my-copilot/
├── SKILL.md                    ← 플러그인 인덱스
├── ultrawork/SKILL.md          ← /ultrawork 스킬
├── prometheus/SKILL.md         ← /prometheus 스킬
├── sisyphus/SKILL.md           ← /sisyphus 스킬
├── hephaestus/SKILL.md         ← /hephaestus 스킬
├── ralph-loop/SKILL.md         ← /ralph-loop 스킬
├── init-deep/SKILL.md          ← /init-deep 스킬
├── github-triage/SKILL.md      ← /github-triage 스킬
└── .agents/skills/             ← Copilot CLI 에이전트 등록
    ├── oh-my-copilot-ultrawork/
    ├── oh-my-copilot-prometheus/
    ├── oh-my-copilot-sisyphus/
    ├── oh-my-copilot-hephaestus/
    ├── oh-my-copilot-ralph-loop/
    ├── oh-my-copilot-init-deep/
    └── oh-my-copilot-github-triage/
```

---

## 📜 원작 크레딧

이 프로젝트는 [oh-my-opencode](https://github.com/code-yeongyu/oh-my-openagent) (by [@code-yeongyu](https://github.com/code-yeongyu))의 철학과 프롬프트 구조를 GitHub Copilot CLI 포맷으로 이식한 것입니다.

---

## 📄 License

MIT
