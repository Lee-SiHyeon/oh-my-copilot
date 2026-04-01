#!/usr/bin/env bats
# session-end.sh migrate_proposals_json_to_sqlite() tests
#
# Tests:
#   1. JSON proposals migrate to SQLite rows
#   2. Duplicate proposals (same contentHash) are deduplicated
#   3. Flag file created after successful migration
#   4. Empty proposals.json handled gracefully (flag created, 0 rows)
#   5. Already-migrated flag prevents re-migration

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/session-end.sh"

# Source session-end.sh functions using the same pattern as test_add_proposal.bats.
# PROPOSALS_PATH is intentionally NOT created before source so that
# migrate_proposals_json_to_sqlite() is a no-op during source time.
_load_functions() {
  export STATE_ROOT="$HOME/.copilot/oh-my-copilot"
  export COPILOT_ROOT="$HOME/.copilot"
  export PROPOSALS_PATH="$STATE_ROOT/proposals.json"
  export DB_PATH="$STATE_ROOT/omc-memory.db"
  export LEARN_PATH="$STATE_ROOT/LEARNINGS.md"
  export LOG_PATH="$COPILOT_ROOT/session.log"
  export TIMESTAMP="2026-01-01 00:00:00"
  export TIMESTAMP_ISO="2026-01-01T00:00:00Z"
  export SCRIPT_DIR="$SCRIPTS_DIR"
  export PLUGIN_ROOT="$(dirname "$SCRIPTS_DIR")"
  export CONSOLIDATE_SCRIPT="$SCRIPTS_DIR/consolidate.sh"

  mkdir -p "$STATE_ROOT" "$COPILOT_ROOT"
  touch "$LEARN_PATH" "$LOG_PATH"

  # Initialize DB with full schema (includes proposals table)
  bash "$SCRIPTS_DIR/init-memory.sh" "$DB_PATH" 2>/dev/null || true

  # Source the script; migration is no-op (PROPOSALS_PATH doesn't exist yet)
  source "$SCRIPT" 2>/dev/null || true

  # Clean up any proposals/flags created during source-time side effects
  # (the script detects git changes in the real plugin repo and auto-queues proposals)
  sqlite3 "$DB_PATH" "DELETE FROM proposals;" 2>/dev/null || true
  rm -f "$PROPOSALS_PATH"
  rm -f "$STATE_ROOT/.proposals_migrated"
}

setup() {
  setup_isolation
  _load_functions
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# Migration correctness
# ──────────────────────────────────────────────────────────────────────────────

@test "JSON proposals migrate to SQLite" {
  cat > "$PROPOSALS_PATH" <<'EOF'
[
  {"contentHash":"abc123","type":"shared-source-change","description":"Fix bug in parser","status":"pending","priority":"normal","filePath":"scripts/foo.sh","suggestedChange":"update logic","timestamp":"2026-01-01T00:00:00Z"},
  {"contentHash":"def456","type":"shared-source-change","description":"Add retry feature","status":"pending","priority":"high","filePath":"scripts/bar.sh","suggestedChange":"new func","timestamp":"2026-01-01T00:00:00Z"}
]
EOF
  rm -f "$STATE_ROOT/.proposals_migrated"

  run migrate_proposals_json_to_sqlite
  assert_success

  run sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM proposals;"
  assert_output "2"

  # Verify content was stored correctly
  run sqlite3 "$DB_PATH" "SELECT content FROM proposals WHERE content_hash='abc123';"
  assert_output "Fix bug in parser"
}

@test "duplicate proposals are deduplicated via INSERT OR IGNORE" {
  cat > "$PROPOSALS_PATH" <<'EOF'
[
  {"contentHash":"same_hash","type":"test-type","description":"First entry","status":"pending","priority":"normal","filePath":"a.sh","suggestedChange":"","timestamp":"2026-01-01T00:00:00Z"},
  {"contentHash":"same_hash","type":"test-type","description":"Second entry","status":"pending","priority":"normal","filePath":"b.sh","suggestedChange":"","timestamp":"2026-01-01T00:00:00Z"}
]
EOF
  rm -f "$STATE_ROOT/.proposals_migrated"

  migrate_proposals_json_to_sqlite

  run sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM proposals;"
  assert_output "1"
}

# ──────────────────────────────────────────────────────────────────────────────
# Flag file behavior
# ──────────────────────────────────────────────────────────────────────────────

@test "flag file created after successful migration" {
  cat > "$PROPOSALS_PATH" <<'EOF'
[
  {"contentHash":"flag_test","type":"test","description":"Flag test","status":"pending","priority":"normal","filePath":"x.sh","suggestedChange":"","timestamp":"2026-01-01T00:00:00Z"}
]
EOF
  rm -f "$STATE_ROOT/.proposals_migrated"

  migrate_proposals_json_to_sqlite

  assert_file_exists "$STATE_ROOT/.proposals_migrated"
}

@test "empty proposals.json handled gracefully" {
  echo "[]" > "$PROPOSALS_PATH"
  rm -f "$STATE_ROOT/.proposals_migrated"

  run migrate_proposals_json_to_sqlite
  assert_success

  # Flag should still be created
  assert_file_exists "$STATE_ROOT/.proposals_migrated"

  # No rows inserted
  run sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM proposals;"
  assert_output "0"
}

@test "already-migrated flag prevents re-migration" {
  cat > "$PROPOSALS_PATH" <<'EOF'
[
  {"contentHash":"should_not_migrate","type":"test","description":"Blocked","status":"pending","priority":"normal","filePath":"z.sh","suggestedChange":"","timestamp":"2026-01-01T00:00:00Z"}
]
EOF
  # Create flag BEFORE calling migration
  touch "$STATE_ROOT/.proposals_migrated"

  migrate_proposals_json_to_sqlite

  # No rows should have been inserted — migration was skipped
  run sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM proposals;"
  assert_output "0"
}
