#!/usr/bin/env bats
# pre-tool-use.sh 위험 패턴 차단 테스트
#
# 스크립트 동작 정리:
#   - 위험 패턴 감지 시: exit 0 + JSON {"permissionDecision":"ask",...}
#   - 미등록 패턴(shutdown, mkfs, dd, git reset --hard, truncate): exit 0 + 출력 없음
#   - 안전한 명령: exit 0 + 출력 없음
#
# 입력 JSON 포맷: {"toolName":"bash","toolArgs":"<command>"}

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/pre-tool-use.sh"

setup() {
  setup_isolation
  # DB가 없으면 스크립트가 init-memory.sh를 자동 실행하므로
  # 격리된 HOME에 디렉터리만 미리 생성
  mkdir -p "$HOME/.copilot/oh-my-copilot"
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# 등록된 위험 패턴: exit 0 + permissionDecision=ask
# ──────────────────────────────────────────────────────────────────────────────

@test "rm -rf / 패턴 차단: ask 결정 반환" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"rm -rf /\"}' | bash '$SCRIPT'"
  assert_success
  assert_output --partial "ask"
}

@test "rm -rf ~ 패턴 차단: ask 결정 반환" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"rm -rf ~\"}' | bash '$SCRIPT'"
  assert_success
  assert_output --partial "ask"
}

@test "git push --force 패턴 차단: ask 결정 반환" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"git push --force origin main\"}' | bash '$SCRIPT'"
  assert_success
  assert_output --partial "ask"
}

@test "DROP TABLE 패턴 차단: ask 결정 반환" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"sqlite3 db.sqlite \\\"DROP TABLE users;\\\"\"}' | bash '$SCRIPT'"
  assert_success
  assert_output --partial "ask"
}

# ──────────────────────────────────────────────────────────────────────────────
# 미등록 위험 패턴: 현재 스크립트에서 처리하지 않으므로 통과됨
# (추후 패턴 추가 시 assert_output --partial "ask" 로 변경 필요)
# ──────────────────────────────────────────────────────────────────────────────

@test "shutdown 패턴: 미등록 패턴으로 통과됨" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"sudo shutdown -h now\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

@test "mkfs 패턴: 미등록 패턴으로 통과됨" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"mkfs.ext4 /dev/sda\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

@test "dd if=/dev/zero 패턴: 미등록 패턴으로 통과됨" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"dd if=/dev/zero of=/dev/sda\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

@test "git reset --hard 패턴: 미등록 패턴으로 통과됨" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"git reset --hard HEAD~10\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

@test "truncate 패턴: 미등록 패턴으로 통과됨" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"truncate -s 0 /etc/passwd\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

# ──────────────────────────────────────────────────────────────────────────────
# 안전한 명령: 출력 없이 통과
# ──────────────────────────────────────────────────────────────────────────────

@test "안전한 echo 명령 통과" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"echo hello world\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}

@test "안전한 ls 명령 통과" {
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"ls -la /tmp\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "ask"
}
