---
name: init-deep
version: 1.0.0
description: |
  계층형 AGENTS.md 파일 자동 생성. 프로젝트 전체를 분석해서 루트와 복잡한
  서브디렉토리에 AGENTS.md를 생성합니다. "AGENTS.md 만들어줘", "init-deep",
  "프로젝트 문서화", "코드맵 만들어" 트리거로 사용합니다.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# INIT-DEEP — 계층형 AGENTS.md 생성기

> "에이전트가 코드베이스를 처음 보는 것처럼 문서를 만들어라."

## 사용법

```
/init-deep                    # 업데이트 모드: 기존 수정 + 새로 필요한 곳 생성
/init-deep --create-new       # 기존 읽기 → 전체 삭제 → 재생성
/init-deep --max-depth=2      # 디렉토리 깊이 제한 (기본: 3)
```

---

## TodoWrite (MANDATORY)

```
즉시 TodoWrite:
1. "discovery" — 프로젝트 탐색 + LSP 코드맵
2. "scoring" — 디렉토리 복잡도 점수 계산
3. "generate" — AGENTS.md 파일 생성
4. "review" — 중복 제거, 검증
```

---

## Phase 1: Discovery + Analysis

### 프로젝트 구조 파악

```powershell
# 디렉토리 깊이 + 파일 수
$dirs = Get-ChildItem -Recurse -Directory | 
  Where-Object { $_.FullName -notmatch 'node_modules|\.git|dist|build|venv' }

# 확장자별 파일 분포
Get-ChildItem -Recurse -File | 
  Where-Object { $_.FullName -notmatch 'node_modules|\.git|dist|build' } |
  Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 10

# 디렉토리별 파일 수 (상위 20개)
Get-ChildItem -Recurse -File |
  Where-Object { $_.FullName -notmatch 'node_modules|\.git|dist|build' } |
  Group-Object DirectoryName | Sort-Object Count -Descending | Select-Object -First 20

# 기존 AGENTS.md / CLAUDE.md 찾기
Get-ChildItem -Recurse -Filter "AGENTS.md" |
  Where-Object { $_.FullName -notmatch 'node_modules' }
```

### 동적 에이전트 스폰 (프로젝트 규모 기반)

```powershell
$totalFiles = (Get-ChildItem -Recurse -File | 
  Where-Object { $_.FullName -notmatch 'node_modules|\.git' }).Count
$totalLines = (Get-ChildItem -Recurse -File -Include "*.ts","*.py","*.js","*.go" |
  Where-Object { $_.FullName -notmatch 'node_modules' } |
  ForEach-Object { (Get-Content $_.FullName).Count } | Measure-Object -Sum).Sum
$largeFiles = (Get-ChildItem -Recurse -File -Include "*.ts","*.py" |
  Where-Object { (Get-Content $_.FullName).Count -gt 500 }).Count
```

| 요소 | 임계값 | 추가 탐색 |
|------|--------|----------|
| 전체 파일 | >100 | 100개당 +1 백그라운드 에이전트 |
| 전체 줄수 | >10k | 10k줄당 +1 |
| 대형 파일 | >10개 | +1 복잡도 탐색 |
| 디렉토리 깊이 | ≥4 | +2 깊이 탐색 |

---

## Phase 2: Scoring Matrix

각 디렉토리 복잡도 점수:

| 요소 | 가중치 | 높음 기준 |
|------|--------|----------|
| 파일 수 | 3x | >20 |
| 서브디렉토리 수 | 2x | >5 |
| 코드 비율 | 2x | >70% |
| 모듈 경계 | 2x | index.ts/__init__.py 있음 |
| 고유 패턴 | 1x | 자체 설정 있음 |

**생성 결정:**

| 점수 | 액션 |
|------|------|
| Root (.) | 항상 생성 |
| >15 | AGENTS.md 생성 |
| 8-15 | 별도 도메인이면 생성 |
| <8 | 건너뜀 (부모가 커버) |

---

## Phase 3: Root AGENTS.md 생성

```markdown
# PROJECT KNOWLEDGE BASE

**생성:** {TIMESTAMP}
**커밋:** {SHORT_SHA}
**브랜치:** {BRANCH}

## 개요
{1-2문장: 무엇 + 핵심 스택}

## 구조
\`\`\`
{root}/
├── {dir}/    # {비자명한 목적만}
└── {entry}
\`\`\`

## 어디를 보나
| 태스크 | 위치 | 메모 |
|--------|------|------|

## 코드 맵
{심볼, 타입, 위치, 역할}

## 컨벤션
{표준에서 벗어난 것만}

## 금지 패턴 (이 프로젝트)
{명시적으로 금지된 것}

## 커맨드
\`\`\`bash
{dev/test/build}
\`\`\`

## 주의사항
{함정}
```

**품질 기준**: 50-150줄, 일반적 조언 없음, 자명한 정보 없음.

---

## Phase 4: 서브디렉토리 AGENTS.md 생성

각 점수 통과 디렉토리에 30-80줄 AGENTS.md:

```markdown
# {DIRNAME} — {1줄 설명}

## 개요
{1줄}

## 구조 (서브디렉토리 >5개인 경우)
{파일 트리}

## 어디를 보나
{태스크 → 파일 매핑}

## 컨벤션 (부모와 다른 경우만)
{지역 패턴}

## 금지
{지역 안티패턴}
```

**절대 규칙**: 자식은 부모 내용을 반복하지 않는다.

---

## Phase 5: Review & Deduplicate

각 생성 파일:
- 일반적 조언 제거
- 부모 중복 제거
- 크기 제한 준수
- 전보문체 검증

---

## 최종 보고

```
=== init-deep 완료 ===

모드: update | create-new

파일:
  [OK] ./AGENTS.md (루트, {N}줄)
  [OK] ./src/hooks/AGENTS.md ({N}줄)
  [SKIP] ./src/utils/ (점수 6 — 부모가 커버)

분석된 디렉토리: {N}
생성된 AGENTS.md: {N}
업데이트된 AGENTS.md: {N}

계층:
  ./AGENTS.md
  └── src/hooks/AGENTS.md
```

---

## Anti-Patterns

- ❌ 정적 에이전트 수 (프로젝트 규모에 따라 동적으로)
- ❌ 순차 실행 (병렬로 탐색 + 생성)
- ❌ 기존 무시 (--create-new여도 먼저 읽기)
- ❌ 과도한 문서화 (모든 디렉토리에 AGENTS.md 불필요)
- ❌ 중복 (자식은 부모 내용 반복 금지)
- ❌ 일반적 내용 ("이 프로젝트는 TypeScript를 사용합니다")
