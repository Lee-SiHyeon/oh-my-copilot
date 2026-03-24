#!/usr/bin/env bats
# init-memory.sh 스키마 생성 테스트
#
# 실제 스키마:
#   - 테이블: semantic_memory, meta_policy_rules, agent_q_table, improvement_candidates
#   - meta_policy_rules 시드: 5개 (task_domain: git, file_io, agent×2, nlm)
#   - agent_q_table 시드: 7개

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/init-memory.sh"

setup() {
  setup_isolation
  # 격리된 HOME에 디렉터리 생성 (스크립트가 $HOME/.copilot/oh-my-copilot/omc-memory.db 사용)
  export OMC_MEMORY_DIR="$HOME/.copilot/oh-my-copilot"
  mkdir -p "$OMC_MEMORY_DIR"
}

run_sqlite_query() {
  local query="$1"
  run sqlite3 -batch -noheader "$OMC_MEMORY_DIR/omc-memory.db" "$query"
}

teardown() {
  teardown_isolation
}

@test "omc-memory.db 파일 생성됨" {
  run bash "$SCRIPT"
  assert_success
  assert_file_exists "$OMC_MEMORY_DIR/omc-memory.db"
}

@test "semantic_memory 테이블 존재" {
  bash "$SCRIPT"
  run sqlite3 "$OMC_MEMORY_DIR/omc-memory.db" ".tables"
  assert_output --partial "semantic_memory"
}

@test "meta_policy_rules 테이블 존재" {
  bash "$SCRIPT"
  run sqlite3 "$OMC_MEMORY_DIR/omc-memory.db" ".tables"
  assert_output --partial "meta_policy_rules"
}

@test "agent_q_table 테이블 존재" {
  bash "$SCRIPT"
  run sqlite3 "$OMC_MEMORY_DIR/omc-memory.db" ".tables"
  assert_output --partial "agent_q_table"
}

@test "improvement_candidates 테이블 존재" {
  bash "$SCRIPT"
  run sqlite3 "$OMC_MEMORY_DIR/omc-memory.db" ".tables"
  assert_output --partial "improvement_candidates"
}

@test "meta_policy_rules에 기본 시드 데이터 5개 존재" {
  # 실제 시드: git(1), file_io(1), agent(2), nlm(1) = 5개
  # 컬럼: task_domain, predicate_condition, action_constraint (rule_name 없음)
  bash "$SCRIPT"
  run_sqlite_query "SELECT COUNT(*) FROM meta_policy_rules;"
  assert_output "5"
}

@test "meta_policy_rules에 file_io 도메인 시드 존재" {
  # 파일 삭제 관련 위험 패턴이 시드에 포함되어야 함
  bash "$SCRIPT"
  run_sqlite_query "SELECT COUNT(*) FROM meta_policy_rules WHERE task_domain='file_io';"
  assert_output "1"
}

@test "멱등성: 두 번 실행해도 오류 없음" {
  run bash "$SCRIPT"
  assert_success
  run bash "$SCRIPT"
  assert_success
}

@test "멱등성: 두 번 실행 후 meta_policy_rules 중복 없음" {
  bash "$SCRIPT"
  bash "$SCRIPT"
  run_sqlite_query "SELECT COUNT(*) FROM meta_policy_rules;"
  assert_output "5"
}
