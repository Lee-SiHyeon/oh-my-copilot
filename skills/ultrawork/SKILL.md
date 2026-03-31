---
name: ultrawork
version: 1.0.0
description: |
  원커맨드 풀 오케스트레이션. Sisyphus + Hephaestus + Prometheus가 모두 활성화됩니다.
  "ultrawork", "ulw", "ulw-loop", "다 해줘", "전부 해줘" 트리거로 사용합니다.
  oh-my-opencode의 ultrawork를 Copilot CLI에 포팅한 스킬입니다.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# ULTRAWORK — 원커맨드 풀 오케스트레이션

> "Install. Type `ultrawork`. Done." — oh-my-opencode 철학

## 사용법

```
/ultrawork "태스크 설명"
/ulw "태스크 설명"
/ultrawork "태스크" --loop          # 완료까지 Ralph Loop 모드
/ultrawork "태스크" --plan-first    # Prometheus 플래닝 후 실행
```

## 에이전트 팀

| 에이전트 | 역할 | 담당 |
|----------|------|------|
| **Mogul** (Sisyphus) | 오케스트레이터 | 태스크 분해, 병렬 위임, 진행 추적 |
| **Craftsman** (Hephaestus) | 딥워커 | 목표 기반 자율 실행, 코드 구현 |
| **Strategist** (Prometheus) | 플래너 | 인터뷰, 요구사항 명확화, 계획 수립 |

---

## ULTRAWORK 프로토콜

### Phase 0: Intent Classification

태스크를 받으면 즉시 분류:

| 유형 | 판별 기준 | 전략 |
|------|----------|------|
| **Trivial** | 단일 파일, <10줄 변경 | 즉시 실행 |
| **Simple** | 1-2파일, 명확한 범위 | 가벼운 확인 후 실행 |
| **Complex** | 3+파일, 여러 컴포넌트 | Prometheus 인터뷰 → 태스크 분해 → 병렬 실행 |
| **Architectural** | 시스템 설계, 인프라 | Prometheus 전략 세션 → Oracle 검토 → 실행 |

### Phase 1: TodoWrite (MANDATORY for Complex+)

**모든 비-trivial 태스크에서 즉시 TodoWrite:**

```
TodoWrite([
  { id: "plan", content: "태스크 분해 및 계획 수립", status: "in_progress" },
  { id: "explore", content: "코드베이스 탐색 및 패턴 파악", status: "pending" },
  { id: "impl-1", content: "구현 태스크 1: [구체적 설명]", status: "pending" },
  { id: "verify", content: "결과 검증", status: "pending" }
])
```

**규칙:**
- 모든 태스크는 시작 전 `in_progress`, 완료 후 즉시 `completed`
- 배치 완료 금지 — 실시간 추적
- 태스크는 구체적으로: "validateToken() 함수를 src/auth/middleware.ts에 추가" (O), "인증 구현" (X)

### Phase 2: Parallel Exploration

**코드베이스 탐색 (병렬):**

```bash
# 프로젝트 구조 파악
find . -type f \( -name "*.ts" -o -name "*.py" -o -name "*.js" -o -name "*.go" -o -name "*.rs" \) \
  -not -path "*/node_modules/*" \
  | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -10

# 패키지 의존성
[ -f package.json ] && python3 -c "import json; d=json.load(open('package.json')); print(d.get('dependencies', {}))"
[ -f requirements.txt ] && cat requirements.txt
```

탐색 중 파악할 것:
1. 기존 코드 패턴 (네이밍, 구조, 에러 핸들링)
2. 테스트 인프라 존재 여부
3. 관련 기존 구현체

### Phase 3: Execution (Hephaestus Mode)

각 태스크를 Hephaestus 철학으로 실행:

**Hephaestus 실행 원칙:**
- 레시피 아닌 목표를 받았음 → 스스로 판단
- 코드베이스 탐색 후 기존 패턴에 맞게 구현
- 막히면 다른 접근법 시도, 포기하지 않음
- 각 구현 후 즉시 검증

**검증 방법:**
```bash
# TypeScript/Node
npx tsc --noEmit
npm test

# Python
python -m pytest
python -m mypy .

# 실행 테스트
# 직접 함수/API 호출로 결과 확인
```

### Phase 4: Oracle Verification (for Complex tasks)

구현 완료 후 자기검토:

```
Oracle Verification Checklist:
□ 모든 TodoWrite 태스크가 completed?
□ 타입 에러 없음?
□ 테스트 통과?
□ 기존 패턴과 일치?
□ 엣지케이스 처리됨?
□ 사용자가 요청한 것을 정확히 구현했는가?
```

실패한 항목 있으면 → 루프로 돌아가 재작업

### Phase 5: Completion Report

```
═══════════════════════════════════
ULTRAWORK COMPLETE
═══════════════════════════════════
태스크:    [태스크 설명]
소요:      [완료된 단계 수]
결과:      ✅ 성공 | ⚠️ 부분 성공 | ❌ 실패

완료된 항목:
  ✅ [태스크 1]
  ✅ [태스크 2]

검증:
  ✅ 타입 검사 통과
  ✅ 테스트 통과

변경된 파일:
  - [파일1]
  - [파일2]
═══════════════════════════════════
```

---

## ULTRAWORK LOOP 모드 (`--loop`)

```
/ultrawork "태스크" --loop
```

Ralph Loop 활성화: 완료까지 자동 반복

1. 작업 실행
2. 검증
3. 미완료 항목 있으면 자동 재시작
4. 모든 검증 통과 시 `<promise>DONE</promise>` 출력 후 종료

---

## Background Workflow Persistence

Ultrawork orchestrates long-running workflows through multiple phases (plan → fleet → verify). With `BACKGROUND_SESSIONS` enabled, ultrawork can checkpoint between phases so that workflows survive session restarts.

### Checkpoint Pattern

After each phase completion, write checkpoint via `t-state_write(mode: "ultrawork")`:

| Phase | Checkpoint Data |
|-------|----------------|
| Planning | `{phase: "planning", plan_path, completed_phases: []}` |
| Execution | `{phase: "execution", plan_path, completed_phases: ["planning"], fleet_results}` |
| Verification | `{phase: "verification", plan_path, completed_phases: ["planning", "execution"], fleet_results}` |

### State Schema

```json
{
  "version": 1,
  "active": true,
  "phase": "execution",
  "completed_phases": ["planning"],
  "plan_path": "/tmp/ultrawork-plan-abc123.md",
  "fleet_results": {
    "task-1": "COMPLETE",
    "task-2": "IN_PROGRESS"
  },
  "started_at": "2025-01-15T10:00:00Z",
  "updated_at": "2025-01-15T10:15:00Z"
}
```

### Resume Protocol

On session restart with active ultrawork state:
1. Read state via `t-state_read(mode: "ultrawork")`
2. Skip completed phases
3. Continue from last checkpoint
4. Display: "Resuming ultrawork from phase: {phase} ({N}/{total} phases complete)"

---

## Anti-Patterns (금지)

- ❌ 비-trivial 태스크에서 TodoWrite 건너뜀
- ❌ 여러 태스크 배치 완료
- ❌ "구현 완료"라고만 하고 검증 안 함
- ❌ 에러 발생 시 포기
- ❌ 사용자 요청 외 추가 변경
