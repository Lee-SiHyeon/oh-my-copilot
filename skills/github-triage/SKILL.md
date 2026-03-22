---
name: github-triage
version: 1.0.0
description: |
  GitHub 이슈/PR read-only 트리아지. 모든 오픈 이슈와 PR을 분석해서
  보고서를 /tmp/에 저장합니다. GitHub에 어떤 변경도 하지 않습니다.
  "triage", "이슈 분석", "PR 검토", "github triage" 트리거로 사용합니다.
  oh-my-opencode github-triage 스킬을 Copilot CLI에 포팅했습니다.
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# GitHub Triage — Read-Only 분석기

> **ZERO ACTION 정책**: GitHub에 어떤 변경도 하지 않습니다. 분석 보고서만 작성.

## 아키텍처

**1 이슈/PR = 1 백그라운드 에이전트 = 1 보고서 파일**

| 규칙 | 값 |
|------|-----|
| 실행 | 병렬 (모든 아이템 동시) |
| 추적 | TodoWrite 1개/아이템 |
| 출력 | `/tmp/{YYYYMMDD-HHmmss}/issue-{N}.md` 또는 `pr-{N}.md` |

---

## Zero-Action 정책 (절대)

### FORBIDDEN
```
gh issue comment, gh issue close, gh issue edit
gh pr comment, gh pr merge, gh pr review, gh pr edit
gh api -X POST/PUT/PATCH/DELETE
```

### ALLOWED
```
gh issue view, gh pr view, gh api (GET만)
grep, glob, 파일 읽기
git log, git show, git blame
Write — /tmp/ 에만
```

---

## Phase 0: 설정

```powershell
$REPO = gh repo view --json nameWithOwner -q .nameWithOwner
$REPORT_DIR = "/tmp/$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force $REPORT_DIR
$COMMIT_SHA = git rev-parse HEAD
Write-Host "레포: $REPO, 보고서: $REPORT_DIR"
```

---

## Phase 1: 오픈 아이템 가져오기

```powershell
# 이슈 목록 (본문 제외 — JSON 파싱 문제 방지)
$ISSUES = gh issue list --repo $REPO --state open --limit 500 `
  --json number,title,labels,author,createdAt | ConvertFrom-Json

# PR 목록
$PRS = gh pr list --repo $REPO --state open --limit 500 `
  --json number,title,labels,author,headRefName,baseRefName,isDraft,createdAt | ConvertFrom-Json

Write-Host "이슈: $($ISSUES.Count), PR: $($PRS.Count)"
```

**대형 레포 처리**: 50개 초과 시 전체 처리. 샘플링 금지.

---

## Phase 2: 분류

| 유형 | 감지 기준 |
|------|----------|
| `ISSUE_QUESTION` | [Question], [Discussion], ?, "how to", "why does" |
| `ISSUE_BUG` | [Bug], Bug:, 에러 메시지, 스택 트레이스 |
| `ISSUE_FEATURE` | [Feature], [Enhancement], Feature Request |
| `ISSUE_OTHER` | 기타 |
| `PR_BUGFIX` | fix로 시작, fix/ 브랜치, bug 라벨 |
| `PR_OTHER` | 나머지 |

---

## Phase 3: 병렬 분석 (서브에이전트)

```powershell
# 이슈별 TodoWrite 생성
foreach ($issue in $ISSUES) {
  Write-Host "분석: #$($issue.number) $($issue.title)"
  # 각 이슈별 개별 분석 수행
}
```

### 각 서브에이전트 공통 프롬프트

```
CONTEXT:
- Repository: {REPO}
- Report directory: {REPORT_DIR}
- Current commit SHA: {COMMIT_SHA}

PERMALINK FORMAT:
모든 코드 참조는 반드시 퍼머링크 포함:
https://github.com/{REPO}/blob/{COMMIT_SHA}/{filepath}#L{start}-L{end}
퍼머링크 없는 주장 = 주장 없음. 미확인은 [UNVERIFIED] 표시.

절대 규칙 위반 = 치명적 실패:
- NEVER: gh issue/pr comment/close/edit/merge/review
- NEVER: -X POST/PUT/PATCH/DELETE
- ONLY Write: {REPORT_DIR}/{issue|pr}-{number}.md
```

---

## 보고서 형식 — ISSUE_BUG

```markdown
# Issue #{number}: {title}
**타입:** Bug Report | **작성자:** {author} | **생성:** {createdAt}

## 버그 요약
**예상:** [사용자가 기대한 것]
**실제:** [실제 발생한 것]
**재현:** [재현 단계]

## 판정: [CONFIRMED_BUG | NOT_A_BUG | ALREADY_FIXED | UNCLEAR]

## 분석

### 근거
[각 근거 + 퍼머링크]

### 근본 원인 (CONFIRMED_BUG의 경우)
[어떤 파일, 어떤 함수, 무엇이 잘못됨]
- 문제 코드: [`{path}#L{N}`](permalink)

### 수정 상세 (ALREADY_FIXED의 경우)
- 수정 커밋: [`{short_sha}`](commit_permalink)
- 수정 날짜: {date}
- 변경 내용: [설명 + diff 퍼머링크]

## 심각도: [LOW | MEDIUM | HIGH | CRITICAL]

## 권장 액션
[메인테이너가 할 것]
```

## 보고서 형식 — ISSUE_QUESTION

```markdown
# Issue #{number}: {title}

## 질문
[1-2문장 요약]

## 발견 사항
[각 발견 + 퍼머링크 증거]

## 제안 답변
[코드 참조와 퍼머링크 포함]

## 신뢰도: [HIGH | MEDIUM | LOW]

## 권장 액션
```

## 보고서 형식 — PR

```markdown
# PR #{number}: {title}

## 수정 요약
[무슨 버그, 어떻게 수정 — 변경 코드 퍼머링크 포함]

## 코드 리뷰

| 검사 | 상태 |
|------|------|
| CI | [PASS / FAIL / PENDING] |
| 리뷰 | [APPROVED / CHANGES_REQUESTED / PENDING] |
| Mergeable | [YES / NO / CONFLICTED] |
| 위험도 | [NONE / LOW / MEDIUM / HIGH] |

## 권장 액션: [MERGE | REQUEST_CHANGES | NEEDS_REVIEW | WAIT]
```

---

## Phase 4: 최종 요약

`{REPORT_DIR}/SUMMARY.md` 생성:

```markdown
# GitHub Triage 보고서 — {REPO}

**날짜:** {date} | **커밋:** {COMMIT_SHA}
**처리된 아이템:** {total}

## 이슈 ({count})
| 카테고리 | 수 |
|----------|-----|
| 버그 확인됨 | {n} |
| 이미 수정됨 | {n} |
| 버그 아님 | {n} |
| 질문 분석됨 | {n} |
| 기능 요청 평가됨 | {n} |

## PR ({count})

## 주의 필요 아이템
[번호, 제목, 판정, 1줄 요약, 보고서 링크]
```

---

## Anti-Patterns

| 위반 | 심각도 |
|------|--------|
| GitHub 변경 (comment/close/merge/etc) | **CRITICAL** |
| 퍼머링크 없는 주장 | **CRITICAL** |
| `quick` 아닌 카테고리 사용 | CRITICAL |
| 여러 아이템을 하나로 배치 | CRITICAL |
| 순차 처리 (병렬 필수) | HIGH |
| 증거 없는 추측 | HIGH |
| 브랜치명 퍼머링크 (커밋 SHA 필수) | HIGH |
