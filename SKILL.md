---
name: oh-my-copilot
version: 1.0.0
description: |
  oh-my-opencode를 Copilot CLI용으로 포팅한 멀티에이전트 오케스트레이션 플러그인.
  Sisyphus(오케스트레이터) + Hephaestus(딥워커) + Prometheus(플래너) + Ralph Loop.
  "/ultrawork 태스크설명" 으로 시작하면 모든 에이전트가 자동 활성화됩니다.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# oh-my-copilot 스킬 인덱스

## 사용 가능한 스킬

| 스킬 | 트리거 | 설명 |
|------|--------|------|
| `/ultrawork` | "ultrawork", "ulw", "전부 해줘" | 원커맨드 풀 오케스트레이션 |
| `/prometheus` | "계획 세워줘", "플래닝", "인터뷰" | 전략 플래닝 + 인터뷰 모드 |
| `/sisyphus` | "오케스트레이션", "태스크 분해" | 메인 오케스트레이터 |
| `/hephaestus` | "딥워크", "자율 실행" | 목표 기반 자율 딥워커 |
| `/ralph-loop` | "루프", "완료까지", "계속 해줘" | 완료까지 자기교정 루프 |
| `/init-deep` | "AGENTS.md 만들어줘", "init-deep" | 계층형 AGENTS.md 생성 |
| `/github-triage` | "triage", "이슈 분석" | GitHub 이슈/PR read-only 트리아지 |

## 빠른 시작

```
/ultrawork "REST API 인증 시스템 구현해줘"
/prometheus "새 기능 추가 계획 세워줘"
/ralph-loop "모든 TypeScript 에러 수정"
/init-deep
```

## 이 플러그인이 하는 것

oh-my-opencode의 핵심 철학을 Copilot CLI에 이식:
- **Sisyphus**: 태스크를 분해하고 병렬로 서브에이전트에 위임
- **Hephaestus**: 목표만 주면 알아서 실행하는 자율 딥워커
- **Prometheus**: 코드 짜기 전에 인터뷰로 요구사항 명확화
- **Ralph Loop**: 완료까지 멈추지 않는 자기교정 루프
- **ultrawork**: 위 모든 것을 한 커맨드로
