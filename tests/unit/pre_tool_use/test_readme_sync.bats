#!/usr/bin/env bats
# pre-tool-use.sh README 동기화 가드 테스트

load "../../helpers/common"
load "../../helpers/isolation"

TEST_PLUGIN_ROOT=""
TEST_SCRIPT=""

setup() {
  setup_isolation

  TEST_PLUGIN_ROOT="$(mktemp -d)"
  TEST_SCRIPT="$TEST_PLUGIN_ROOT/scripts/pre-tool-use.sh"

  mkdir -p "$TEST_PLUGIN_ROOT/scripts" "$TEST_PLUGIN_ROOT/agents" "$TEST_PLUGIN_ROOT/local"
  cp "$SCRIPTS_DIR/pre-tool-use.sh" "$TEST_SCRIPT"
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

run_pre_tool_use() {
  local tool_name="$1"
  local tool_args="$2"

  printf '{"toolName":"%s","toolArgs":"%s"}' "$tool_name" "$tool_args" | bash "$TEST_SCRIPT"
}

@test "README.md 없이 핵심 파일이 바뀌면 ask 결정 반환" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"

  run run_pre_tool_use "bash" "echo safe command"

  assert_success
  assert_output --partial '"permissionDecision":"ask"'
  assert_output --partial 'README.md'
}

@test "README.md도 함께 바뀌면 README 동기화 ask를 내지 않는다" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"
  echo "docs updated" >> "$TEST_PLUGIN_ROOT/README.md"

  run run_pre_tool_use "bash" "echo safe command"

  assert_success
  refute_output --partial '"permissionDecision":"ask"'
}
