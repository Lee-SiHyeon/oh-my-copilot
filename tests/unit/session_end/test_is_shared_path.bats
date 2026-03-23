#!/usr/bin/env bats
# session-end.sh is_shared_path 함수 테스트
#
# is_shared_path 함수는 플러그인 루트 기준 상대 경로를 검사:
#   true  (exit 0): ^agents/, ^scripts/, hooks.json, plugin.json,
#                   LEARNINGS.md, README.md, local/README.md, .gitignore
#   false (exit 1): 그 외 모든 경로 (/etc/..., 절대경로 등)
#
# 주의: source 시 session-end.sh 상단 코드(mkdir, log, git 조작)가 실행되므로
#       git() stub으로 실제 git 작업을 방지한다.

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/session-end.sh"

# source + 함수 호출을 단일 subshell에서 수행하는 헬퍼
# - git stub: 실제 git add/commit/push 방지
# - 모든 side-effect 출력을 /dev/null으로 억제
run_is_shared_path() {
  local path="$1"
  # HOME은 이미 setup_isolation()에 의해 ISOLATED_HOME으로 설정됨
  bash -c "
    git() { :; }
    export -f git
    source '${SCRIPT}' 2>/dev/null || true
    is_shared_path '${path}'
  " 2>/dev/null
}

setup() {
  setup_isolation
  mkdir -p "$HOME/.copilot/oh-my-copilot"
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# 공유 경로 (true 반환 기대)
# ──────────────────────────────────────────────────────────────────────────────

@test "is_shared_path: agents/ 접두사 경로는 true 반환" {
  run run_is_shared_path "agents/my-agent"
  assert_success
}

@test "is_shared_path: scripts/ 접두사 경로는 true 반환" {
  run run_is_shared_path "scripts/init-memory.sh"
  assert_success
}

@test "is_shared_path: hooks.json은 true 반환" {
  run run_is_shared_path "hooks.json"
  assert_success
}

@test "is_shared_path: plugin.json은 true 반환" {
  run run_is_shared_path "plugin.json"
  assert_success
}

@test "is_shared_path: README.md는 true 반환" {
  run run_is_shared_path "README.md"
  assert_success
}

@test "is_shared_path: .gitignore는 true 반환" {
  run run_is_shared_path ".gitignore"
  assert_success
}

# ──────────────────────────────────────────────────────────────────────────────
# 비공유 경로 (false 반환 기대)
# /etc/ 같은 시스템 절대 경로는 플러그인 상대 경로가 아니므로 false
# ──────────────────────────────────────────────────────────────────────────────

@test "is_shared_path: /etc/ 절대경로는 false 반환" {
  run run_is_shared_path "/etc/hosts"
  assert_failure
}

@test "is_shared_path: 홈 디렉터리 절대경로는 false 반환" {
  run run_is_shared_path "$HOME/.local/bin/tool"
  assert_failure
}

@test "is_shared_path: 임의 파일명은 false 반환" {
  run run_is_shared_path "random.txt"
  assert_failure
}
