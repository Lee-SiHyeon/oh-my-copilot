#!/usr/bin/env bats
# consolidate.sh Step 3 — Memory Ingestion 테스트
#
# 테스트 대상: LEARNINGS.md에서 마지막 10개의 '['로 시작하는 라인을 읽어
# semantic_memory 테이블에 삽입하는 기능
#
# Low-signal 필터:
#   - 30자 미만 라인 제외
#   - "No agent changes" 포함 라인 제외
#
# 카테고리 자동 감지:
#   - agent, error, pattern, tool 키워드 포함 시 해당 카테고리
#   - 기본: general
#
# 테스트 전략: 격리된 DB와 LEARNINGS.md를 생성하고, consolidate.sh를
# 실행한 뒤 semantic_memory 테이블의 내용을 검증한다.

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/consolidate.sh"

setup() {
  setup_isolation
  export OMC_DIR="$HOME/.copilot/oh-my-copilot"
  export DB_PATH="$OMC_DIR/omc-memory.db"
  export LEARN_PATH="$OMC_DIR/LEARNINGS.md"
  mkdir -p "$OMC_DIR"

  # Bootstrap DB with full schema via init-memory.sh
  bash "$SCRIPTS_DIR/init-memory.sh" "$DB_PATH"
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# Valid input tests
# ──────────────────────────────────────────────────────────────────────────────

@test "Memory ingestion: valid learning lines are ingested correctly" {
  # Create LEARNINGS.md with valid learning entries
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] executor agent successfully completed file refactoring task in 45 seconds
[2024-01-02] Error handling pattern identified: always validate inputs before processing
[2024-01-03] Tool usage optimization: batch file operations reduce I/O overhead
[2024-01-04] Pattern detected: immutable data structures prevent side effects
[2024-01-05] Agent coordination improved with explicit handoff protocols
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Verify all 5 valid entries were ingested
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory;"
  assert_output "5"

  # Verify category detection works
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT category FROM semantic_memory WHERE fact_content LIKE '%executor agent%';"
  assert_output "agent"

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT category FROM semantic_memory WHERE fact_content LIKE '%Error handling%';"
  assert_output "error"

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT category FROM semantic_memory WHERE fact_content LIKE '%Tool usage%';"
  assert_output "tool"

  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT category FROM semantic_memory WHERE fact_content LIKE '%Pattern detected%';"
  assert_output "pattern"
}

@test "Memory ingestion: only last 10 lines are processed" {
  # Create LEARNINGS.md with 15 entries (only last 10 should be ingested)
  for i in {1..15}; do
    echo "[$(date +%Y-%m-%d)] Learning entry number $i describes an important pattern discovered during session execution" >> "$LEARN_PATH"
  done

  # Pre-seed one entry to distinguish from ingested ones
  sqlite3 "$DB_PATH" "INSERT INTO semantic_memory (fact_content, category)
    VALUES ('pre-existing entry', 'general');"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Should have pre-existing entry + 10 new entries = 11 total
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory;"
  assert_output "11"
}

@test "Memory ingestion: token weight is calculated correctly" {
  # Create a learning entry with specific length
  local line="[2024-01-01] This is a learning entry with exactly one hundred characters to test token weight calculation which should be capped at 100 tokens max total"
  echo "$line" >> "$LEARN_PATH"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Token weight = length / 10, capped at 100
  # This line is ~160 chars, so weight should be capped at 100
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT token_weight FROM semantic_memory WHERE fact_content LIKE '%one hundred characters%';"
  assert_output "100"
}

# ──────────────────────────────────────────────────────────────────────────────
# Empty input tests
# ──────────────────────────────────────────────────────────────────────────────

@test "Memory ingestion: empty LEARNINGS.md is handled gracefully" {
  # Create empty LEARNINGS.md
  touch "$LEARN_PATH"

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # No entries should be ingested
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory;"
  # Only seed data from init-memory.sh should exist
  [ "$output" -le 10 ]  # Allow for seed data
}

@test "Memory ingestion: LEARNINGS.md with no bracket lines is handled" {
  # Create LEARNINGS.md with no valid learning lines
  cat > "$LEARN_PATH" <<'EOF'
This is a regular line
Another line without brackets
Yet another line
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # No new entries should be ingested (only seed data may exist)
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE 'This is a regular%';"
  assert_output "0"
}

@test "Memory ingestion: missing LEARNINGS.md is handled gracefully" {
  # Don't create LEARNINGS.md at all

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Should succeed without error, just skip ingestion
  assert_output --partial "LEARNINGS.md not found"
}

# ──────────────────────────────────────────────────────────────────────────────
# Malformed input tests
# ──────────────────────────────────────────────────────────────────────────────

@test "Memory ingestion: low-signal lines (< 30 chars) are filtered out" {
  # Create LEARNINGS.md with short and long lines
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] Short
[2024-01-02] This is a valid learning entry that exceeds the minimum thirty character threshold for ingestion
[2024-01-03] Another medium length entry that should be processed correctly
[2024-01-04] Tiny
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Only 2 valid entries should be ingested (short lines filtered)
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE '%[2024%';"
  assert_output "2"

  # Verify short lines were not ingested
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content = '[2024-01-01] Short';"
  assert_output "0"
}

@test "Memory ingestion: 'No agent changes' boilerplate is filtered out" {
  # Create LEARNINGS.md with boilerplate lines
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] No agent changes detected in this session
[2024-01-02] This is a valid learning about agent coordination patterns
[2024-01-03] No agent changes - nothing to report here
[2024-01-04] Another valid entry describing tool usage optimization
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Only 2 valid entries should be ingested (boilerplate filtered)
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE '%[2024%';"
  assert_output "2"

  # Verify boilerplate was not ingested
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE '%No agent changes%';"
  assert_output "0"
}

@test "Memory ingestion: SQL injection is prevented with special characters" {
  # Create LEARNINGS.md with quotes and special characters
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] Learning with 'single quotes' and "double quotes" should be escaped properly
[2024-01-02] Test with semicolons; DROP TABLE semantic_memory; -- should not execute
[2024-01-03] Entry with backticks `code` and other special chars @#$%^&*()
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # All entries should be ingested safely (SQL injection prevented)
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE '%[2024%';"
  assert_output "3"

  # Verify the table still exists and works (DROP TABLE didn't execute)
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM sqlite_master WHERE name='semantic_memory';"
  assert_output "1"
}

@test "Memory ingestion: duplicate entries are ignored" {
  # Create LEARNINGS.md with duplicate entries
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] This is a unique learning entry that should be ingested
[2024-01-02] This is a unique learning entry that should be ingested
[2024-01-03] Another different learning entry for testing
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Due to INSERT OR IGNORE, only 2 unique entries should exist
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT COUNT(*) FROM semantic_memory WHERE fact_content LIKE '%This is a unique%';"
  assert_output "1"
}

@test "Memory ingestion: category detection defaults to general" {
  # Create LEARNINGS.md with entry that doesn't match any category keywords
  cat > "$LEARN_PATH" <<'EOF'
[2024-01-01] This is a general system observation without specific keywords
EOF

  run bash "$SCRIPT" "$DB_PATH" "$LEARN_PATH"
  assert_success

  # Verify category defaults to 'general'
  run sqlite3 -batch -noheader "$DB_PATH" \
    "SELECT category FROM semantic_memory WHERE fact_content LIKE '%general system observation%';"
  assert_output "general"
}
