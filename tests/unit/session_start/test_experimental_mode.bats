#!/usr/bin/env bats
# session-start.sh experimental mode advisory 테스트
#
# 테스트 대상 (lines 23-56):
#   - .experimental-advised 플래그 파일 없으면 → 팁 메시지 출력
#   - .experimental-advised 이미 존재 → 팁 안 보임 (2회차 이후)
#   - config.json에 experimental: true → 팁 안 보임
#   - experimental + ralph-state.json active → 복구 메시지 출력
#   - experimental 아님 → 복구 메시지 출력 안 됨

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/session-start.sh"

setup() {
  setup_isolation
  mkdir -p "$HOME/.copilot/oh-my-copilot"
  mkdir -p "$HOME/.copilot/agents"

  # Provide init-memory.sh in expected location so DB bootstrap works
  local script_dir
  script_dir="$(dirname "$SCRIPT")"
  # session-start.sh resolves SCRIPT_DIR from BASH_SOURCE, so we need
  # the init-memory.sh alongside session-start.sh — it's already there
  # since SCRIPT points to the real scripts dir.
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# Experimental advisory tip
# ──────────────────────────────────────────────────────────────────────────────

@test "First run without flag file: shows experimental tip message" {
  # Ensure no flag file exists
  rm -f "$HOME/.copilot/oh-my-copilot/.experimental-advised"

  run bash "$SCRIPT"
  assert_success
  assert_output --partial "Tip: Run '/experimental on'"
}

@test "Second run with flag file already present: tip NOT shown" {
  # Create the flag file before running
  mkdir -p "$HOME/.copilot/oh-my-copilot"
  touch "$HOME/.copilot/oh-my-copilot/.experimental-advised"

  run bash "$SCRIPT"
  assert_success
  refute_output --partial "Tip: Run '/experimental on'"
}

@test "With config.json experimental=true: tip NOT shown" {
  rm -f "$HOME/.copilot/oh-my-copilot/.experimental-advised"
  mkdir -p "$HOME/.copilot"
  cat > "$HOME/.copilot/config.json" <<'EOF'
{
  "experimental": true
}
EOF

  run bash "$SCRIPT"
  assert_success
  refute_output --partial "Tip: Run '/experimental on'"
}

# ──────────────────────────────────────────────────────────────────────────────
# Background session recovery (ralph-loop)
# ──────────────────────────────────────────────────────────────────────────────

@test "Experimental enabled + active ralph-state: shows recovery message" {
  rm -f "$HOME/.copilot/oh-my-copilot/.experimental-advised"
  mkdir -p "$HOME/.copilot"
  cat > "$HOME/.copilot/config.json" <<'EOF'
{
  "experimental": true
}
EOF

  # Create active ralph state
  cat > "$HOME/.copilot/oh-my-copilot/ralph-state.json" <<'EOF'
{
  "active": true,
  "iteration": 3,
  "task": "refactor auth module"
}
EOF

  run bash "$SCRIPT"
  assert_success
  assert_output --partial "Found paused ralph-loop"
  assert_output --partial "iteration 3"
  assert_output --partial "refactor auth module"
}

@test "Without experimental enabled: recovery message NOT shown" {
  rm -f "$HOME/.copilot/oh-my-copilot/.experimental-advised"
  # No config.json → _exp_enabled stays false

  # Create ralph state (should be ignored without experimental)
  cat > "$HOME/.copilot/oh-my-copilot/ralph-state.json" <<'EOF'
{
  "active": true,
  "iteration": 5,
  "task": "some task"
}
EOF

  run bash "$SCRIPT"
  assert_success
  refute_output --partial "Found paused ralph-loop"
}
