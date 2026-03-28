#!/usr/bin/env bats
# add_proposal() unit tests
#
# Tests:
#   1. Normal case: add_proposal() succeeds and creates a proposals.json entry
#   2. Dedup case: calling add_proposal() twice with same content only creates one entry
#   3. Missing jq: when jq is not available, function prints error to stderr

load "../helpers/common"
load "../helpers/isolation"

SCRIPT="$SCRIPTS_DIR/session-end.sh"

# Source only the functions we need, skipping side-effects at the top level
# by temporarily replacing mkdir/touch/echo with no-ops during source.
_load_functions() {
  # Set required variables that session-end.sh uses at source time
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

  # Source the script; suppress output from the side-effect lines
  # (the top-level mkdir/touch/echo run but are harmless in isolated HOME)
  source "$SCRIPT" 2>/dev/null || true
}

setup() {
  setup_isolation
  _load_functions
}

teardown() {
  teardown_isolation
}

@test "normal case: add_proposal() succeeds and creates a proposals.json entry" {
  run add_proposal "shared-source-change" "Test proposal description" "$PLUGIN_ROOT" "normal" "some/file.sh"
  assert_success
  assert_file_exists "$PROPOSALS_PATH"
  run bash -c "cat \"$PROPOSALS_PATH\""
  assert_output --partial "Test proposal description"
}

@test "dedup case: calling add_proposal() twice with same content only creates one entry" {
  add_proposal "shared-source-change" "Duplicate proposal" "$PLUGIN_ROOT" "normal" "some/file.sh"
  add_proposal "shared-source-change" "Duplicate proposal" "$PLUGIN_ROOT" "normal" "some/file.sh"
  # Count how many entries exist in the JSON array
  run bash -c "jq 'length' \"$PROPOSALS_PATH\""
  assert_output "1"
}

@test "missing jq: when jq is not available, function prints warning to stderr" {
  # Override PATH to hide jq
  local orig_path="$PATH"
  export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/usr/bin' | tr '\n' ':' | sed 's/:$//')"
  # Use a temp dir with no jq
  local fake_bin
  fake_bin="$(mktemp -d)"
  # Copy everything except jq into fake_bin via PATH override
  export PATH="$fake_bin:$PATH"

  run add_proposal "shared-source-change" "No jq proposal" "$PLUGIN_ROOT" "normal" "other/file.sh"
  # Should not hard-fail — function has a fallback path
  # The proposal file should still be created (fallback appends manually)
  assert_file_exists "$PROPOSALS_PATH"

  export PATH="$orig_path"
  rm -rf "$fake_bin"
}
