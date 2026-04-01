#!/usr/bin/env bats
# consolidate.sh Step 5 — Garbage Collection 테스트
#
# GC 대상:
#   5a. improvement_candidates: created_at > 90일 → 삭제
#   5c. permission_cache: expires_at < now → 삭제
#   Step 2. priority-decay eviction: 낮은 점수 + 30일 이상 → 삭제
#
# 테스트 전략: 격리된 DB를 직접 생성하고, 타임스탬프를 조작한 데이터를 삽입,
# consolidate.sh를 실행한 뒤 남은 행 수를 검증한다.

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/consolidate.sh"

setup() {
  setup_isolation
  export OMC_DIR="$HOME/.copilot/oh-my-copilot"
  export DB_PATH="$OMC_DIR/omc-memory.db"
  export LEARN_PATH="$OMC_DIR/LEARNINGS.md"
  mkdir -p "$OMC_DIR"
  touch "$LEARN_PATH"

  # Bootstrap DB with full schema via init-memory.sh
  bash "$SCRIPTS_DIR/init-memory.sh" "$DB_PATH"
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# 5a. improvement_candidates GC (90-day cutoff)
# ──────────────────────────────────────────────────────────────────────────────

@test "GC: improvement_candidates older than 90 days are removed" {
  # Insert a record dated 100 days ago
  sqlite3 "$DB_PATH" "INSERT INTO improvement_candidates
    (created_at, plugin_root, changed_paths, status_snapshot)
    VALUES (datetime('now', '-100 days'), '/test', 'a.sh', 'M a.sh');"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM improvement_candidates;"
  assert_output "0"
}

@test "GC: improvement_candidates newer than 90 days are preserved" {
  # Insert a recent record (10 days ago)
  sqlite3 "$DB_PATH" "INSERT INTO improvement_candidates
    (created_at, plugin_root, changed_paths, status_snapshot)
    VALUES (datetime('now', '-10 days'), '/test', 'b.sh', 'M b.sh');"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM improvement_candidates;"
  assert_output "1"
}

# ──────────────────────────────────────────────────────────────────────────────
# 5c. permission_cache GC (expired entries)
# ──────────────────────────────────────────────────────────────────────────────

@test "GC: expired permission_cache entries are removed" {
  # Insert an already-expired entry
  sqlite3 "$DB_PATH" "INSERT INTO permission_cache
    (tool_name, pattern_hash, decision, risk_level, created_at, expires_at)
    VALUES ('bash', 'abc123', 'allow', 'low',
            datetime('now', '-10 days'), datetime('now', '-1 day'));"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM permission_cache;"
  assert_output "0"
}

@test "GC: non-expired permission_cache entries are preserved" {
  # Insert an entry that expires in the future
  sqlite3 "$DB_PATH" "INSERT INTO permission_cache
    (tool_name, pattern_hash, decision, risk_level, created_at, expires_at)
    VALUES ('bash', 'def456', 'deny', 'high',
            datetime('now'), datetime('now', '+7 days'));"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM permission_cache;"
  assert_output "1"
}

# ──────────────────────────────────────────────────────────────────────────────
# Empty tables — no errors
# ──────────────────────────────────────────────────────────────────────────────

@test "GC: empty tables handled without error" {
  # Ensure improvement_candidates and permission_cache are empty
  sqlite3 "$DB_PATH" "DELETE FROM improvement_candidates;"
  sqlite3 "$DB_PATH" "DELETE FROM permission_cache;"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Priority-decay eviction (semantic_memory)
# ──────────────────────────────────────────────────────────────────────────────

@test "Priority-decay eviction: old low-score semantic_memory entries are removed" {
  # Clear seed data first for a clean test
  sqlite3 "$DB_PATH" "DELETE FROM semantic_memory;"

  # Insert a very old entry with low importance and low access → low priority score
  # Score = (base_importance * access_count) / (days + 1)
  # Score = (0.01 * 1) / (200 + 1) ≈ 0.00005 < 0.01 threshold → evicted
  sqlite3 "$DB_PATH" "INSERT INTO semantic_memory
    (fact_content, category, token_weight, base_importance, access_count,
     creation_time, last_accessed)
    VALUES ('old low priority fact', 'general', 5, 0.01, 1,
            datetime('now', '-200 days'), datetime('now', '-200 days'));"

  # Insert a recent entry with decent score → should be preserved
  # Score = (1.0 * 10) / (1 + 1) = 5.0 >> 0.01
  sqlite3 "$DB_PATH" "INSERT INTO semantic_memory
    (fact_content, category, token_weight, base_importance, access_count,
     creation_time, last_accessed)
    VALUES ('recent high priority fact', 'general', 10, 1.0, 10,
            datetime('now', '-5 days'), datetime('now'));"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Only the high-priority entry should remain
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory;"
  assert_output "1"

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT fact_content FROM semantic_memory;"
  assert_output "recent high priority fact"
}
