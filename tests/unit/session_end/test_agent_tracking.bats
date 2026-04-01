#!/usr/bin/env bats
# session-end.sh track_agent_usage() tests
#
# Tests:
#   1. Agent usage logged when LEARNINGS.md mentions agent name
#   2. Correct agent_id and task_signature fields recorded
#   3. Success outcome (reward=1.0) when no errors in session log
#   4. Failure outcome (reward=-0.5) when 3+ errors in session log
#   5. No duplicate agent entries per single track_agent_usage call

load "../../helpers/common"
load "../../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/session-end.sh"

# Source session-end.sh functions.
# During source: LEARN_PATH is empty and LOG_PATH has only the SESSION_END line,
# so track_agent_usage() finds no agents and is effectively a no-op.
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

  # Initialize DB with full schema (includes agent_usage_log table)
  bash "$SCRIPTS_DIR/init-memory.sh" "$DB_PATH" 2>/dev/null || true

  # Source the script; track_agent_usage runs but is a no-op (no agent mentions)
  source "$SCRIPT" 2>/dev/null || true
}

setup() {
  setup_isolation
  _load_functions
}

teardown() {
  teardown_isolation
}

# ──────────────────────────────────────────────────────────────────────────────
# Agent detection and logging
# ──────────────────────────────────────────────────────────────────────────────

@test "agent usage logged when LEARNINGS.md mentions agent name" {
  local today
  today="$(date '+%Y-%m-%d')"
  echo "## ${today} hephaestus completed a complex refactoring task" > "$LEARN_PATH"

  track_agent_usage

  run sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agent_usage_log WHERE agent_id='hephaestus';"
  assert_output "1"
}

@test "correct agent_id and task_signature fields recorded" {
  local today
  today="$(date '+%Y-%m-%d')"
  echo "## ${today} oracle helped debug the failing test" > "$LEARN_PATH"

  track_agent_usage

  run sqlite3 "$DB_PATH" \
    "SELECT agent_id FROM agent_usage_log ORDER BY id DESC LIMIT 1;"
  assert_output "oracle"

  # oracle maps to task_signature 'debugging' in agent_task_map
  run sqlite3 "$DB_PATH" \
    "SELECT task_signature FROM agent_usage_log ORDER BY id DESC LIMIT 1;"
  assert_output "debugging"
}

# ──────────────────────────────────────────────────────────────────────────────
# Outcome determination
# ──────────────────────────────────────────────────────────────────────────────

@test "success outcome with reward=1.0 when no errors in log" {
  local today
  today="$(date '+%Y-%m-%d')"
  echo "## ${today} hephaestus built the feature successfully" > "$LEARN_PATH"
  # Session log has no error/warning keywords
  echo "[2026-01-01 12:00:00] SESSION_START cwd=/home/test" > "$LOG_PATH"

  track_agent_usage

  run sqlite3 "$DB_PATH" \
    "SELECT outcome FROM agent_usage_log WHERE agent_id='hephaestus' ORDER BY id DESC LIMIT 1;"
  assert_output "success"

  run sqlite3 "$DB_PATH" \
    "SELECT reward FROM agent_usage_log WHERE agent_id='hephaestus' ORDER BY id DESC LIMIT 1;"
  assert_output "1.0"
}

@test "failure outcome with reward=-0.5 when errors in log" {
  local today
  today="$(date '+%Y-%m-%d')"
  echo "## ${today} hephaestus attempted the migration" > "$LEARN_PATH"

  # Write 3+ ERROR lines to session.log (threshold is recent_errors > 2)
  {
    echo "ERROR: database connection failed"
    echo "ERROR: migration script crashed"
    echo "ERROR: fatal rollback error"
  } > "$LOG_PATH"

  track_agent_usage

  run sqlite3 "$DB_PATH" \
    "SELECT outcome FROM agent_usage_log WHERE agent_id='hephaestus' ORDER BY id DESC LIMIT 1;"
  assert_output "failure"

  run sqlite3 "$DB_PATH" \
    "SELECT reward FROM agent_usage_log WHERE agent_id='hephaestus' ORDER BY id DESC LIMIT 1;"
  assert_output "-0.5"
}

# ──────────────────────────────────────────────────────────────────────────────
# Deduplication within a single invocation
# ──────────────────────────────────────────────────────────────────────────────

@test "no duplicate agent entries per single track_agent_usage call" {
  local today
  today="$(date '+%Y-%m-%d')"
  # Mention hephaestus multiple times in today's entries
  cat > "$LEARN_PATH" <<EOF
## ${today} hephaestus started the refactoring
## ${today} hephaestus continued working on the module
## ${today} hephaestus finished the implementation
EOF

  track_agent_usage

  # Should only have 1 entry for hephaestus (dedup within single call)
  run sqlite3 "$DB_PATH" \
    "SELECT COUNT(*) FROM agent_usage_log WHERE agent_id='hephaestus';"
  assert_output "1"
}
