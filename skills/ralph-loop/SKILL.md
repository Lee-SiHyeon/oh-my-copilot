---
name: ralph-loop
version: 1.0.0
description: |
  자기교정 반복 루프. 완료까지 자동으로 반복 실행합니다.
  "루프", "완료까지", "계속 해줘", "ralph-loop", "ulw-loop" 트리거로 사용합니다.
  oh-my-opencode의 Ralph Loop를 Copilot CLI에 포팅한 스킬입니다.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# RALPH LOOP — 완료까지 자기교정 루프

> "완료될 때까지 멈추지 않는다."

## 사용법

```
/ralph-loop "모든 TypeScript 에러 수정"
/ralph-loop "태스크 설명" --max-iterations=50
/ulw-loop "태스크 설명"         # ultrawork + loop 모드
/cancel-ralph                   # 실행 중인 루프 취소
```

## INVARIANTS
⚠️ NEVER declare done without <promise>DONE</promise>
⚠️ NEVER give up after first failure — try different approaches
⚠️ ALWAYS maintain TodoWrite tracking
⚠️ ALWAYS verify before marking complete

---

## ULTRAWORK LOOP vs RALPH LOOP

| | Ralph Loop | ULW Loop |
|--|-----------|----------|
| 종료 조건 | 완료 promise 태그 출력 | Oracle 검증 + promise 태그 |
| 반복 한도 | 기본 100회 (설정 가능) | 없음 |
| 검증 수준 | 자체 검증 | Oracle 독립 검증 |
| 사용 시기 | 일반 작업 | 크리티컬 작업 |

---

## Loop 프로토콜

### Phase 1: Task Initialization

```
태스크 수신 → 즉시 TodoWrite (원자적 스텝으로):

TodoWrite([
  { id: "analyze", content: "현재 상태 분석", status: "in_progress" },
  { id: "step-1", content: "[구체적 스텝 1]", status: "pending" },
  { id: "step-2", content: "[구체적 스텝 2]", status: "pending" },
  { id: "verify", content: "결과 검증", status: "pending" }
])
```

### Phase 2: Iteration Cycle

```
ITERATION N:
1. 남은 TodoWrite 항목 확인
2. 다음 pending 항목을 in_progress로
3. 해당 작업 실행
4. 결과 즉시 검증
5. completed 또는 failed 표시
6. 다음 반복 또는 완료 판정
```

### Phase 3: Completion Check

**각 반복 후 체크:**
```
□ 모든 TodoWrite 항목 completed?
□ 빌드/타입 에러 없음?
□ 테스트 통과?
□ 완료 기준 충족?
```

**모두 통과 시:**
```
<promise>DONE</promise>
```
→ 이 태그가 없으면 루프 계속 실행

**실패 항목 있을 시:**
- 실패 원인 분석
- 다른 접근법 시도
- TodoWrite 업데이트 후 계속

### 반복 실패 시 사용자 개입 (3회 이상 동일 실패)

같은 에러가 3회 이상 반복되면 자동으로 사용자에게 구조화된 선택지를 제시:

```
ask_user(
  question="[에러 내용] — 같은 실패가 3회 반복됐습니다. 어떻게 진행할까요?",
  choices=["계속 — 다른 접근법으로 재시도 (Recommended)", "전략 변경 — 새로운 전략을 제안해주세요", "중단 — 현재까지 완료된 것만 유지", "건너뛰기 — 이 항목 스킵하고 다음으로"]
)
```

**선택별 동작:**
- **계속**: 이전과 다른 접근법을 자동 선택하여 재시도
- **전략 변경**: 사용자에게 새 전략 입력 요청 → 해당 전략으로 전환
- **중단**: `<promise>DONE</promise>` 출력, 미완료 항목 목록 표시
- **건너뛰기**: 해당 TodoWrite 항목을 `skipped`로 표시, 다음 항목 진행

---

## ULTRAWORK LOOP 검증 프로세스

`/ulw-loop` 모드에서는 추가 Oracle 검증 단계:

```
1. 자체 작업 완료 → <promise>DONE</promise> 출력
2. Oracle 검증 프롬프트 실행:
   "방금 구현한 것이 요청 사항을 완전히 충족하는가?
    A) 충족 — 명확한 증거 제시
    B) 미충족 — 누락된 것 명시
    C) 부분 충족 — 완료된 것과 남은 것 구분"
3. A만 진짜 완료
4. B 또는 C → 루프 재시작
```

---

## Context Management for Long Loops

### Periodic Summary (every 10 iterations)

Every 10 iterations (10, 20, 30...), write a Loop Summary:

```
[LOOP-SUMMARY iteration={N} of={max}]
Task: {original task description}
Progress: {items done}/{total items}
Completed: {brief list of done items}
Failed & retried: {items that needed retry}
Current focus: {what iteration N+1 will work on}
Remaining: {pending items count}
[/LOOP-SUMMARY]
```

### Auto-Compact Trigger

Context management thresholds:
- At 50% context: Write a Loop Summary (even if not at iteration 10)
- At 70% context: Write Loop Summary + consider `/compact`
- At 80% context: MUST run `/compact` before continuing
- After `/compact`: Re-read the latest Loop Summary, re-state remaining todos, continue

Note: Context percentage is estimated by the agent based on the volume of file reads, command outputs, and conversation length.

### Strategy for 100-iteration scenarios

For high-iteration tasks (50+ expected iterations):
- Use `--strategy=continue` (default)
- Write Loop Summary every 10 iterations
- After `/compact`, the Loop Summary is the recovery checkpoint
- Keep TodoWrite items updated — they are the source of truth
- If the same item fails 5 times, mark it as blocked and move on

---

## Multi-Turn Loop Optimization

[MULTI-TURN-RALPH-LOOP]

When `MULTI_TURN_AGENTS` is available (detected by `write_agent` tool presence), the ralph loop can keep verification agents alive across iterations instead of spawning new ones each cycle.

### Legacy Loop Pattern (One-Shot)

```
iteration 1: task(verifier) → read_agent → done → discard
iteration 2: task(verifier) → read_agent → done → discard  ← full context rebuild
iteration 3: task(verifier) → read_agent → done → discard  ← full context rebuild
```

### Multi-Turn Loop Pattern (Optimized)

```
loop_start → task(verifier, mode="background")
  → [write_agent(fix_1) → read_agent]*
  → [write_agent(fix_2) → read_agent]*
  → ...
  → [write_agent(fix_N) → read_agent]*
→ loop_end
```

### Benefits

- **Faster iterations**: No context rebuild between loop cycles — the verifier already knows the codebase
- **Accumulated understanding**: The verifier learns from prior fixes, catches regression patterns
- **Lower cost**: Single agent dispatch + N incremental turns vs N full dispatches
- **Better error correlation**: Verifier can correlate new failures with prior fixes ("this broke because of the change in iteration 3")

### Implementation Rules

1. **Agent reuse scope**: Reuse the same verifier agent within a single ralph-loop session. Spawn fresh for new loop sessions.
2. **Staleness check**: If the verifier has been alive for 50+ turns, consider spawning fresh (context may be degraded)
3. **Failure fallback**: If `write_agent` returns an error or the agent is no longer `idle`, fall back to spawning a new verifier
4. **Loop Summary integration**: The `[LOOP-SUMMARY]` checkpoint should note multi-turn agent status:

```
[LOOP-SUMMARY iteration={N} of={max}]
...existing fields...
Multi-turn verifier: {agent_id} (turn {T}, status: {idle|completed})
[/LOOP-SUMMARY]
```

[/MULTI-TURN-RALPH-LOOP]

---

<!-- LOW-PRIORITY: Examples below may be removed during compaction -->

## 자주 쓰이는 패턴

### TypeScript 에러 수정 루프

```
/ralph-loop "모든 TypeScript 컴파일 에러 수정"

→ 루프 내부:
  1. npx tsc --noEmit 2>&1 실행
  2. 에러 목록 파싱
  3. 각 에러를 TodoWrite로
  4. 에러별 수정
  5. 다시 tsc 실행
  6. 에러 없으면 <promise>DONE</promise>
```

### 테스트 통과 루프

```
/ralph-loop "모든 테스트 통과"

→ 루프 내부:
  1. npm test 실행
  2. 실패 테스트 파악
  3. 실패별 수정
  4. 다시 npm test
  5. 모두 통과 → <promise>DONE</promise>
```

### 린트 정리 루프

```
/ralph-loop "모든 ESLint 경고 수정"

→ 루프 내부:
  1. npx eslint . 실행
  2. 경고 목록 파싱
  3. 자동 수정 가능한 것: npx eslint . --fix
  4. 수동 수정 필요한 것: TodoWrite로 개별 처리
  5. 모두 해결 → <promise>DONE</promise>
```

---

## 취소

실행 중 루프 취소:
```
/cancel-ralph
```

또는 Copilot CLI에서 `Ctrl+C` 후:
```
현재 루프가 취소됐습니다. 
완료된 TodoWrite: [목록]
미완료 TodoWrite: [목록]
```

---

## 설정

```
--max-iterations=N    # 최대 반복 횟수 (기본: 100)
--strategy=reset      # 각 반복마다 상태 초기화
--strategy=continue   # 이전 상태에서 계속 (기본)
```

---

## Anti-Patterns

- ❌ 검증 없이 완료 선언
- ❌ 첫 번째 실패 후 포기
- ❌ `<promise>DONE</promise>` 없이 루프 종료
- ❌ 같은 접근법으로 계속 실패 (다른 방법 시도)
- ❌ TodoWrite 없이 루프 시작 (추적 불가)
