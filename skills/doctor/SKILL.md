---
name: doctor
description: Diagnose and fix oh-my-copilot installation issues. Checks plugin path, broken symlinks, dependencies (sqlite3/jq/git), hooks.json validity, script permissions, and plugin version. Trigger with "doctor", "진단", "install check", "헬스체크", "health check".
---

# oh-my-copilot Doctor — 설치 진단 및 자동 수정

> **목적**: oh-my-copilot 플러그인의 설치 상태를 진단하고, 발견된 문제를 사용자 확인 후 자동 수정합니다.

## 트리거 키워드

`doctor` · `진단` · `install check` · `헬스체크` · `health check` · `설치 확인`

---

## Phase 0: 플러그인 디렉토리 탐지

```bash
# 두 가지 설치 경로를 모두 지원
OMC_DIR=""
for d in \
  "$HOME/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot" \
  "$HOME/.copilot/installed-plugins/oh-my-copilot"; do
  if [ -d "$d" ]; then
    OMC_DIR="$d"
    break
  fi
done

if [ -z "$OMC_DIR" ]; then
  echo "❌ FATAL: oh-my-copilot 플러그인 디렉토리를 찾을 수 없습니다."
  echo "   확인한 경로:"
  echo "   • $HOME/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot"
  echo "   • $HOME/.copilot/installed-plugins/oh-my-copilot"
  echo ""
  echo "   재설치 방법: GitHub Copilot CLI에서 플러그인을 다시 설치하세요."
  exit 1
fi

echo "✅ 플러그인 디렉토리: $OMC_DIR"
```

---

## Phase 1: 진단 항목 실행

각 항목을 순서대로 실행하고 결과를 수집합니다.

### 1-1. 플러그인 설치 경로 확인

```bash
CHECK_PLUGIN_DIR="PASS"
PLUGIN_DIR_NOTE="$OMC_DIR"

if [ ! -d "$OMC_DIR" ]; then
  CHECK_PLUGIN_DIR="FAIL"
  PLUGIN_DIR_NOTE="디렉토리 없음"
fi
echo "[1] 플러그인 경로: $CHECK_PLUGIN_DIR — $PLUGIN_DIR_NOTE"
```

### 1-2. Broken symlink 탐지

```bash
BROKEN_LINKS=""
BROKEN_LINKS=$(find "$OMC_DIR" -type l -exec sh -c \
  'test ! -e "$1" && echo "$1"' _ {} \; 2>/dev/null)

if [ -z "$BROKEN_LINKS" ]; then
  CHECK_SYMLINKS="PASS"
  SYMLINK_NOTE="없음"
else
  CHECK_SYMLINKS="FAIL"
  SYMLINK_NOTE=$(echo "$BROKEN_LINKS" | wc -l | tr -d ' ')개
  echo "  Broken symlinks 목록:"
  echo "$BROKEN_LINKS" | sed 's/^/    • /'
fi
echo "[2] Broken symlink: $CHECK_SYMLINKS — ${SYMLINK_NOTE}"
```

### 1-3. 의존성 확인 (sqlite3 / jq / git)

```bash
MISSING_DEPS=""
for dep in sqlite3 jq git; do
  if ! command -v "$dep" > /dev/null 2>&1; then
    MISSING_DEPS="$MISSING_DEPS $dep"
  fi
done

if [ -z "$MISSING_DEPS" ]; then
  CHECK_DEPS="PASS"
  DEPS_NOTE="sqlite3 ✓  jq ✓  git ✓"
else
  CHECK_DEPS="FAIL"
  DEPS_NOTE="누락:$(echo $MISSING_DEPS | tr ' ' ',')"
fi
echo "[3] 의존성: $CHECK_DEPS — $DEPS_NOTE"
```

### 1-4. hooks.json 유효성 검사

```bash
HOOKS_FILE="$OMC_DIR/hooks.json"

if [ ! -f "$HOOKS_FILE" ]; then
  CHECK_HOOKS="FAIL"
  HOOKS_NOTE="hooks.json 파일 없음"
elif jq empty "$HOOKS_FILE" > /dev/null 2>&1; then
  CHECK_HOOKS="PASS"
  HOOK_COUNT=$(jq '[.hooks | to_entries[].value | length] | add // 0' "$HOOKS_FILE" 2>/dev/null)
  HOOKS_NOTE="유효한 JSON, 훅 엔트리 ${HOOK_COUNT}개"
else
  CHECK_HOOKS="FAIL"
  HOOKS_NOTE="JSON 파싱 오류: $(jq empty "$HOOKS_FILE" 2>&1 | head -1)"
fi
echo "[4] hooks.json: $CHECK_HOOKS — $HOOKS_NOTE"
```

### 1-5. 스크립트 실행권한 확인 (scripts/*.sh)

```bash
NO_EXEC_SCRIPTS=""
for script in "$OMC_DIR"/scripts/*.sh; do
  [ -f "$script" ] || continue
  if [ ! -x "$script" ]; then
    NO_EXEC_SCRIPTS="$NO_EXEC_SCRIPTS\n$script"
  fi
done

if [ -z "$NO_EXEC_SCRIPTS" ]; then
  CHECK_PERMS="PASS"
  PERMS_NOTE="모든 스크립트 실행 가능"
else
  CHECK_PERMS="FAIL"
  COUNT=$(printf '%b' "$NO_EXEC_SCRIPTS" | grep -c '^/' || true)
  PERMS_NOTE="${COUNT}개 스크립트 실행권한 없음"
  echo "  실행권한 없는 스크립트:"
  printf '%b' "$NO_EXEC_SCRIPTS" | grep '^/' | sed 's/^/    • /'
fi
echo "[5] 스크립트 권한: $CHECK_PERMS — $PERMS_NOTE"
```

### 1-6. plugin.json 버전 확인

```bash
PLUGIN_JSON="$OMC_DIR/plugin.json"

if [ ! -f "$PLUGIN_JSON" ]; then
  CHECK_VERSION="WARN"
  VERSION_NOTE="plugin.json 없음"
elif jq empty "$PLUGIN_JSON" > /dev/null 2>&1; then
  INSTALLED_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_JSON")
  CHECK_VERSION="INFO"
  VERSION_NOTE="v${INSTALLED_VERSION}"
else
  CHECK_VERSION="WARN"
  VERSION_NOTE="plugin.json 파싱 실패"
fi
echo "[6] 버전: $CHECK_VERSION — $VERSION_NOTE"
```

---

## Phase 2: 진단 결과 리포트

```bash
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  oh-my-copilot Doctor Report"
echo "  플러그인 경로: $OMC_DIR"
echo "════════════════════════════════════════════════════════════"
echo ""
printf "%-5s %-25s %-10s %s\n" "No." "항목" "상태" "상세"
echo "────────────────────────────────────────────────────────────"
printf "%-5s %-25s %-10s %s\n" "[1]" "플러그인 설치 경로"    "$CHECK_PLUGIN_DIR" "$PLUGIN_DIR_NOTE"
printf "%-5s %-25s %-10s %s\n" "[2]" "Broken symlink"        "$CHECK_SYMLINKS"   "$SYMLINK_NOTE"
printf "%-5s %-25s %-10s %s\n" "[3]" "의존성 (sqlite3/jq/git)" "$CHECK_DEPS"     "$DEPS_NOTE"
printf "%-5s %-25s %-10s %s\n" "[4]" "hooks.json 유효성"     "$CHECK_HOOKS"      "$HOOKS_NOTE"
printf "%-5s %-25s %-10s %s\n" "[5]" "스크립트 실행권한"     "$CHECK_PERMS"      "$PERMS_NOTE"
printf "%-5s %-25s %-10s %s\n" "[6]" "설치 버전"             "$CHECK_VERSION"    "$VERSION_NOTE"
echo "────────────────────────────────────────────────────────────"

# 전체 통과 여부 판단
ALL_PASS=true
for status in "$CHECK_PLUGIN_DIR" "$CHECK_SYMLINKS" "$CHECK_DEPS" "$CHECK_HOOKS" "$CHECK_PERMS"; do
  [ "$status" = "FAIL" ] && ALL_PASS=false
done

if $ALL_PASS; then
  echo ""
  echo "✅ 모든 진단 항목 통과. oh-my-copilot이 정상 설치되어 있습니다."
else
  echo ""
  echo "⚠️  문제가 발견되었습니다. Phase 3 자동 수정을 진행합니다."
fi
echo ""
```

---

## Phase 3: 자동 수정 (문제 발견 시만 실행)

> 각 수정 전 사용자에게 확인을 구합니다. 사용자가 거부하면 해당 항목을 건너뜁니다.

### 3-1. Broken symlink 제거

```bash
if [ "$CHECK_SYMLINKS" = "FAIL" ] && [ -n "$BROKEN_LINKS" ]; then
  echo "🔧 [수정 1/3] Broken symlink 제거"
  echo "   다음 broken symlink를 제거합니다:"
  echo "$BROKEN_LINKS" | sed 's/^/   • /'
  echo ""
  echo "   → 사용자 확인 후 아래 명령을 실행하세요:"
  echo ""
  echo "$BROKEN_LINKS" | while IFS= read -r link; do
    [ -n "$link" ] && echo "   rm -f \"$link\""
  done
  echo ""
  # 실제 수정 실행 (사용자 승인 획득 후)
  echo "$BROKEN_LINKS" | while IFS= read -r link; do
    if [ -n "$link" ] && [ -L "$link" ]; then
      rm -f "$link"
      echo "   ✅ 제거됨: $link"
    fi
  done
fi
```

### 3-2. 스크립트 실행권한 부여

```bash
if [ "$CHECK_PERMS" = "FAIL" ] && [ -n "$NO_EXEC_SCRIPTS" ]; then
  echo "🔧 [수정 2/3] 스크립트 실행권한 부여 (chmod +x)"
  printf '%b' "$NO_EXEC_SCRIPTS" | grep '^/' | while IFS= read -r script; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
      chmod +x "$script"
      echo "   ✅ chmod +x: $script"
    fi
  done
  echo ""
fi
```

### 3-3. 의존성 누락 안내

```bash
if [ "$CHECK_DEPS" = "FAIL" ] && [ -n "$MISSING_DEPS" ]; then
  echo "🔧 [수정 3/3] 누락 의존성 설치 안내"
  echo "   누락된 패키지:$(echo $MISSING_DEPS)"
  echo ""
  echo "   install.sh를 실행하여 의존성을 설치할 수 있습니다:"
  echo ""
  echo "   bash \"$OMC_DIR/scripts/install.sh\""
  echo ""
  echo "   ⚠️  자동 실행은 하지 않습니다. 위 명령을 직접 실행하세요."
  echo ""
fi
```

---

## Phase 4: 수정 후 재검증

```bash
echo "════════════════════════════════════════════════════════════"
echo "  재검증 결과"
echo "════════════════════════════════════════════════════════════"

# Broken symlink 재확인
REMAINING_BROKEN=$(find "$OMC_DIR" -type l -exec sh -c \
  'test ! -e "$1" && echo "$1"' _ {} \; 2>/dev/null)
if [ -z "$REMAINING_BROKEN" ]; then
  echo "✅ Broken symlink: 없음"
else
  echo "❌ Broken symlink: 아직 남아있음"
  echo "$REMAINING_BROKEN" | sed 's/^/   • /'
fi

# 스크립트 권한 재확인
STILL_NO_EXEC=""
for script in "$OMC_DIR"/scripts/*.sh; do
  [ -f "$script" ] && [ ! -x "$script" ] && STILL_NO_EXEC="$STILL_NO_EXEC $script"
done
if [ -z "$STILL_NO_EXEC" ]; then
  echo "✅ 스크립트 실행권한: 정상"
else
  echo "❌ 스크립트 실행권한: 일부 미해결"
fi

echo ""
echo "Doctor 진단 완료."
```

---

## 진단 항목 요약표

| No. | 항목 | 확인 방법 | 자동 수정 |
|-----|------|-----------|-----------|
| 1 | 플러그인 설치 경로 | `[ -d <plugin_dir> ]` | ✗ (재설치 안내) |
| 2 | Broken symlink | `find -type l + test ! -e` | ✅ `rm -f` |
| 3 | 의존성 (sqlite3/jq/git) | `command -v` | ✗ (install.sh 안내) |
| 4 | hooks.json 유효성 | `jq empty hooks.json` | ✗ (수동 확인 필요) |
| 5 | 스크립트 실행권한 | `[ -x scripts/*.sh ]` | ✅ `chmod +x` |
| 6 | 설치 버전 | `jq .version plugin.json` | ✗ (정보 표시) |

---

## 알려진 문제 및 원인

| 증상 | 원인 | 해결 |
|------|------|------|
| Copilot CLI `ENOENT` 오류 | `tests/bats/bin/bats → /usr/bin/bats` broken symlink | [2] 자동 수정 |
| hook 미실행 | `session-start.sh` 실행권한 없음 | [5] 자동 수정 |
| jq/sqlite3 명령 없음 | 의존성 미설치 | `scripts/install.sh` 실행 |
| hooks.json 파싱 실패 | JSON 형식 오류 | 직접 편집 필요 |
