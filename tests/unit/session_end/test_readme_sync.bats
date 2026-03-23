#!/usr/bin/env bats
# session-end.sh README 동기화 최종 가드 테스트

load "../../helpers/common"
load "../../helpers/isolation"

TEST_PLUGIN_ROOT=""
TEST_SCRIPT=""

setup() {
  setup_isolation

  TEST_PLUGIN_ROOT="$(mktemp -d)"
  TEST_SCRIPT="$TEST_PLUGIN_ROOT/scripts/session-end.sh"

  mkdir -p "$TEST_PLUGIN_ROOT/scripts" "$TEST_PLUGIN_ROOT/agents" "$TEST_PLUGIN_ROOT/local"
  cp "$SCRIPTS_DIR/session-end.sh" "$TEST_SCRIPT"
  chmod +x "$TEST_SCRIPT"

  cat > "$TEST_PLUGIN_ROOT/README.md" <<'EOF'
# Test Plugin
EOF
  cat > "$TEST_PLUGIN_ROOT/agents/sample.agent.md" <<'EOF'
# sample agent
EOF
  cat > "$TEST_PLUGIN_ROOT/local/README.md" <<'EOF'
# local readme
EOF
  cat > "$TEST_PLUGIN_ROOT/.gitignore" <<'EOF'
local/agents/
EOF

  git -C "$TEST_PLUGIN_ROOT" init -q -b main
  git -C "$TEST_PLUGIN_ROOT" config user.name "Test User"
  git -C "$TEST_PLUGIN_ROOT" config user.email "test@example.com"
  git -C "$TEST_PLUGIN_ROOT" add .
  git -C "$TEST_PLUGIN_ROOT" commit -q -m "baseline"
}

teardown() {
  [[ -n "$TEST_PLUGIN_ROOT" && -d "$TEST_PLUGIN_ROOT" ]] && rm -rf "$TEST_PLUGIN_ROOT"
  teardown_isolation
}

@test "README.md 없이 핵심 파일이 바뀌면 sessionEnd가 실패한다" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"

  run bash "$TEST_SCRIPT"

  assert_failure
  assert_output --partial "README.md"
}

@test "README.md도 함께 바뀌면 sessionEnd가 통과하고 변경을 정리한다" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"
  echo "docs updated" >> "$TEST_PLUGIN_ROOT/README.md"

  run bash "$TEST_SCRIPT"

  assert_success

  run git -C "$TEST_PLUGIN_ROOT" status --short
  assert_success
  assert_output ""
}
