#!/usr/bin/env bats
# init-memory.sh DB bootstrap deep tests
#
# Existing test_schema_creation.bats covers basic 4-table existence + seeds.
# This file covers:
#   - All 7 tables created (including permission_cache, proposals, agent_usage_log)
#   - Column schema verification for newer tables
#   - Idempotency (no duplication on double-run)
#   - Custom DB_PATH argument support

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/init-memory.sh"

setup() {
  setup_isolation
  export OMC_MEMORY_DIR="$HOME/.copilot/oh-my-copilot"
  mkdir -p "$OMC_MEMORY_DIR"
}

teardown() {
  teardown_isolation
}

# Helper: query the default DB
run_query() {
  local query="$1"
  run sqlite3 -batch -noheader "$OMC_MEMORY_DIR/omc-memory.db" "$query"
}

# Helper: get column names for a table (pipe-separated PRAGMA output, field 2)
get_columns() {
  local db="$1" table="$2"
  sqlite3 -batch -noheader "$db" "PRAGMA table_info('$table');" | \
    cut -d'|' -f2 | sort
}

# ──────────────────────────────────────────────────────────────────────────────
# Complete table set verification
# ──────────────────────────────────────────────────────────────────────────────

@test "All 7 tables are created after init-memory.sh" {
  bash "$SCRIPT"
  local db="$OMC_MEMORY_DIR/omc-memory.db"

  for table in semantic_memory meta_policy_rules agent_q_table \
               improvement_candidates permission_cache proposals agent_usage_log; do
    run sqlite3 -batch -noheader "$db" \
      "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';"
    [ "$output" = "1" ] || {
      echo "Missing table: $table" >&2
      return 1
    }
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Idempotency
# ──────────────────────────────────────────────────────────────────────────────

@test "Idempotent: running twice does not error" {
  run bash "$SCRIPT"
  assert_success
  run bash "$SCRIPT"
  assert_success
}

@test "Idempotent: running twice preserves exact seed counts" {
  bash "$SCRIPT"
  bash "$SCRIPT"

  # meta_policy_rules seed: exactly 5 rows
  run_query "SELECT COUNT(*) FROM meta_policy_rules;"
  assert_output "5"

  # agent_q_table seed: exactly 7 rows
  run_query "SELECT COUNT(*) FROM agent_q_table;"
  assert_output "7"
}

# ──────────────────────────────────────────────────────────────────────────────
# Custom DB_PATH argument
# ──────────────────────────────────────────────────────────────────────────────

@test "Custom DB_PATH argument creates DB at specified location" {
  local custom_dir="$HOME/custom-db-dir"
  local custom_db="$custom_dir/test.db"
  mkdir -p "$custom_dir"

  run bash "$SCRIPT" "$custom_db"
  assert_success
  assert_file_exists "$custom_db"

  # Verify tables exist in custom DB
  run sqlite3 -batch -noheader "$custom_db" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type='table';"
  # Should have at least 7 tables
  [ "$output" -ge 7 ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Column schema verification: permission_cache
# ──────────────────────────────────────────────────────────────────────────────

@test "permission_cache has correct columns" {
  bash "$SCRIPT"
  local db="$OMC_MEMORY_DIR/omc-memory.db"

  for col in tool_name pattern_hash decision risk_level created_at expires_at; do
    run sqlite3 -batch -noheader "$db" \
      "SELECT COUNT(*) FROM pragma_table_info('permission_cache') WHERE name='$col';"
    [ "$output" = "1" ] || {
      echo "Missing column in permission_cache: $col" >&2
      return 1
    }
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Column schema verification: agent_usage_log
# ──────────────────────────────────────────────────────────────────────────────

@test "agent_usage_log has correct columns" {
  bash "$SCRIPT"
  local db="$OMC_MEMORY_DIR/omc-memory.db"

  for col in session_id task_signature agent_id outcome reward created_at; do
    run sqlite3 -batch -noheader "$db" \
      "SELECT COUNT(*) FROM pragma_table_info('agent_usage_log') WHERE name='$col';"
    [ "$output" = "1" ] || {
      echo "Missing column in agent_usage_log: $col" >&2
      return 1
    }
  done
}
