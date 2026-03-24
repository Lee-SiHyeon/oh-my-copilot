#!/usr/bin/env bats
# session-end.sh README 동기화 최종 가드 테스트

load "../../helpers/common"
load "../../helpers/isolation"

TEST_PLUGIN_ROOT=""
TEST_SCRIPT=""
REMOTE_REPO=""
REMOTE_URL=""
BASELINE_COMMIT=""
OMC_DB_PATH=""

setup() {
  setup_isolation

  TEST_PLUGIN_ROOT="$(mktemp -d)"
  TEST_SCRIPT="$TEST_PLUGIN_ROOT/scripts/session-end.sh"
  REMOTE_REPO="$(mktemp -d)"
  OMC_DB_PATH="$HOME/.copilot/oh-my-copilot/omc-memory.db"

  mkdir -p "$TEST_PLUGIN_ROOT/scripts" "$TEST_PLUGIN_ROOT/agents" "$TEST_PLUGIN_ROOT/local"
  cp "$SCRIPTS_DIR/session-end.sh" "$TEST_SCRIPT"
  cp "$SCRIPTS_DIR/init-memory.sh" "$TEST_PLUGIN_ROOT/scripts/init-memory.sh"
  chmod +x "$TEST_SCRIPT"
  chmod +x "$TEST_PLUGIN_ROOT/scripts/init-memory.sh"

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
  git -C "$REMOTE_REPO" init -q --bare
  git -C "$TEST_PLUGIN_ROOT" config user.name "Test User"
  git -C "$TEST_PLUGIN_ROOT" config user.email "test@example.com"
  git -C "$TEST_PLUGIN_ROOT" remote add origin "$REMOTE_REPO"
  git -C "$TEST_PLUGIN_ROOT" add .
  git -C "$TEST_PLUGIN_ROOT" commit -q -m "baseline"
  git -C "$TEST_PLUGIN_ROOT" push -q -u origin main
  REMOTE_URL="$(git -C "$TEST_PLUGIN_ROOT" remote get-url origin)"
  BASELINE_COMMIT="$(git -C "$TEST_PLUGIN_ROOT" rev-parse HEAD)"
}

teardown() {
  [[ -n "$TEST_PLUGIN_ROOT" && -d "$TEST_PLUGIN_ROOT" ]] && rm -rf "$TEST_PLUGIN_ROOT"
  [[ -n "$REMOTE_REPO" && -d "$REMOTE_REPO" ]] && rm -rf "$REMOTE_REPO"
  teardown_isolation
}

@test "README.md 없이 핵심 파일이 바뀌면 sessionEnd가 실패한다" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"

  run bash "$TEST_SCRIPT"

  assert_failure
  assert_output --partial "README.md"

  if [[ -f "$OMC_DB_PATH" ]]; then
    run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT COUNT(*) FROM improvement_candidates;"
    assert_success
    assert_output "0"
  fi
}

@test "README.md도 함께 바뀌면 sessionEnd가 로컬 제안만 큐잉하고 git 상태는 유지한다" {
  echo "updated" >> "$TEST_PLUGIN_ROOT/agents/sample.agent.md"
  echo "docs updated" >> "$TEST_PLUGIN_ROOT/README.md"

  run bash "$TEST_SCRIPT"

  assert_success
  assert_output --partial "Queued shared-source improvement proposal"

  run git -C "$TEST_PLUGIN_ROOT" status --short
  assert_success
  assert_output --partial " M README.md"
  assert_output --partial " M agents/sample.agent.md"

  run git -C "$REMOTE_REPO" rev-parse refs/heads/main
  assert_success
  assert_output "$BASELINE_COMMIT"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT COUNT(*) FROM improvement_candidates;"
  assert_success
  assert_output "1"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT git_remote_name FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output "origin"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT git_remote_url FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output "$REMOTE_URL"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT git_branch FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output "main"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT head_commit FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output "$BASELINE_COMMIT"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT changed_paths FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output --partial "README.md"
  assert_output --partial "agents/sample.agent.md"

  run sqlite3 -batch -noheader "$OMC_DB_PATH" "SELECT status_snapshot FROM improvement_candidates ORDER BY id DESC LIMIT 1;"
  assert_success
  assert_output --partial " M README.md"
  assert_output --partial " M agents/sample.agent.md"
}
