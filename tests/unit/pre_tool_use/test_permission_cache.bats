#!/usr/bin/env bats
# pre-tool-use.sh permission cache tests
#
# Tests:
#   1. compute_pattern_hash generates consistent, deterministic hashes
#   2. Cache hit returns saved decision (Cached permission)
#   3. Cache miss falls through without cached output
#   4. Expired cache entries are not matched
#   5. High-risk cached entry does not bypass danger patterns
#   6. cache_permission skips high-risk entries (no DB insert)

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/pre-tool-use.sh"

# Extract pure utility functions from the script for direct testing.
# These functions have no side effects and can be eval'd safely.
_extract_functions() {
  eval "$(sed -n '/^compute_pattern_hash()/,/^}/p' "$SCRIPT")"
  eval "$(sed -n '/^cache_permission()/,/^}/p' "$SCRIPT")"
}

setup() {
  setup_isolation
  mkdir -p "$HOME/.copilot/oh-my-copilot"
  # Initialize DB with full schema (includes permission_cache table)
  bash "$SCRIPTS_DIR/init-memory.sh" 2>/dev/null
  DB_PATH="$HOME/.copilot/oh-my-copilot/omc-memory.db"
  _extract_functions
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# Hash function consistency
# ──────────────────────────────────────────────────────────────────────────────

@test "compute_pattern_hash generates consistent hash from tool_name:tool_args" {
  local hash1 hash2 hash3
  hash1="$(compute_pattern_hash "bash" "echo hello")"
  hash2="$(compute_pattern_hash "bash" "echo hello")"
  hash3="$(compute_pattern_hash "bash" "echo different")"

  # Same inputs produce same hash
  [[ "$hash1" == "$hash2" ]]
  # Hash is non-empty
  [[ -n "$hash1" ]]
  # Different inputs produce different hash
  [[ "$hash1" != "$hash3" ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# Cache hit / miss / expiry
# ──────────────────────────────────────────────────────────────────────────────

@test "cache hit returns saved decision" {
  local hash
  hash="$(compute_pattern_hash "bash" "echo hello")"

  # Pre-seed an allow entry in the permission cache
  sqlite3 "$DB_PATH" \
    "INSERT INTO permission_cache (tool_name, pattern_hash, decision, risk_level)
     VALUES ('bash', '${hash}', 'allow', 'low');"

  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"echo hello\"}' | bash '$SCRIPT'"
  assert_success
  assert_output --partial "Cached permission"
}

@test "cache miss falls through without cached output" {
  # Empty cache — no matching entry for this command
  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"echo unique_test_cmd_12345\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "Cached permission"
}

@test "expired cache entries are not matched" {
  local hash
  hash="$(compute_pattern_hash "bash" "ls -la")"

  # Insert a cache entry that expired yesterday
  sqlite3 "$DB_PATH" \
    "INSERT INTO permission_cache (tool_name, pattern_hash, decision, risk_level, expires_at)
     VALUES ('bash', '${hash}', 'allow', 'low', datetime('now', '-1 day'));"

  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"ls -la\"}' | bash '$SCRIPT'"
  assert_success
  refute_output --partial "Cached permission"
}

# ──────────────────────────────────────────────────────────────────────────────
# Danger pattern interaction with cache
# ──────────────────────────────────────────────────────────────────────────────

@test "high-risk cached entry does not bypass danger patterns" {
  local hash
  hash="$(compute_pattern_hash "bash" "rm -rf /")"

  # Insert a cache entry with risk_level='high' — cache lookup filters these out
  sqlite3 "$DB_PATH" \
    "INSERT INTO permission_cache (tool_name, pattern_hash, decision, risk_level)
     VALUES ('bash', '${hash}', 'allow', 'high');"

  run bash -c "echo '{\"toolName\":\"bash\",\"toolArgs\":\"rm -rf /\"}' | bash '$SCRIPT'"
  assert_success
  # Danger pattern should still trigger "ask"
  assert_output --partial "ask"
  refute_output --partial "Cached permission"
}

# ──────────────────────────────────────────────────────────────────────────────
# cache_permission function behavior
# ──────────────────────────────────────────────────────────────────────────────

@test "cache_permission skips high-risk entries" {
  cache_permission "bash" "testhash_high_risk" "allow" "high"

  run sqlite3 "$DB_PATH" \
    "SELECT COUNT(*) FROM permission_cache WHERE pattern_hash='testhash_high_risk';"
  assert_output "0"
}
